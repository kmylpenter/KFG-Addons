#!/data/data/com.termux/files/usr/bin/bash
# Toggle voice reading mode flag + (re)spawn Piper daemon.
# Prints exactly "ON" or "OFF" so the skill can branch on a single read.

RUN_DIR="${TMPDIR:-/tmp}/piper-server"

if [ -f "$HOME/.claude/czytaj.flag" ]; then
  rm -f "$HOME/.claude/czytaj.flag"
  termux-media-player stop >/dev/null 2>&1
  for pat in piper_server piper-daemon paplay piper_stream termux-tts-speak; do
    pkill -9 -f "$pat" >/dev/null 2>&1
  done
  rm -rf "$RUN_DIR"
  echo OFF
else
  touch "$HOME/.claude/czytaj.flag"
  mkdir -p "$RUN_DIR"
  chmod 700 "$RUN_DIR" 2>/dev/null
  nohup python3 "$HOME/.claude/hooks/czytaj/piper_server.py" serve >/dev/null 2>&1 &
  disown
  echo ON
fi
