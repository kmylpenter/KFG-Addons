#!/usr/bin/env node
// PostToolUse hook: tracks changed files for statusline display
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join, resolve } from 'path';
import { tmpdir } from 'os';

try {
  const input = JSON.parse(readFileSync(0, 'utf8'));
  const sessionId = input.session_id || 'default';
  const filePath = input.tool_input?.file_path;

  if (!filePath) process.exit(0);

  const fullPath = resolve(filePath);

  // Track file for statusline
  const trackFile = join(tmpdir(), `claude-changed-files-${sessionId}.json`);
  let files = [];
  if (existsSync(trackFile)) {
    try { files = JSON.parse(readFileSync(trackFile, 'utf8')); } catch {}
  }
  files = files.filter(f => f !== fullPath);
  files.push(fullPath);
  if (files.length > 20) files = files.slice(-20);
  writeFileSync(trackFile, JSON.stringify(files), 'utf8');
} catch {}
