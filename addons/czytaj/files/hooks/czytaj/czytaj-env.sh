#!/data/data/com.termux/files/usr/bin/bash
# Single source of truth for czytaj's SHELL-side paths + the per-project key.
# Mirrors czytaj_paths.py for the shell hooks. SOURCE it (do not execute):
#     source "$HOME/.claude/hooks/czytaj/czytaj-env.sh"
#
# WHY a separate shell file instead of having the hooks call python: these hooks run on
# EVERY prompt / tool-use, and shelling out to python per invocation would add ~50-100ms
# to the hot path — defeating the latency goal of the SSOT audit (2026-06-15). So the shell
# keeps its own fast copy and czytaj_selftest.py asserts it agrees with czytaj_paths.py
# (RUN_DIR + the sha1 key), so this file and the Python module can never silently drift.
#
# Before this file, RUN_DIR was hardcoded in 3 places (piper_server.py + toggle.sh +
# install.sh) and the sha1 key was derived in 3 (toggle.sh + user-prompt-submit.sh +
# _speak.py) — its divergence is what split the daemon and made synth always cold.

CZYTAJ_DIR="$HOME/.claude"
CZYTAJ_HOOK_DIR="$CZYTAJ_DIR/hooks/czytaj"
CZYTAJ_FLAG_DIR="$CZYTAJ_DIR/czytaj-flags"
CZYTAJ_LOG="$CZYTAJ_DIR/czytaj.log"
CZYTAJ_PAUSE_FLAG="$CZYTAJ_DIR/czytaj-pause.flag"
CZYTAJ_KEYPAUSE_STATE="$CZYTAJ_DIR/czytaj-keypause.state"
# Daemon socket dir — FIXED absolute path (was env-derived → daemon-split → cold synth).
CZYTAJ_RUN_DIR="$HOME/.cache/czytaj/piper-server"

# czytaj_project_key DIR  ->  sha1 of realpath(DIR), lowercase hex, no trailing newline.
# MUST equal czytaj_paths.project_key(). printf '%s' (NOT echo) so the trailing newline
# echo would add can't change the hash; realpath falls back to the literal dir if it fails.
czytaj_project_key() {
  printf '%s' "$(realpath "$1" 2>/dev/null || echo "$1")" | sha1sum | cut -d' ' -f1
}
