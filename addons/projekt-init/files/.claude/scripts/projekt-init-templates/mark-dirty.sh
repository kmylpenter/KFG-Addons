#!/usr/bin/env bash
# PostToolUse(Edit|Write): sentinel "w tej turze byly edycje" — Stop-gate odpala suite tylko wtedy.
D="${CLAUDE_PROJECT_DIR:-$PWD}"
mkdir -p "$D/.claude/.runtime" 2>/dev/null
date +%s > "$D/.claude/.runtime/dirty" 2>/dev/null
exit 0
