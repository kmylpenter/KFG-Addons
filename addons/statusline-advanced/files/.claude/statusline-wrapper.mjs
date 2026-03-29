#!/usr/bin/env node
// KFG Statusline v8.1 - ctx% │ model/ctx │ EFFORT │ project + changed files
// Effort detection: transcript JSONL > settings.json (same approach as ccstatusline)

import { readFileSync, existsSync } from 'fs';
import { basename, join, relative, isAbsolute } from 'path';
import { tmpdir, homedir } from 'os';

const ESC = '\x1b';
const reset = `${ESC}[0m`;
const c_blue = `${ESC}[38;5;39m`;
const c_red = `${ESC}[38;5;196m`;
const c_cyan = `${ESC}[38;5;44m`;
const c_dim = `${ESC}[38;5;240m`;
const c_yellow = `${ESC}[38;5;220m`;
const c_violet = `${ESC}[38;5;135m`;

const SEP = `${c_dim} │ ${reset}`;

function getCtxColor(pct) {
  if (pct >= 85) return `${ESC}[38;5;196m`;
  if (pct >= 75) return `${ESC}[38;5;202m`;
  if (pct >= 65) return `${ESC}[38;5;208m`;
  if (pct >= 55) return `${ESC}[38;5;226m`;
  if (pct >= 40) return `${ESC}[38;5;154m`;
  return `${ESC}[38;5;46m`;
}

function getEffortColor(level) {
  if (level === 'max') return c_violet;
  if (level === 'high') return c_blue;
  if (level === 'medium') return c_yellow;
  if (level === 'low') return c_dim;
  return c_dim; // unknown/pending
}

function shortModel(model, ctxWindowSize) {
  const id = model?.id || '';
  const name = model?.display_name || '';
  let ver = '';
  let m;
  if ((m = name.match(/(\d+\.\d+)/))) ver = m[1];
  else if ((m = id.match(/(\d+)-(\d+)-\d{8}/))) ver = `${m[1]}.${m[2]}`;
  else if ((m = id.match(/(\d+)-\d{8}/))) ver = m[1];
  else if ((m = id.match(/(\d+)-(\d+)/))) ver = `${m[1]}.${m[2]}`;

  const raw = id || name;
  let prefix = 'C';
  if (/opus/i.test(raw)) prefix = 'O';
  else if (/sonnet/i.test(raw)) prefix = 'S';
  else if (/haiku/i.test(raw)) prefix = 'H';

  let ctxSize = '';
  if (ctxWindowSize >= 1000000) ctxSize = `/${Math.round(ctxWindowSize / 1000000)}M`;
  else if (ctxWindowSize >= 1000) ctxSize = `/${Math.round(ctxWindowSize / 1000)}k`;

  return `${prefix}${ver}${ctxSize}`;
}

// Strip ANSI escape codes from text
function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, '');
}

// Read effort from transcript JSONL (per-session, based on ccstatusline approach)
// Scans from end for last /model or /effort command output
// Two formats:
//   /model: "<local-command-stdout>Set model to X with Y effort</local-command-stdout>"
//   /effort: "<local-command-stdout>Set effort level to Y ...</local-command-stdout>"
const MODEL_EFFORT_REGEX = /with\s+(low|medium|high|max)\s+effort/i;
const DIRECT_EFFORT_REGEX = /Set effort level to\s+(low|medium|high|max)/i;
// /effort command entry: <command-name>/effort</command-name>...<command-args>max</command-args>
const EFFORT_CMD_REGEX = /<command-name>\/effort<\/command-name>[\s\S]*<command-args>(low|medium|high|max)<\/command-args>/i;

function readEffortFromTranscript(transcriptPath) {
  if (!transcriptPath || !existsSync(transcriptPath)) return null;
  try {
    let content = readFileSync(transcriptPath, 'utf8');
    if (content.charCodeAt(0) === 0xFEFF) content = content.substring(1);
    const lines = content.split('\n');
    // Scan from end (most recent first)
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (!line) continue;
      if (!line.includes('effort') && !line.includes('Set model to')) continue;
      try {
        const entry = JSON.parse(line);
        const text = entry?.message?.content;
        if (typeof text !== 'string') continue;
        const clean = stripAnsi(text);
        // /effort command entry (most reliable — parses user's actual command args)
        const cmdMatch = EFFORT_CMD_REGEX.exec(clean);
        if (cmdMatch) return cmdMatch[1].toLowerCase();
        // /effort stdout: "Set effort level to X ..."
        const directMatch = DIRECT_EFFORT_REGEX.exec(clean);
        if (directMatch) return directMatch[1].toLowerCase();
        // /model command: "Set model to X with Y effort"
        if (clean.includes('Set model to')) {
          const modelMatch = MODEL_EFFORT_REGEX.exec(clean);
          if (modelMatch) return modelMatch[1].toLowerCase();
          // /model without effort = effort was reset
          if (clean.includes('<local-command-stdout>Set model to')) return null;
        }
      } catch {}
    }
  } catch {}
  return null;
}

