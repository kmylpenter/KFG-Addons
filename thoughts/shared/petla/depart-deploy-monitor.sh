#!/usr/bin/env bash
# Departure monitor (czytaj deploy, 2026-06-16). User is driving now, leaves the car in ~30 min,
# back in a few hours. Deploy the audit fixes + restart the volume_watcher ONLY when it won't
# interrupt an in-progress read-back. Exit (→ re-invokes the launching session to run the deploy)
# once: elapsed >= FLOOR (user has left) AND czytaj has NOT played for IDLE seconds (no active
# read-back, so a watcher restart is seamless). Read-only (only stats a marker + sleeps).
OUT="${1:-/tmp/depart-deploy.out}"
FLOOR="${2:-1800}"     # 30 min — user's own estimate for leaving the car
IDLE="${3:-120}"       # require 2 min with no czytaj playback before restarting the watcher
POLL=60
CAP=7200               # 2 h hard cap (deploy anyway)
PM="$HOME/.claude/czytaj-playing.flag"
ts(){ date '+%H:%M:%S'; }
say(){ printf '[%s] %s\n' "$(ts)" "$*" >> "$OUT"; }
recently_playing(){    # true iff czytaj played within the last IDLE seconds
  [ -f "$PM" ] || return 1
  local age=$(( $(date +%s) - $(stat -c %Y "$PM" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$IDLE" ]
}
: > "$OUT"
say "depart-monitor START floor=${FLOOR}s idle=${IDLE}s cap=${CAP}s"
elapsed=0
while [ "$elapsed" -lt "$CAP" ]; do
  sleep "$POLL"; elapsed=$((elapsed+POLL))
  if [ "$elapsed" -ge "$FLOOR" ]; then
    if recently_playing; then
      say "elapsed=${elapsed}s — floor reached but czytaj played <${IDLE}s ago; waiting for an idle gap"
    else
      say "elapsed=${elapsed}s, no playback for >=${IDLE}s -> DEPLOY window"
      echo "DEPLOY_NOW elapsed=${elapsed}"
      exit 0
    fi
  fi
done
say "CAP ${CAP}s reached -> deploy anyway"
echo "DEPLOY_CAP elapsed=${elapsed}"
exit 0
