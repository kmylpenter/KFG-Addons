#!/usr/bin/env bash
# Testy syntetyczne pace.sh — dziala na podstawionych plikach cache/history,
# NIE dotyka prawdziwego ~/.claude/usage-cache.json.
set -u
PACE=/root/.claude/usage/pace.sh
T=/root/.claude/usage/test/tmp
rm -rf "$T"; mkdir -p "$T/bin"
PASS=0; FAIL=0

# atrapa termux-notification: loguje wywolanie, wychodzi 0
cat > "$T/bin/termux-notification" <<'EOF'
#!/usr/bin/env bash
echo "STUB-NOTIF $*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$T/bin/termux-notification"

mkcache() { # $1=plik $2=used7d $3=resets_offset_h $4=fetched_offset_s
  python3 - "$@" <<'PY'
import json, sys, time
f, used, off_h, f_off = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
now = time.time()
json.dump({
  "fetched_at_epoch": now - f_off,
  "source": "test",
  "cc_version": "2.1.170",
  "five_hour": {"used_pct": 11.0, "resets_at_epoch": now + 3600},
  "seven_day": {"used_pct": used, "resets_at_epoch": now + off_h * 3600},
}, open(f, "w"))
PY
}

run() { # $1=nazwa $2=oczekiwany_status $3=used $4=reset_za_h [$5=fetched_off_s] [$6=extra_env]
  local name="$1" want="$2" cache="$T/c-$1.json"
  mkcache "$cache" "$3" "$4" "${5:-10}"
  local out
  out="$(eval "${6:-}" CLAUDE_USAGE_CACHE_FILE="$cache" CLAUDE_USAGE_HISTORY_FILE="$T/h-$1.csv" \
        bash "$PACE" --compute-only; \
        CLAUDE_USAGE_CACHE_FILE="$cache" CLAUDE_USAGE_HISTORY_FILE="$T/h-$1.csv" \
        bash "$PACE" --status 2>/dev/null | head -1)"
  if python3 -c "
import json,sys
c=json.load(open('$cache'))
s=(c.get('pace') or {}).get('status')
sys.exit(0 if s=='$want' else 1)
"; then echo "PASS $name -> $want"; PASS=$((PASS+1));
  else echo "FAIL $name (oczekiwano $want, jest: $(python3 -c "import json;print((json.load(open('$cache')).get('pace') or {}).get('status'))"))"; FAIL=$((FAIL+1)); fi
}

# scenariusze: nazwa, oczekiwany status, used7d%, reset za N h
run srodek-ok        OK    45  100   # elapsed 68h=40% -> proj 111%
run srodek-low       LOW   15  100   # proj ~37% < 50
run grace            GRACE 5   160   # 8h od resetu < 12h
run endgame-low      LOW   24  28    # zostalo 76% > 15
run endgame-ok       OK    90  28    # zostalo 10% <= 15
run stale            STALE 50  100   10900  # dane sprzed >2h
run okno-przeszle    STALE 50  -1    # resets_at w przeszlosci

# NO_DATA: pusty cache
: > "$T/c-nodata.json"
CLAUDE_USAGE_CACHE_FILE="$T/c-nodata.json" CLAUDE_USAGE_HISTORY_FILE="$T/h-nodata.csv" bash "$PACE" --compute-only
if python3 -c "
import json,sys
c=json.load(open('$T/c-nodata.json'))
sys.exit(0 if (c.get('pace') or {}).get('status')=='NO_DATA' else 1)
"; then echo "PASS nodata -> NO_DATA"; PASS=$((PASS+1)); else echo "FAIL nodata"; FAIL=$((FAIL+1)); fi

# --- powiadomienie + cooldown (atrapa, HOME podstawiony) ---
export STUB_LOG="$T/stub.log"; : > "$STUB_LOG"
NC="$T/c-notif.json"; mkcache "$NC" 24 28 10
HOME=/data/data/com.termux/files/home PATH="$T/bin:$PATH" \
  CLAUDE_USAGE_CACHE_FILE="$NC" CLAUDE_USAGE_HISTORY_FILE="$T/h-notif.csv" bash "$PACE" --compute-only
N1=$(grep -c STUB-NOTIF "$STUB_LOG")
HOME=/data/data/com.termux/files/home PATH="$T/bin:$PATH" \
  CLAUDE_USAGE_CACHE_FILE="$NC" CLAUDE_USAGE_HISTORY_FILE="$T/h-notif.csv" bash "$PACE" --compute-only
