#!/usr/bin/env bash
# car-catch.sh — background Bluetooth-car A2DP connection catcher.
# Calibration aid for volume_watcher._car_connected (czytaj audit 2026-06-16).
#
# Authoritative connect signal on this device (Pixel 9 Pro XL / Android 16):
#   dumpsys bluetooth_manager -> 'Profile: A2dpService' -> 'mActiveDevice: <MAC|null>'
#   null  = no A2DP sink active;  a MAC = that device is the active A2DP sink.
# (The 'active A2DP contains: [..]' lines are HISTORICAL log entries, not current
#  state — grepping them is what made the spike's detection flicker.)
#
# Read-only: only runs dumpsys via Shizuku (rish). Appends a timestamped trace to OUT
# and, on the first null->MAC transition, captures the full signature and EXITS — so the
# launching Claude session is re-invoked (the "signal"). Times out after ~55 min.
#
#   bash car-catch.sh [OUT] [POLL_S] [MAX_POLLS]
PAT="${CZYTAJ_BT_DEVICE:-peugeo}"
OUT="${1:-/tmp/car-catch.out}"
POLL="${2:-7}"
MAX="${3:-470}"        # 470 * 7s ≈ 55 min
ts(){ date '+%H:%M:%S'; }
say(){ printf '[%s] %s\n' "$(ts)" "$*" >> "$OUT"; }

# Current A2DP active device (MAC or 'null'), read from the A2dpService section only.
active_dev(){
  rish -c "dumpsys bluetooth_manager 2>/dev/null" 2>/dev/null \
    | awk '/Profile: A2dpService/{f=1} f&&/mActiveDevice:/{print $2; exit}'
}
is_mac(){ [ -n "$1" ] && [ "$1" != "null" ] && printf '%s' "$1" | grep -q ':'; }

: > "$OUT"
say "car-catch START pat='$PAT' poll=${POLL}s max=${MAX} signal=A2dpService.mActiveDevice"
say "BASELINE audio active/communication device:"
rish -c "dumpsys audio 2>/dev/null" 2>/dev/null \
  | grep -iE "active communication device|name:.*$PAT|A2DP (sink )?device addr" \
  | tail -6 | sed 's/^/    /' >> "$OUT"
base="$(active_dev)"
say "BASELINE A2dpService.mActiveDevice = '${base:-<empty>}'"
prev="$base"

for i in $(seq 1 "$MAX"); do
  cur="$(active_dev)"
  if [ "$cur" != "$prev" ]; then
    say "CHANGE @poll $i: mActiveDevice '${prev:-<empty>}' -> '${cur:-<empty>}'"
    prev="$cur"
  fi
  if is_mac "$cur"; then
    say "=== A2DP SINK ACTIVE (mActiveDevice=$cur) @poll $i ==="
    say "--- confirm name + full A2dpService section ---"
    rish -c "dumpsys audio 2>/dev/null" 2>/dev/null \
      | grep -iE "name:.*$cur|Active communication device" | head -5 | sed 's/^/    /' >> "$OUT"
    rish -c "dumpsys bluetooth_manager 2>/dev/null" 2>/dev/null \
      | awk '/Profile: A2dpService/{f=1} f{print}' | head -14 | sed 's/^/    /' >> "$OUT"
    say "=== EXIT on detection ==="
    echo "CAR_CONNECTED mActiveDevice=$cur"
    exit 0
  fi
  sleep "$POLL"
done
say "car-catch TIMEOUT — no A2DP sink became active in the window"
echo "CAR_CATCH_TIMEOUT"
exit 0
