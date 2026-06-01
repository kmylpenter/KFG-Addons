#!/data/data/com.termux/files/usr/bin/bash
# Toggle voice reading mode flag + (re)spawn Piper daemon.
# Prints exactly "ON" or "OFF" so the skill can branch on a single read.

RUN_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/piper-server"   # F19: SSOT with piper_server.py
FLAG_DIR="$HOME/.claude/czytaj-flags"

# Per-project key — MUST match _speak.py _project_dir/_project_flag and
# user-prompt-submit.sh EXACTLY. printf '%s' (NOT echo) so no trailing newline
# changes the sha1; $CLAUDE_PROJECT_DIR is stable across `cd` into a subdir.
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
KEY=$(printf '%s' "$(realpath "$DIR" 2>/dev/null || echo "$DIR")" | sha1sum | cut -d' ' -f1)
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
    for pat in 'python.*piper_server\.py' piper-daemon paplay 'python.*piper_stream\.py' termux-tts-speak 'python.*volume_watcher\.py' 'rish.*dd if=/dev/input' 'rish.*getevent'; do
      pkill -9 -f "$pat" >/dev/null 2>&1
    done
    # The volume watcher's reader (dd) — and the getevent used for device discovery —
    # run under the Shizuku SERVICE (shell uid), not as a child of the PRoot client,
    # so killing the client above can leave them. Reap on the Android side via rish.
    timeout 8 rish -c "pkill -f 'dd if=/dev/input' 2>/dev/null; pkill -9 getevent 2>/dev/null" >/dev/null 2>&1
    rm -rf "$RUN_DIR"
    rm -f "$HOME/.claude/czytaj-pause.flag"   # F40: clear a stale global pause
  fi
else
  mkdir -p "$FLAG_DIR"
  touch "$FLAG"
  mkdir -p "$RUN_DIR"
  chmod 700 "$RUN_DIR" 2>/dev/null
  nohup python3 "$HOME/.claude/hooks/czytaj/piper_server.py" start >/dev/null 2>&1 &   # F20: race-safe
  disown
  # Volume-key watcher (VolumeDown=stop, VolumeUp=read-last via Shizuku getevent).
  # Self-gates on Shizuku readiness + holds a single-instance lock, so spawning it
  # on every ON is safe — a second project's toggle just exits immediately.
  nohup python3 "$HOME/.claude/hooks/czytaj/volume_watcher.py" >/dev/null 2>&1 &
  disown
  echo ON
fi
