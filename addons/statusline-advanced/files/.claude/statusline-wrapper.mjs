#!/usr/bin/env node
// KFG Statusline Wrapper v6.0 (Node.js)
// Rewritten from PowerShell v5.6 for ~200-500ms faster startup
// Maintains same cache format and output as v5.6
//
// Rzad 1: Model/User | ctx%/compacts
// Rzad 2: czas/typing  | turns/AI_chars
// Rzad 3: tokens/prompts | cost/cost_t

import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync, openSync, readSync, closeSync, unlinkSync, renameSync } from 'fs';
import { join, basename } from 'path';
import { tmpdir } from 'os';

// === ANSI COLORS ===
const ESC = '\x1b';
const reset = `${ESC}[0m`;
const c_red = `${ESC}[38;5;196m`;
const c_green = `${ESC}[38;5;46m`;
const c_lime = `${ESC}[38;5;154m`;
const c_yellow = `${ESC}[38;5;226m`;
const c_orange = `${ESC}[38;5;208m`;
const c_orange_red = `${ESC}[38;5;202m`;
const c_blue = `${ESC}[38;5;39m`;
const c_purple = `${ESC}[38;5;171m`;

const HOME = process.env.USERPROFILE || process.env.HOME || '';
const CACHE_DIR = join(HOME, '.claude', 'statusline-cache');

// === HELPER FUNCTIONS ===

// Read JSON file with BOM stripping (PS1 files often have BOM)
function readJsonSafe(filePath) {
  let content = readFileSync(filePath, 'utf8');
  if (content.charCodeAt(0) === 0xFEFF) content = content.substring(1);
  return JSON.parse(content);
}

function getCtxColor(pct) {
  if (pct >= 85) return c_red;
  if (pct >= 75) return c_orange_red;
  if (pct >= 65) return c_orange;
  if (pct >= 55) return c_yellow;
  if (pct >= 40) return c_lime;
  return c_green;
}

function formatNumber(num, suffix = '') {
  if (num >= 1000000) {
    // m20: Use Floor for M to avoid premature "1.0M" for 999.9k
    const v = Math.floor(num / 100000) / 10;
    return `${v}M${suffix}`;
  }
  if (num >= 1000) {
    return `${(num / 1000).toFixed(1)}k${suffix}`;
  }
  return `${num}${suffix}`;
}

