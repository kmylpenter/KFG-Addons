#!/data/data/com.termux/files/usr/bin/bash
# Voice reader hook: speak last assistant message via TTS
# Only runs when ~/.claude/czytaj.flag exists.

[ -f "$HOME/.claude/czytaj.flag" ] || exit 0

exec python3 "$(dirname "$0")/stop.py"
