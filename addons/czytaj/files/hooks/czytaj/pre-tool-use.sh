#!/data/data/com.termux/files/usr/bin/bash
# Voice reader PreToolUse hook: streams any new assistant text before tool calls.
# Lets the user hear questions/decisions while Claude continues working.

source "$HOME/.claude/hooks/czytaj/czytaj-env.sh" 2>/dev/null || exit 0   # SSOT (audit 2026-06-15)
# F18: cheap gate — exit only if NO project has reading on; pre-tool-use.py does
# the precise per-project is_active check.
[ -n "$(ls -A "$CZYTAJ_FLAG_DIR" 2>/dev/null)" ] || exit 0

exec python3 "$(dirname "$0")/pre-tool-use.py"