function formatTime(seconds) {
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h${mins}m`;
  return `${mins}m`;
}

function formatCost(cost) {
  if (cost >= 1000) return `\$${(cost / 1000).toFixed(1)}k`;
  return `\$${cost.toFixed(2)}`;
}

// PS1 naming convention (confusing but consistent):
// Pad-Left = right-pad (left-align)
function padLeft(text, width) {
  if (text.length >= width) return text.substring(0, width);
  return text + ' '.repeat(width - text.length);
}

// Pad-Right = left-pad (right-align)
function padRight(text, width) {
  if (text.length >= width) return text.substring(0, width);
  return ' '.repeat(width - text.length) + text;
}

// Atomic write: write to temp then rename (atomic on NTFS)
function writeAtomic(filePath, content) {
  const tmp = `${filePath}.${process.pid}.tmp`;
  try {
    writeFileSync(tmp, content, 'utf8');
    try {
      renameSync(tmp, filePath);
    } catch {
      // Windows: rename may fail if target exists
      try {
        if (existsSync(filePath)) unlinkSync(filePath);
        renameSync(tmp, filePath);
      } catch {
        // Last resort: direct write
        writeFileSync(filePath, content, 'utf8');
      }
    }
  } finally {
    try { if (existsSync(tmp)) unlinkSync(tmp); } catch {}
  }
}

// === TRANSCRIPT CACHE ===

function getTranscriptCache(sessionId, transcriptPath) {
  const defaults = {
    last_offset: 0,
    transcript_size: 0,
    turns: 0,
    agent_contribution: 0,
    first_timestamp: null,
    last_timestamp: null,
    context_length: 0,
    last_usage: null,
  };

  const cacheFile = join(CACHE_DIR, `${sessionId}.json`);
  if (!existsSync(cacheFile)) return defaults;

  try {
    const cache = readJsonSafe(cacheFile);

    // Check if transcript shrunk (rewind/compact)
    let currentSize = 0;
    if (transcriptPath && existsSync(transcriptPath)) {
      currentSize = statSync(transcriptPath).size;
    }

    if (currentSize < (cache.transcript_size || 0)) {
      // M12: Transcript rewind - reset offset but preserve accumulated counters
      return {
        last_offset: 0,
        transcript_size: 0,
        turns: cache.turns || 0,
        agent_contribution: cache.agent_contribution || 0,
        first_timestamp: cache.first_timestamp || null,
        last_timestamp: cache.last_timestamp || null,
        context_length: cache.context_length || 0,
        last_usage: cache.last_usage || null,
      };
    }

    return {
      last_offset: cache.last_offset || 0,
      transcript_size: cache.transcript_size || 0,
      turns: cache.turns || 0,
      agent_contribution: cache.agent_contribution || 0,
      first_timestamp: cache.first_timestamp || null,
      last_timestamp: cache.last_timestamp || null,
      context_length: cache.context_length || 0,
      last_usage: cache.last_usage || null,
    };
  } catch {
    return defaults;
  }
}

function saveTranscriptCache(sessionId, cache) {
  const cacheFile = join(CACHE_DIR, `${sessionId}.json`);
  try {
    writeAtomic(cacheFile, JSON.stringify(cache));
  } catch {}
}

// === INCREMENTAL TRANSCRIPT PARSING ===

// Pre-compiled regex patterns
const RE_TIMESTAMP = /"timestamp"\s*:\s*"([^"]+)"/;
const RE_USER_TYPE = /"type"\s*:\s*"user"/;
const RE_IS_META = /"isMeta"\s*:\s*true/;
const RE_IS_SIDECHAIN = /"isSidechain"\s*:\s*true/;
const RE_USAGE = /"usage"/;
const RE_TOOL_USE_RESULT = /"toolUseResult"/;

function getIncrementalTranscriptData(transcriptPath, cache) {
  const result = {
    turns: cache.turns,
    agent_contribution: cache.agent_contribution,
    first_timestamp: cache.first_timestamp,
    last_timestamp: cache.last_timestamp,
    context_length: cache.context_length,
    last_usage: cache.last_usage,
    new_offset: cache.last_offset,
    new_size: cache.transcript_size,
  };

  if (!transcriptPath || !existsSync(transcriptPath)) return result;

  try {
    const fileStat = statSync(transcriptPath);
    const currentSize = fileStat.size;
    result.new_size = currentSize;

    // If file hasn't changed - return cached
    if (currentSize === cache.transcript_size && cache.last_offset > 0) {
      return result;
    }

    const startOffset = (cache.last_offset > 0 && cache.last_offset < currentSize)
      ? cache.last_offset : 0;
    const toRead = currentSize - startOffset;
    if (toRead <= 0) return result;

    // Read from offset (max 10MB per cycle)
    const fd = openSync(transcriptPath, 'r');
    const buf = Buffer.alloc(Math.min(toRead, 10 * 1024 * 1024));
    const bytesRead = readSync(fd, buf, 0, buf.length, startOffset);
    closeSync(fd);

    if (bytesRead === 0) return result;

    const content = buf.toString('utf8', 0, bytesRead);
    const rawLines = content.split('\n');

    // Don't process the last element - it might be incomplete
    // (unless content ends with \n, meaning last element is empty string)
    // Also skip first element when reading from non-zero offset - it's a partial line fragment
    const skipFirst = startOffset > 0 ? 1 : 0;
    const lines = rawLines.slice(skipFirst, -1);

    let mostRecentUsage = cache.last_usage;
    let linesProcessed = 0;
    const MAX_LINES = 5000;
    // Adjust byte offset for skipped first partial line
    let byteOffset = startOffset;
    if (skipFirst && rawLines.length > 0) {
      byteOffset += Buffer.byteLength(rawLines[0], 'utf8') + 1; // +1 for \n
    }
    let lastGoodOffset = byteOffset;

    for (const line of lines) {
      const lineBytes = Buffer.byteLength(line, 'utf8') + 1; // +1 for \n

      if (!line.trim()) {
        byteOffset += lineBytes;
        lastGoodOffset = byteOffset;
        continue;
      }

      linesProcessed++;
      if (linesProcessed > MAX_LINES) break; // C6: line limit

      // Extract timestamp via regex (cheap)
      const tsMatch = line.match(RE_TIMESTAMP);
      if (tsMatch) {
        if (!result.first_timestamp) result.first_timestamp = tsMatch[1];
        result.last_timestamp = tsMatch[1];
      }

      // Count user turns via regex
      if (RE_USER_TYPE.test(line)) {
        if (!RE_IS_META.test(line) && !RE_IS_SIDECHAIN.test(line)) {
          result.turns++;
        }
      }

      // Full parse ONLY for lines with usage or toolUseResult (expensive)
      const needFullParse = RE_USAGE.test(line) || RE_TOOL_USE_RESULT.test(line);
      if (needFullParse) {
        let entry;
        try {
          entry = JSON.parse(line);
        } catch {
          // M9: Malformed JSONL line - skip it, continue processing
          byteOffset += lineBytes;
          lastGoodOffset = byteOffset;
          continue;
        }

        // Context length: most recent main chain entry with usage
        if (entry.message && entry.message.usage) {
          const isSidechain = entry.isSidechain === true;
          const isError = entry.isApiErrorMessage === true;
          if (!isSidechain && !isError) {
            mostRecentUsage = entry.message.usage;
          }
        }

        // Agent contribution from toolUseResult (M13: prefer totalTokens)
        if (entry.toolUseResult) {
          const tur = entry.toolUseResult;
          let agentNewWork = 0;

          if (tur.totalTokens) {
            agentNewWork = Number(tur.totalTokens);
          } else if (tur.usage) {
            const agentInput = tur.usage.input_tokens || 0;
            const agentCacheCreate = tur.usage.cache_creation_input_tokens || 0;
            const agentOutput = tur.usage.output_tokens || 0;
            agentNewWork = agentInput + agentCacheCreate + agentOutput;
          }

          let summaryTokens = 0;
          if (tur.content && Array.isArray(tur.content)) {
            for (const c of tur.content) {
              if (c.text) summaryTokens += Math.ceil(c.text.length / 4);
            }
          }

          const contribution = agentNewWork - summaryTokens;
          if (contribution > 0) result.agent_contribution += contribution;
        }
      }

      byteOffset += lineBytes;
      lastGoodOffset = byteOffset; // M9: track last valid offset
    }

    // M9+M16: Use last good offset
    result.new_offset = lastGoodOffset;
    result.last_usage = mostRecentUsage;

    // Calculate context length from most recent usage
    if (mostRecentUsage) {
      const inputTok = mostRecentUsage.input_tokens || 0;
      const cacheRead = mostRecentUsage.cache_read_input_tokens || 0;
      const cacheCreate = mostRecentUsage.cache_creation_input_tokens || 0;
      result.context_length = inputTok + cacheRead + cacheCreate;
    }
  } catch {}

  return result;
}

// === MAIN ===

function main() {
  try {
    let jsonInput = readFileSync(0, 'utf8');

    // BOM cleanup (M17+m4)
    if (jsonInput.length > 0) {
      const first = jsonInput.charCodeAt(0);
      if (first === 0xFEFF || first === 0xFFFE || first === 0) {
        jsonInput = jsonInput.replace(/^\uFEFF/, '').replace(/^\uFFFE/, '').replace(/\0/g, '');
      }
    }

    if (!jsonInput.trim()) process.exit(0);

    const data = JSON.parse(jsonInput);

    // === ENSURE CACHE DIR ===
    if (!existsSync(CACHE_DIR)) {
      mkdirSync(CACHE_DIR, { recursive: true });
    }

    // === PARSE SESSION DATA ===
    // M10: Generate fallback ID from transcript path hash
    // M11: Sanitize session ID to prevent path traversal
    let rawSessionId;
    if (data.session_id) {
      rawSessionId = data.session_id;
    } else if (data.transcript_path) {
      rawSessionId = 'fallback-' + basename(data.transcript_path).replace(/\.[^.]+$/, '');
    } else {
      rawSessionId = `fallback-${process.pid}`;
    }
    const sessionId = rawSessionId.replace(/[^a-zA-Z0-9_\-]/g, '_');

    let sessionCost = 0;
    if (data.cost && data.cost.total_cost_usd) {
      sessionCost = Number(data.cost.total_cost_usd);
    }

    // Model name (shortened: O4.5, S3.5, H3)
    let modelName = '?';
    let rawModel = null;
    if (data.model) {
      if (data.model.id) rawModel = data.model.id;
      else if (data.model.display_name) rawModel = data.model.display_name;
    }

    if (rawModel) {
      let version = '';
      let m;
      if ((m = rawModel.match(/(\d+)-(\d+)-\d{8}/))) {
        version = `${m[1]}.${m[2]}`;
      } else if ((m = rawModel.match(/(\d+)-\d{8}/))) {
        version = m[1];
      } else if ((m = rawModel.match(/(\d+\.\d+)/))) {
        version = m[1];
      }

      if (/opus/i.test(rawModel)) modelName = `O${version}`;
      else if (/sonnet/i.test(rawModel)) modelName = `S${version}`;
      else if (/haiku/i.test(rawModel)) modelName = `H${version}`;
      else modelName = `C${version}`;
    }

    // === INCREMENTAL TRANSCRIPT PARSING ===
    const transcriptPath = data.transcript_path;
    const cache = getTranscriptCache(sessionId, transcriptPath);
    const transcriptData = getIncrementalTranscriptData(transcriptPath, cache);

    // M3: Save cache ONLY when dirty
    const newCache = {
      last_offset: transcriptData.new_offset,
      transcript_size: transcriptData.new_size,
      turns: transcriptData.turns,
      agent_contribution: transcriptData.agent_contribution,
      first_timestamp: transcriptData.first_timestamp,
      last_timestamp: transcriptData.last_timestamp,
      context_length: transcriptData.context_length,
      last_usage: transcriptData.last_usage,
    };

    const cacheDirty =
      (newCache.last_offset !== cache.last_offset) ||
      (newCache.turns !== cache.turns) ||
      (newCache.agent_contribution !== cache.agent_contribution) ||
      (newCache.context_length !== cache.context_length);

    if (cacheDirty) {
      saveTranscriptCache(sessionId, newCache);
    }

    // === CALCULATIONS ===
    const contextLength = transcriptData.context_length;
    const contextLimit = 160000;
    let contextPct = 0;
    if (contextLimit > 0 && contextLength > 0) {
      contextPct = Math.round((contextLength / contextLimit) * 1000) / 10;
    }

    const turns = transcriptData.turns;

    // Session duration
    let sessionDuration = 0;
    if (transcriptData.first_timestamp && transcriptData.last_timestamp) {
      try {
        const firstTs = new Date(transcriptData.first_timestamp);
        const lastTs = new Date(transcriptData.last_timestamp);
        sessionDuration = Math.floor((lastTs - firstTs) / 1000);
        if (sessionDuration < 0) sessionDuration = 0;
      } catch {}
    }

    // M3: Write ctx% for hooks - dirty-check
    const ctxPctInt = Math.round(contextPct);
    const ctxCacheFile = join(tmpdir(), `claude-context-pct-${sessionId}.txt`);
    let prevCtxPct = -1;
    try {
      if (existsSync(ctxCacheFile)) {
        prevCtxPct = parseInt(readFileSync(ctxCacheFile, 'utf8').trim(), 10);
      }
    } catch {}
    if (ctxPctInt !== prevCtxPct) {
      try { writeAtomic(ctxCacheFile, String(ctxPctInt)); } catch {}
    }

    // === AGENT CONTRIBUTION / TOTAL TOKENS ===
    const totalTokens = transcriptData.agent_contribution;

    // === COMPACT COUNTER (per-session file) ===
    const compactStateFile = join(CACHE_DIR, `compact-${sessionId}.json`);
    let compactsCount = 0;
    let compactDirty = false;

    try {
      if (existsSync(compactStateFile)) {
        const compactState = readJsonSafe(compactStateFile);
        compactsCount = compactState.count || 0;
        const prevCtxLength = compactState.last_context_length || 0;

        // Detect compaction: context dropped by >10%
        if (contextLength > 0 && prevCtxLength > 0) {
          if (contextLength < prevCtxLength * 0.9) {
            compactsCount++;
            compactDirty = true;
          }
        }
        if (contextLength !== prevCtxLength) compactDirty = true;
      } else {
        compactDirty = true;
      }
    } catch {
      compactDirty = true;
    }

    if (compactDirty) {
      const cJson = JSON.stringify({ count: compactsCount, last_context_length: contextLength });
      try { writeAtomic(compactStateFile, cJson); } catch {}
    }

    // === CROSS-DEVICE TOTALS (per-user stats) ===
    const statsDir = join(HOME, '.claude-history', 'stats');
    const configPath = join(HOME, '.config', 'kfg-stats', 'users.json');

    let userName = process.env.USERNAME || process.env.USER || 'unknown';
    if (existsSync(configPath)) {
      try {
        const cfg = readJsonSafe(configPath);
        if (cfg.defaultUser) userName = cfg.defaultUser;
      } catch {}
    }

    let totalCharsUser = 0, totalCharsAi = 0, totalUserPrompts = 0, totalCost = 0;
    const userStatsFile = join(statsDir, `user-${userName}.json`);
    if (existsSync(userStatsFile)) {
      try {
        const userStats = readJsonSafe(userStatsFile);
        totalCharsUser = userStats.chars_user || 0;
        totalCharsAi = userStats.chars_ai || 0;
        totalUserPrompts = userStats.user_prompts || 0;
        totalCost = userStats.cost || 0;
      } catch {}
    }

    const typingMinutes = totalCharsUser > 0 ? totalCharsUser / 285 : 0;
    const typingHours = Math.floor(typingMinutes / 60);
    const typingMins = Math.floor(typingMinutes % 60);
    const typingTimeStr = typingHours > 0 ? `${typingHours}h${typingMins}m` : `${typingMins}m`;

    // === FORMAT VALUES ===
    // m14: Cap display at 100%
    const ctxPctStr = contextPct > 100 ? '100%+' : `${contextPct}%`;
    const ctxColor = getCtxColor(contextPct);

    const sessionTimeStr = formatTime(sessionDuration);
    const turnsStr = String(turns);
    const totalTokensStr = formatNumber(totalTokens);
    const sessionCostStr = formatCost(sessionCost);

    const compactsStr = String(compactsCount);
    const aiCharsStr = formatNumber(totalCharsAi);
    const promptsStr = formatNumber(totalUserPrompts);
    const totalCostStr = formatCost(totalCost);

    // === GENERATE OUTPUT 4x3 ===
    const colW = 8;
    const sep1 = ' ';
    const sep2 = '  ';
    const sep3 = ' ';

    // Row 1: Model/User | ctx%/compacts
    const r1c1 = padLeft(modelName, colW);
    const r1c2 = padRight(userName, colW);
    const r1c3 = padLeft(ctxPctStr, colW);
    const r1c4 = padRight(compactsStr, colW);
    const line1 = `${c_red}${r1c1}${reset}${sep1}${c_red}${r1c2}${reset}${sep2}${ctxColor}${r1c3}${reset}${sep3}${ctxColor}${r1c4}${reset}`;

    // Row 2: time/typing | turns/AI_chars
    const r2c1 = padLeft(sessionTimeStr, colW);
    const r2c2 = padRight(typingTimeStr, colW);
    const r2c3 = padLeft(turnsStr, colW);
    const r2c4 = padRight(aiCharsStr, colW);
    const line2 = `${c_yellow}${r2c1}${reset}${sep1}${c_yellow}${r2c2}${reset}${sep2}${c_green}${r2c3}${reset}${sep3}${c_green}${r2c4}${reset}`;

    // Row 3: tokens/prompts | cost/cost_t
    const r3c1 = padLeft(totalTokensStr, colW);
    const r3c2 = padRight(promptsStr, colW);
    const r3c3 = padLeft(sessionCostStr, colW);
    const r3c4 = padRight(totalCostStr, colW);
    const line3 = `${c_blue}${r3c1}${reset}${sep1}${c_blue}${r3c2}${reset}${sep2}${c_purple}${r3c3}${reset}${sep3}${c_purple}${r3c4}${reset}`;

    process.stdout.write(`${line1}\n${line2}\n${line3}\n`);
  } catch {
    // Silent failure - statusline should never break the terminal
    process.exit(0);
  }
}

main();