function resolveEffort(transcriptPath) {
  return readEffortFromTranscript(transcriptPath)
    || process.env.CLAUDE_CODE_EFFORT_LEVEL?.toLowerCase()
    || 'high';
}

// Smart display names: basename if unique, parent/basename if duplicated
function smartDisplayNames(fullPaths, cwd) {
  const valid = fullPaths.filter(f => f.includes('/') || f.includes('\\'));

  const deduped = [];
  const pathSet = new Set();
  for (let i = valid.length - 1; i >= 0; i--) {
    if (!pathSet.has(valid[i])) {
      pathSet.add(valid[i]);
      deduped.unshift(valid[i]);
    }
  }

  const baseCount = {};
  for (const f of deduped) {
    const b = basename(f);
    baseCount[b] = (baseCount[b] || 0) + 1;
  }

  return deduped.map(f => {
    const b = basename(f);
    if (baseCount[b] <= 1) return b;

    const rel = relative(cwd, f).replace(/\\/g, '/');
    if (!rel.startsWith('..') && !isAbsolute(rel)) {
      const parts = rel.split('/');
      if (parts.length >= 2) return parts.slice(-2).join('/');
      return rel;
    }
    return '~/' + b;
  });
}

try {
  let input = readFileSync(0, 'utf8');
  if (input.charCodeAt(0) === 0xFEFF) input = input.substring(1);
  if (!input.trim()) process.exit(0);

  const data = JSON.parse(input);

  // Context %
  let ctxPct = 0;
  let ctxWindowSize = 0;
  if (data.context_window) {
    ctxWindowSize = data.context_window.context_window_size || 0;
    if (data.context_window.used_percentage != null) {
      ctxPct = data.context_window.used_percentage;
    } else if (ctxWindowSize > 0 && data.context_window.current_usage) {
      const u = data.context_window.current_usage;
      const used = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
      ctxPct = Math.round((used / ctxWindowSize) * 100);
    }
  }

  const ctxColor = getCtxColor(ctxPct);
  const ctxStr = ctxPct > 100 ? '100%+' : `${ctxPct}%`;
  const modelName = shortModel(data.model, ctxWindowSize);
  const projectName = basename(data.cwd || data.workspace?.project_dir || '');
  const cwd = data.cwd || data.workspace?.project_dir || '';

  // Effort level: transcript (per-session) > settings.json (global)
  const effort = resolveEffort(data.transcript_path);
  const effortColor = getEffortColor(effort);
  const effortIcon = `\x1b[1m${effort.toUpperCase()}\x1b[22m`;

  // Changed files (from PostToolUse hook)
  const sessionId = data.session_id || 'default';
  const trackFile = join(tmpdir(), `claude-changed-files-${sessionId}.json`);
  let rawFiles = [];
  if (existsSync(trackFile)) {
    try { rawFiles = JSON.parse(readFileSync(trackFile, 'utf8')); } catch {}
  }

  const fileNames = smartDisplayNames(rawFiles, cwd);

  // Line 1: ctx% │ model │ EFFORT │ project
  const parts = [
    `${ctxColor}${ctxStr}${reset}`,
    `${c_blue}${modelName}${reset}`,
    `${effortColor}${effortIcon}${reset}`,
    `${c_red}${projectName}${reset}`,
  ];

  let output = parts.join(SEP);

  // Lines 2+: changed files (cyan names, dim dot separators)
  if (fileNames.length > 0) {
    const maxW = 50;
    const recent = fileNames.slice(-10);
    const lines = [''];
    for (const f of recent) {
      const cur = lines[lines.length - 1];
      const nextVis = cur ? `${cur} · ${f}` : f;
      if (nextVis.length > maxW && cur) {
        if (lines.length >= 4) break;
        lines.push(f);
      } else {
        lines[lines.length - 1] = nextVis;
      }
    }
    for (const line of lines) {
      if (line) {
        const colored = line.split(' · ').join(`${reset}${c_dim} · ${c_cyan}`);
        output += `\n${c_cyan}${colored}${reset}`;
      }
    }
  }

  process.stdout.write(output + '\n');
} catch {
  process.exit(0);
}
