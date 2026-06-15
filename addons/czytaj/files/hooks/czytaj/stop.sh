#!/data/data/com.termux/files/usr/bin/bash
# Voice reader hook: speak last assistant message via TTS
# Only runs when reading mode is ON in at least one project (per-project flags).

source "$HOME/.claude/hooks/czytaj/czytaj-env.sh" 2>/dev/null || exit 0   # SSOT (audit 2026-06-15)
# F18: cheap gate — exit only if NO project has reading on. The precise
# per-project check is in stop.py (is_active keyed by the hook's project dir).
[ -n "$(ls -A "$CZYTAJ_FLAG_DIR" 2>/dev/null)" ] || exit 0

exec python3 "$(dirname "$0")/stop.py"
