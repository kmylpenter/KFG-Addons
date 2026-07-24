#!/usr/bin/env bash
# Testy syntetyczne pace.sh — dziala na podstawionych plikach cache/history,
# NIE dotyka prawdziwego ~/.claude/usage-cache.json.
set -u
# PACE = siostrzany pace.sh (ten sam katalog co ten harness), z fallbackiem na zainstalowany.
PACE="$(cd "$(dirname "$0")" && pwd)/pace.sh"; [ -f "$PACE" ] || PACE=/root/.claude/usage/pace.sh
T="${TMPDIR:-/tmp}/kfg-pace-test-tmp"
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
  # swiezy znacznik fetchu API: bez niego --scheduled otwiera bramke i realnie
  # idzie do api/oauth/usage prawdziwym tokenem, nadpisujac scenariusz testu.
  "last_api_fetch_epoch": now - 10,
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

# --- powiadomienie raz + cooldown (atrapa OK, --scheduled, HOME=Termux) ---
export STUB_LOG="$T/stub.log"; : > "$STUB_LOG"
NC="$T/c-notif.json"; mkcache "$NC" 24 28 10   # fetched 10s temu (< TTL) -> --scheduled nie fetchuje
HOME=/data/data/com.termux/files/home PATH="$T/bin:$PATH" \
  CLAUDE_USAGE_CACHE_FILE="$NC" CLAUDE_USAGE_HISTORY_FILE="$T/h-notif.csv" bash "$PACE" --scheduled
N1=$(grep -c STUB-NOTIF "$STUB_LOG")
HOME=/data/data/com.termux/files/home PATH="$T/bin:$PATH" \
  CLAUDE_USAGE_CACHE_FILE="$NC" CLAUDE_USAGE_HISTORY_FILE="$T/h-notif.csv" bash "$PACE" --scheduled
N2=$(grep -c STUB-NOTIF "$STUB_LOG")
if [ "$N1" = "1" ] && [ "$N2" = "1" ]; then echo "PASS notyfikacja-raz+cooldown"; PASS=$((PASS+1));
else echo "FAIL notyfikacja (po1=$N1 po2=$N2, oczekiwano 1 i 1)"; FAIL=$((FAIL+1)); fi

# --- M50: --compute-only (sciezka PASKA) NIE powiadamia, nawet przy LOW+CAN_NOTIFY ---
M50C="$T/c-m50.json"; mkcache "$M50C" 24 28 10; : > "$STUB_LOG"
HOME=/data/data/com.termux/files/home PATH="$T/bin:$PATH" \
  CLAUDE_USAGE_CACHE_FILE="$M50C" CLAUDE_USAGE_HISTORY_FILE="$T/h-m50.csv" bash "$PACE" --compute-only
if [ "$(grep -c STUB-NOTIF "$STUB_LOG")" = "0" ]; then echo "PASS M50 compute-only-nie-powiadamia"; PASS=$((PASS+1));
else echo "FAIL M50: --compute-only wyslal powiadomienie!"; FAIL=$((FAIL+1)); fi

# --- M49: nieudany send NIE zapisuje cooldownu (retry mozliwy) ---
cat > "$T/bin/termux-notification" <<'EOF'
#!/usr/bin/env bash
echo "STUB-FAIL $*" >> "$STUB_LOG"; exit 1
EOF
chmod +x "$T/bin/termux-notification"
M49C="$T/c-m49.json"; mkcache "$M49C" 24 28 10; : > "$STUB_LOG"
HOME=/data/data/com.termux/files/home PATH="$T/bin:$PATH" \
  CLAUDE_USAGE_CACHE_FILE="$M49C" CLAUDE_USAGE_HISTORY_FILE="$T/h-m49.csv" bash "$PACE" --scheduled
# po nieudanym send: last_notification_epoch ma NIE byc ustawiony
if python3 -c "
import json,sys
c=json.load(open('$M49C'))
sys.exit(0 if not c.get('last_notification_epoch') else 1)
"; then echo "PASS M49 fail-send-bez-cooldownu"; PASS=$((PASS+1));
else echo "FAIL M49: cooldown zapisany mimo nieudanego send"; FAIL=$((FAIL+1)); fi
# przywroc atrape sukcesu
cat > "$T/bin/termux-notification" <<'EOF'
#!/usr/bin/env bash
echo "STUB-NOTIF $*" >> "$STUB_LOG"; exit 0
EOF
chmod +x "$T/bin/termux-notification"

# --- w proot (HOME=/root) NIE wolno wysylac ---
PC="$T/c-proot.json"; mkcache "$PC" 24 28 10
: > "$STUB_LOG"
PATH="$T/bin:$PATH" CLAUDE_USAGE_CACHE_FILE="$PC" CLAUDE_USAGE_HISTORY_FILE="$T/h-proot.csv" bash "$PACE" --scheduled
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

# --- glitch API 7d: licznik spada w trakcie okna -> HWM trzyma projekcje (nie false LOW, nie absurd 333%) ---
GL="$T/c-glitch.json"; mkcache "$GL" 28 82 10   # used 28, reset za 82h -> elapsed realny ~51%
CLAUDE_USAGE_CACHE_FILE="$GL" CLAUDE_USAGE_HISTORY_FILE="$T/h-glitch.csv" bash "$PACE" --compute-only
python3 -c "import json; d=json.load(open('$GL')); d['seven_day']['used_pct']=3.0; json.dump(d,open('$GL','w'))"  # API prze-bazowuje used->3
CLAUDE_USAGE_CACHE_FILE="$GL" CLAUDE_USAGE_HISTORY_FILE="$T/h-glitch.csv" bash "$PACE" --compute-only
GLP=$(python3 -c "import json;print(round((json.load(open('$GL')).get('pace') or {}).get('projection_pct') or 0))")
GLE=$(python3 -c "import json;print(round((json.load(open('$GL')).get('pace') or {}).get('elapsed_pct') or 0))")
if [ "$GLP" -ge 50 ] && [ "$GLP" -le 62 ] && [ "$GLE" -ge 48 ] && [ "$GLE" -le 54 ]; then
  echo "PASS glitch-api-hwm (proj=$GLP trzyma ~55 mimo used->3; elapsed=$GLE realny)"; PASS=$((PASS+1));
