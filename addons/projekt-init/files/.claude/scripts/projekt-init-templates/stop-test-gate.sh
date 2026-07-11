#!/usr/bin/env bash
# Uniwersalny Stop-gate (projekt-init): zielona suita warunkiem konca tury (globalny standard: Verification Gate).
# CICHY (exit 0), dopoki projekt nie ma zadnego runnera — aktywuje sie sam, gdy pojawia sie testy.
# Kolejnosc sondowania: .claude/test-command (override) -> harness petla-noc -> run-tests.sh -> vitest -> gradlew.
# Cicho tez gdy: brak edycji w turze / anty-petla (stop_hook_active).
set -u
IN=$(cat 2>/dev/null || true)
case "$IN" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;; esac
D="${CLAUDE_PROJECT_DIR:-$PWD}"
DIRTY="$D/.claude/.runtime/dirty"
[ -f "$DIRTY" ] || exit 0

run_suite() {
  # 1) jawny override: .claude/test-command (jedna linia; exit 0 = zielone)
  if [ -f "$D/.claude/test-command" ]; then
    local c; c=$(head -1 "$D/.claude/test-command")
    if [ -n "$c" ]; then (cd "$D" && bash -c "$c"); return $?; fi
  fi
  # 2) harness charakteryzujacy petla-noc (root albo podkatalog, np. GoogleAppsScript/ lub gas/)
  local h pd out
  for h in "$D/.petla-noc/harness/harness.js" "$D"/*/.petla-noc/harness/harness.js; do
    if [ -f "$h" ] && command -v node >/dev/null 2>&1; then
      pd="$(dirname "$(dirname "$(dirname "$h")")")"
      out=$(node "$h" "$pd" --json 2>&1) || { printf '%s' "$out"; return 1; }
      if printf '%s' "$out" | grep -q '"green": *true'; then return 0; fi
      printf '%s' "$out"; return 1
    fi
  done
  # 3) warstwa tania w stylu KmylSales
  if [ -f "$D/run-tests.sh" ]; then bash "$D/run-tests.sh"; return $?; fi
  # 4) vitest (tylko realnie zainstalowany)
  if [ -x "$D/node_modules/.bin/vitest" ]; then (cd "$D" && npx vitest run --reporter=dot); return $?; fi
  # 5) gradle
  if [ -x "$D/gradlew" ]; then (cd "$D" && ./gradlew test -q); return $?; fi
  return 200  # brak runnera -> bramka spi
}

OUT=$(run_suite 2>&1); RC=$?
if [ "$RC" = "200" ]; then exit 0; fi
if [ "$RC" = "0" ]; then rm -f "$DIRTY"; exit 0; fi
{
  echo "🔴 STOP-GATE: suita testowa CZERWONA — nie koncz tury, napraw regres."
  echo "Ogon wyniku:"
  printf '%s\n' "$OUT" | tail -c 700
} >&2
exit 2
