#!/usr/bin/env node
// UserPromptSubmit hook: clears changed files tracking on each new user prompt
// So statusline only shows files from the CURRENT assistant turn
import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

try {
  const input = JSON.parse(readFileSync(0, 'utf8'));
  const sessionId = input.session_id || 'default';
  const trackFile = join(tmpdir(), `claude-changed-files-${sessionId}.json`);
  writeFileSync(trackFile, '[]', 'utf8');
} catch {}