N2=$(grep -c STUB-NOTIF "$STUB_LOG")
if [ "$N1" = "1" ] && [ "$N2" = "1" ]; then echo "PASS notyfikacja-raz+cooldown"; PASS=$((PASS+1));
else echo "FAIL notyfikacja (po1=$N1 po2=$N2, oczekiwano 1 i 1)"; FAIL=$((FAIL+1)); fi
grep STUB-NOTIF "$STUB_LOG" | head -1

# --- w proot (HOME=/root) NIE wolno wysylac ---
PC="$T/c-proot.json"; mkcache "$PC" 24 28 10
: > "$STUB_LOG"
PATH="$T/bin:$PATH" CLAUDE_USAGE_CACHE_FILE="$PC" CLAUDE_USAGE_HISTORY_FILE="$T/h-proot.csv" bash "$PACE" --compute-only
if [ "$(grep -c STUB-NOTIF "$STUB_LOG")" = "0" ]; then echo "PASS proot-bez-powiadomien"; PASS=$((PASS+1));
else echo "FAIL proot wyslal powiadomienie!"; FAIL=$((FAIL+1)); fi

# --- projekcja 5h: liczona (elapsed 4h z 5h, used 11 -> 13.8), bez alarmow ---
P5="$T/c-proj5.json"; mkcache "$P5" 45 100 10   # five_hour: used 11, reset za 1h
CLAUDE_USAGE_CACHE_FILE="$P5" CLAUDE_USAGE_HISTORY_FILE="$T/h-proj5.csv" bash "$PACE" --compute-only
if python3 -c "
import json,sys
p=(json.load(open('$P5')).get('pace') or {})
sys.exit(0 if abs((p.get('projection_pct_5h') or 0) - 13.8) < 0.3 else 1)
"; then echo "PASS proj5h-liczona (13.8)"; PASS=$((PASS+1));
else echo "FAIL proj5h ($(python3 -c "import json;print((json.load(open('$P5')).get('pace') or {}).get('projection_pct_5h'))"))"; FAIL=$((FAIL+1)); fi

# --- projekcja 5h: grace na starcie okna (reset za 4.9h => elapsed 6 min) ---
G5="$T/c-grace5.json"
python3 - "$G5" <<'PY'
import json, sys, time
now = time.time()
json.dump({"fetched_at_epoch": now-10, "source": "test", "cc_version": "2.1.170",
  "five_hour": {"used_pct": 2.0, "resets_at_epoch": now + 4.9*3600},
  "seven_day": {"used_pct": 45.0, "resets_at_epoch": now + 100*3600}}, open(sys.argv[1],"w"))
PY
CLAUDE_USAGE_CACHE_FILE="$G5" CLAUDE_USAGE_HISTORY_FILE="$T/h-grace5.csv" bash "$PACE" --compute-only
if python3 -c "
import json,sys
p=(json.load(open('$G5')).get('pace') or {})
sys.exit(0 if p.get('projection_pct_5h') is None else 1)
"; then echo "PASS proj5h-grace (brak strzalki na starcie okna)"; PASS=$((PASS+1));
else echo "FAIL proj5h-grace"; FAIL=$((FAIL+1)); fi

# --- historia: 1 wiersz na ten sam odczyt (dedup po fetched_at) ---
HC="$T/c-hist.json"; mkcache "$HC" 45 100 10
CLAUDE_USAGE_CACHE_FILE="$HC" CLAUDE_USAGE_HISTORY_FILE="$T/h-hist.csv" bash "$PACE" --compute-only
CLAUDE_USAGE_CACHE_FILE="$HC" CLAUDE_USAGE_HISTORY_FILE="$T/h-hist.csv" bash "$PACE" --compute-only
ROWS=$(($(wc -l < "$T/h-hist.csv") - 1))
if [ "$ROWS" = "1" ]; then echo "PASS historia-dedup (1 wiersz)"; PASS=$((PASS+1));
else echo "FAIL historia ($ROWS wierszy, oczekiwano 1)"; FAIL=$((FAIL+1)); fi
echo "--- przyklad CSV ---"; cat "$T/h-hist.csv"

echo "=============================="
echo "WYNIK: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
