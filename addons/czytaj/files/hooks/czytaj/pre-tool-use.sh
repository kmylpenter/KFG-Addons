#!/data/data/com.termux/files/usr/bin/bash
# Voice reader PreToolUse hook: streams any new assistant text before tool calls.
# Lets the user hear questions/decisions while Claude continues working.

[ -f "$HOME/.claude/czytaj.flag" ] || exit 0

exec python3 "$(dirname "$0")/pre-tool-use.py"
