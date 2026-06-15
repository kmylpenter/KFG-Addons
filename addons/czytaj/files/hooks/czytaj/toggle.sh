#!/data/data/com.termux/files/usr/bin/bash
# Toggle voice reading mode flag + (re)spawn Piper daemon.
# Prints exactly "ON" or "OFF" so the skill can branch on a single read.

source "$HOME/.claude/hooks/czytaj/czytaj-env.sh" || { echo "ERR: czytaj-env.sh missing — reinstall czytaj addon" >&2; exit 1; }
RUN_DIR="$CZYTAJ_RUN_DIR"   # SSOT (audit 2026-06-15): one definition in czytaj-env.sh
FLAG_DIR="$CZYTAJ_FLAG_DIR"

# Per-project key — ONE derivation now (czytaj_project_key in czytaj-env.sh), shared with
# user-prompt-submit.sh and mirrored by czytaj_paths.project_key (pinned by czytaj_selftest.py).
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
KEY=$(czytaj_project_key "$DIR")
FLAG="$FLAG_DIR/$KEY.flag"

if [ -f "$FLAG" ]; then
  rm -f "$FLAG"
  echo OFF
  # F4/F40: tear down the SHARED audio ONLY when NO project is reading anymore,
  # so /czytaj OFF here can't cut off another window that is still on.
  if [ -z "$(ls -A "$FLAG_DIR" 2>/dev/null)" ]; then
    termux-media-player stop >/dev/null 2>&1
    # F21: anchor the python scripts so the pattern can't match an editor/grep
    # whose argv contains these names; bare binaries (daemon/paplay/tts) stay.
    # GLOBAL-KEYS: the volume_watcher + its dd/getevent readers are DELIBERATELY
    # NOT killed here. The keys are an always-on remote (read-back/pause) decoupled
    # from czytaj on/off, so turning reading OFF tears down only the AUTO-read audio
    # chain — never the key watcher. (The watcher is respawned by the prompt hook.)
    for pat in 'python.*piper_server\.py' piper-daemon paplay 'python.*piper_stream\.py' termux-tts-speak; do
      pkill -9 -f "$pat" >/dev/null 2>&1
    done
    rm -rf "$RUN_DIR"
    rm -f "$CZYTAJ_PAUSE_FLAG"   # F40: clear a stale global pause
  fi
else
  mkdir -p "$FLAG_DIR"
  touch "$FLAG"
  mkdir -p "$RUN_DIR"
  chmod 700 "$RUN_DIR" 2>/dev/null
  nohup python3 "$HOME/.claude/hooks/czytaj/piper_server.py" start >/dev/null 2>&1 &   # F20: race-safe
  disown
  # FD1: warm the synth inference graph + BT/Android-Auto routing now (detached), so the
  # FIRST read-back of the session isn't a cold JIT inference + a ~0.7s routing-wake tone.
  nohup python3 "$HOME/.claude/hooks/czytaj/piper_stream.py" warmup >/dev/null 2>&1 &
  disown
  # Volume-key watcher (VolumeDown=stop, VolumeUp=read-last via Shizuku getevent).
  # Self-gates on Shizuku readiness + holds a single-instance lock, so spawning it
  # on every ON is safe — a second project's toggle just exits immediately.
  nohup python3 "$HOME/.claude/hooks/czytaj/volume_watcher.py" >/dev/null 2>&1 &
  disown
  echo ON
fi
