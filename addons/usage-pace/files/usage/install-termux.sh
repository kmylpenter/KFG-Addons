#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# install-termux.sh — JEDYNY krok reczny usage-pace, do wklejenia W TERMUKSIE
# (nie w proot!):   bash ~/.claude/usage/install-termux.sh
#
# Robi trzy rzeczy:
#  1. rejestruje cykliczne sprawdzanie tempa (termux-job-scheduler, co 6 h)
#  2. wysyla testowe powiadomienie (od razu widzisz, ze dziala)
#  3. odpala pierwszy przebieg pace.sh (jesli tempo niskie -> prawdziwe
#     powiadomienie przyjdzie za chwile)
# ============================================================================
set -u
H=/data/data/com.termux/files/home
JOB_ID=7301
PERIOD_MS=21600000   # 6 godzin; minimalnie 900000 (15 min) — Android nie umie
                     # "punktualnie o 12:00", tylko "mniej wiecej co X"

echo "== usage-pace: instalacja po stronie Termuxa =="

if ! command -v termux-notification >/dev/null 2>&1; then
  echo "BLAD: brak termux-notification. Zainstaluj pakiet i apke:"
  echo "  pkg install termux-api    + apka Termux:API z F-Droid"
  exit 1
fi

if ! command -v termux-job-scheduler >/dev/null 2>&1; then
  echo "BLAD: brak termux-job-scheduler (pkg install termux-api)"
  exit 1
fi

chmod +x "$H/.claude/usage/pace-job.sh" "$H/.claude/usage/pace.sh" 2>/dev/null

echo "-- rejestruje job co 6 h (job-id $JOB_ID)..."
termux-job-scheduler --job-id "$JOB_ID" \
  --script "$H/.claude/usage/pace-job.sh" \
  --period-ms "$PERIOD_MS" \
  --persisted true 2>&1 | grep -v "^WARNING: linker"

echo "-- zaplanowane joby:"
termux-job-scheduler --pending 2>&1 | grep -v "^WARNING: linker"

echo "-- testowe powiadomienie..."
if termux-notification --id usage-pace-setup --title "usage-pace: instalacja OK" \
     --content "Powiadomienia dzialaja. Sprawdzanie tempa co 6 h zarejestrowane."; then
  echo "   wyslane — sprawdz pasek powiadomien"
else
  echo "   BLAD wysylki — sprawdz apke Termux:API"
fi

echo "-- pierwszy przebieg pace.sh (pobranie danych + ocena tempa)..."
bash "$H/.claude/usage/pace.sh" --scheduled
bash "$H/.claude/usage/pace.sh" --status

echo "== gotowe. Odinstalowanie: bash ~/.claude/usage/rollback.sh =="