else echo "FAIL glitch-api (proj=$GLP oczek 50-62; elapsed=$GLE oczek 48-54)"; FAIL=$((FAIL+1)); fi

# --- kubelki per-model (weekly_scoped): projekcja + status jak dla okna 7d ---
# $1=plik $2=used_kubelka $3=reset_za_h $4=wiek_ostatniego_fetchu_API_s
mkscoped() {
  python3 - "$@" <<'PY'
import json, sys, time
f, used, off_h, api_off = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
now = time.time()
json.dump({
  "fetched_at_epoch": now - 10, "last_api_fetch_epoch": now - api_off,
  "source": "test", "cc_version": "2.1.170",
  "five_hour": {"used_pct": 11.0, "resets_at_epoch": now + 3600},
  "seven_day": {"used_pct": 45.0, "resets_at_epoch": now + 100 * 3600},
  "model_scoped": [{"display_name": "Fable", "used_pct": used,
                    "resets_at_epoch": now + off_h * 3600}],
}, open(f, "w"))
PY
}
scoped_run() { # $1=nazwa $2=oczekiwany_status $3=oczekiwana_proj|- $4=used $5=reset_za_h $6=wiek_api_s
  local name="$1" want="$2" wproj="$3" cache="$T/c-$1.json"
  mkscoped "$cache" "$4" "$5" "${6:-10}"
  CLAUDE_USAGE_CACHE_FILE="$cache" CLAUDE_USAGE_HISTORY_FILE="$T/h-$1.csv" bash "$PACE" --compute-only
  if python3 -c "
import json,sys
b=(json.load(open('$cache')).get('model_scoped') or [{}])[0]
ok = b.get('status')=='$want'
if '$wproj' != '-':
    p=b.get('projection_pct')
    ok = ok and p is not None and abs(p-float('$wproj'))<1.0
sys.exit(0 if ok else 1)
"; then echo "PASS $name -> $want proj=$wproj"; PASS=$((PASS+1));
  else echo "FAIL $name (jest: $(python3 -c "
import json;b=(json.load(open('$cache')).get('model_scoped') or [{}])[0]
print(b.get('status'), b.get('projection_pct'))"))"; FAIL=$((FAIL+1)); fi
}

# elapsed 68h/168h = 40.5% -> proj 45/40.5*100 = 111%
scoped_run scoped-ok    OK    111 45  100
# elapsed 40.5%, used 15 -> proj 37% < 50 -> LOW (kubelek moze byc LOW gdy glowne 7d jest OK)
scoped_run scoped-low   LOW   37  15  100
# 8h od startu okna (<12h GRACE) -> brak oceny tempa
scoped_run scoped-grace GRACE -   5   160
# fetch API sprzed >2h -> kubelek STALE, mimo swiezego fetched_at_epoch ze stdin paska
scoped_run scoped-stale STALE -   45  100  10900

# glitch API na kubelku: licznik spada w trakcie okna -> HWM trzyma projekcje
GLS="$T/c-scoped-glitch.json"; mkscoped "$GLS" 28 82 10   # elapsed ~51% -> proj ~55%
CLAUDE_USAGE_CACHE_FILE="$GLS" CLAUDE_USAGE_HISTORY_FILE="$T/h-sglitch.csv" bash "$PACE" --compute-only
python3 -c "import json; d=json.load(open('$GLS')); d['model_scoped'][0]['used_pct']=3.0; json.dump(d,open('$GLS','w'))"
CLAUDE_USAGE_CACHE_FILE="$GLS" CLAUDE_USAGE_HISTORY_FILE="$T/h-sglitch.csv" bash "$PACE" --compute-only
SGP=$(python3 -c "import json;print(round((json.load(open('$GLS'))['model_scoped'][0]).get('projection_pct') or 0))")
SGU=$(python3 -c "import json;print(round((json.load(open('$GLS'))['model_scoped'][0]).get('used_hwm') or 0))")
if [ "$SGP" -ge 50 ] && [ "$SGP" -le 62 ] && [ "$SGU" = "28" ]; then
  echo "PASS scoped-glitch-hwm (proj=$SGP, used_hwm=$SGU mimo used->3)"; PASS=$((PASS+1));
else echo "FAIL scoped-glitch (proj=$SGP oczek 50-62; used_hwm=$SGU oczek 28)"; FAIL=$((FAIL+1)); fi

# brak kubelkow w cache -> zero wysypki, glowne 7d liczy sie normalnie
NS="$T/c-noscoped.json"; mkcache "$NS" 45 100 10
CLAUDE_USAGE_CACHE_FILE="$NS" CLAUDE_USAGE_HISTORY_FILE="$T/h-noscoped.csv" bash "$PACE" --compute-only
if python3 -c "
import json,sys
c=json.load(open('$NS'))
sys.exit(0 if (c.get('pace') or {}).get('status')=='OK' and c.get('model_scoped_hwm')=={} else 1)
"; then echo "PASS scoped-brak-kubelkow (7d liczy sie normalnie)"; PASS=$((PASS+1));
else echo "FAIL scoped-brak-kubelkow"; FAIL=$((FAIL+1)); fi

echo "=============================="
echo "WYNIK: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
