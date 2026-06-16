#!/data/data/com.termux/files/usr/bin/bash
# Voice reader PreToolUse hook: streams any new assistant text before tool calls.
# Lets the user hear questions/decisions while Claude continues working.

source "$HOME/.claude/hooks/czytaj/czytaj-env.sh" 2>/dev/null || exit 0   # SSOT (audit 2026-06-15)
# F18: cheap gate — exit only if NO project has reading on; pre-tool-use.py does
# the precise per-project is_active check.
# M12 (audit 2026-06-15): count only real *.flag files — the watcher's .keepwarm-readback
# dotfile made the old `ls -A` always non-empty, so this cheap skip never fired and every
# PreToolUse on every project shelled into python. (pre-tool-use.py only auto-reads — no
# precache — so skipping when no project reads is a pure win. stop.sh is intentionally NOT
# changed: it must reach stop.py for keepwarm precache regardless of mode.)
compgen -G "$CZYTAJ_FLAG_DIR"/*.flag >/dev/null 2>&1 || exit 0

exec python3 "$(dirname "$0")/pre-tool-use.py"
