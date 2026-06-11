#!/usr/bin/env bash
# ============================================================================
# pace.sh — usage-pace monitor (SSOT logiki tempa zuzycia limitow Claude Max)
#
# Liczy, czy tempo zuzycia limitu tygodniowego (7d) jest na sciezce do pelnego
# wykorzystania. Gdy projekcja za niska -> powiadomienie (tylko po stronie
# Termuxa). NIGDY sam nie uruchamia zadnych sesji — wylacznie informuje.
#
# Tryby:
#   --compute-only   przelicz z cache (bez siegania do internetu); wolane
#                    w tle przez pasek statusu po odswiezeniu cache
#   --scheduled      tryb harmonogramu: pobierz dane jesli cache stary,
#                    przelicz, ewentualnie wyslij powiadomienie
#   --status         wypisz czytelny status po polsku (do recznego sprawdzania)
#   --notify-test    wyslij testowe powiadomienie (dziala tylko w Termuksie)
#
# Dziala identycznie w proot (Ubuntu) i w Termuksie — uzywa $HOME/.claude,
# ktory po obu stronach wskazuje ten sam katalog (bind mount).
# ============================================================================

# ======================= KONFIGURACJA (strojenie) ===========================
# Mozesz zmieniac te liczby — to jedyne miejsce z progami.
#
# CACHE_TTL_S — jak dlugo (sekundy) dane w cache sa "swieze". Ponizej tego
#   wieku nikt nie robi pobrania z internetu. 300 = 5 minut.
CACHE_TTL_S="${CACHE_TTL_S:-300}"
#
# GRACE_HOURS — ile godzin PO RESECIE okna tygodniowego status jest zawsze OK
#   (za malo danych, by oceniac tempo). 12 = pierwsze pol doby wolne od alarmow.
GRACE_HOURS="${GRACE_HOURS:-12}"
#
# EARLY_LOW_PROJECTION_PCT — prog dla poczatku/srodka okna: status LOW dopiero
#   gdy projekcja (ile % limitu wykorzystam przy obecnym tempie) spadnie
#   PONIZEJ tej wartosci. 50 = alarm gdy zmierzam do zuzycia mniej niz polowy.
#   Jednodniowe przerwy sa normalne — podnos ostroznie, bo zacznie spamowac.
EARLY_LOW_PROJECTION_PCT="${EARLY_LOW_PROJECTION_PCT:-50}"
#
# ENDGAME_HOURS — ile godzin przed resetem wlacza sie tryb agresywny.
ENDGAME_HOURS="${ENDGAME_HOURS:-48}"
#
# ENDGAME_REMAINING_PCT — w trybie agresywnym: status LOW gdy do wykorzystania
#   zostalo WIECEJ niz tyle % limitu (te procenty przepadna przy resecie).
ENDGAME_REMAINING_PCT="${ENDGAME_REMAINING_PCT:-15}"
#
# NOTIFY_COOLDOWN_H — minimalny odstep (godziny) miedzy powiadomieniami.
NOTIFY_COOLDOWN_H="${NOTIFY_COOLDOWN_H:-6}"
#
# STALE_HOURS — po ilu godzinach od ostatniego pobrania dane uznajemy za
#   przeterminowane (segment oznaczany '?', zero powiadomien).
STALE_HOURS="${STALE_HOURS:-2}"
#
# GRACE_HOURS_5H — ile godzin po resecie okna 5h NIE pokazywac jego projekcji
#   (na starcie okna jest zbyt rozchwiana). 0.5 = pierwsze pol godziny bez strzalki.
#   Projekcja 5h jest TYLKO informacyjna — nigdy nie wysyla powiadomien.
GRACE_HOURS_5H="${GRACE_HOURS_5H:-0.5}"
#
# UA_VERSION_FALLBACK — wersja Claude Code do naglowka User-Agent, gdyby
#   w cache nie bylo aktualnej (pasek statusu zapisuje ja automatycznie).
UA_VERSION_FALLBACK="${UA_VERSION_FALLBACK:-2.1.170}"
# ============================================================================

set -u

# --- sciezki (te same dane po obu stronach swiata) ---
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
if [ ! -d "$CLAUDE_DIR" ]; then
  for cand in /data/data/com.termux/files/home/.claude /root/.claude; do
    [ -d "$cand" ] && CLAUDE_DIR="$cand" && break
  done
fi
USAGE_DIR="$CLAUDE_DIR/usage"
CACHE_FILE="${CLAUDE_USAGE_CACHE_FILE:-$CLAUDE_DIR/usage-cache.json}"
HISTORY_FILE="${CLAUDE_USAGE_HISTORY_FILE:-$CLAUDE_DIR/usage-history.csv}"
CREDS_FILE="$CLAUDE_DIR/.credentials.json"
LOG_FILE="$USAGE_DIR/pace.log"
LOCK_FILE="$USAGE_DIR/pace.lock"
mkdir -p "$USAGE_DIR" 2>/dev/null

MODE="${1:---scheduled}"

# --- log z prosta rotacja (max ~200 KB) ---
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODE] $*" >> "$LOG_FILE" 2>/dev/null
  if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 200000 ]; then
    tail -c 100000 "$LOG_FILE" > "$LOG_FILE.tmp.$$" 2>/dev/null && mv "$LOG_FILE.tmp.$$" "$LOG_FILE"
  fi
}

# --- czy wolno stad wysylac powiadomienia? (tylko natywny Termux) ---
can_notify() {
  case "$HOME" in
    /data/data/com.termux/files/home*) command -v termux-notification >/dev/null 2>&1 && return 0 ;;
  esac
  return 1
}

send_notification() {
  # $1=tytul $2=tresc — fire-and-forget, nie moze nic zablokowac
  timeout 30 termux-notification \
    --id usage-pace \
    --title "$1" \
    --content "$2" \
    --priority high \
    --action "am start --user 0 -n com.termux/com.termux.app.TermuxActivity" \
    >/dev/null 2>&1
  return $?
}

if [ "$MODE" = "--notify-test" ]; then
  if can_notify; then
    send_notification "Claude usage-pace: test" "Powiadomienia dzialaja. To tylko test." \
      && echo "OK: powiadomienie wyslane" || echo "BLAD: termux-notification zwrocil blad"
  else
    echo "POMINIETO: powiadomienia dzialaja tylko po stronie Termuxa (HOME=$HOME)"
  fi
  exit 0
fi

# --- blokada przed rownoleglymi przebiegami (jesli flock dostepny) ---
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" 2>/dev/null && flock -w 10 9 2>/dev/null || true
fi

# ============================================================================
# Rdzen w pythonie: JSON + matematyka czasu + ewentualny fetch + zapis cache
# + historia CSV + decyzja o powiadomieniu. Wypisuje linie:
#   STATUS <status> <projekcja> <opis...>      (zawsze)
#   NOTIFY<TAB><tytul><TAB><tresc>             (tylko gdy nalezy powiadomic)
# ============================================================================
PY_OUT="$(
MODE="$MODE" CACHE_FILE="$CACHE_FILE" HISTORY_FILE="$HISTORY_FILE" \
CREDS_FILE="$CREDS_FILE" CACHE_TTL_S="$CACHE_TTL_S" GRACE_HOURS="$GRACE_HOURS" \
EARLY_LOW_PROJECTION_PCT="$EARLY_LOW_PROJECTION_PCT" ENDGAME_HOURS="$ENDGAME_HOURS" \
ENDGAME_REMAINING_PCT="$ENDGAME_REMAINING_PCT" NOTIFY_COOLDOWN_H="$NOTIFY_COOLDOWN_H" \
STALE_HOURS="$STALE_HOURS" UA_VERSION_FALLBACK="$UA_VERSION_FALLBACK" \
GRACE_HOURS_5H="$GRACE_HOURS_5H" \
CAN_NOTIFY="$(can_notify && echo 1 || echo 0)" \
python3 - <<'PYEOF'
import json, os, sys, time, tempfile, datetime

MODE = os.environ["MODE"]
CACHE_FILE = os.environ["CACHE_FILE"]
HISTORY_FILE = os.environ["HISTORY_FILE"]
CREDS_FILE = os.environ["CREDS_FILE"]
TTL = float(os.environ["CACHE_TTL_S"])
GRACE_H = float(os.environ["GRACE_HOURS"])
EARLY_LOW = float(os.environ["EARLY_LOW_PROJECTION_PCT"])
ENDGAME_H = float(os.environ["ENDGAME_HOURS"])
ENDGAME_REMAIN = float(os.environ["ENDGAME_REMAINING_PCT"])
COOLDOWN_S = float(os.environ["NOTIFY_COOLDOWN_H"]) * 3600
STALE_S = float(os.environ["STALE_HOURS"]) * 3600
UA_FALLBACK = os.environ["UA_VERSION_FALLBACK"]
CAN_NOTIFY = os.environ.get("CAN_NOTIFY") == "1"
WINDOW_S = 7 * 24 * 3600.0
now = time.time()

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

def atomic_write_json(path, obj):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(prefix=".usage-cache.", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, indent=1)
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except Exception: pass
        raise

def parse_resets_at(v):
    """endpoint daje ISO, pasek statusu epoch — normalizuj do epoch (s)."""
    if v is None: return None
    if isinstance(v, (int, float)):
        return float(v) / (1000.0 if v > 4e12 else 1.0)
    try:
        s = str(v).replace("Z", "+00:00")
        return datetime.datetime.fromisoformat(s).timestamp()
    except Exception:
        return None

def norm_bucket(b):
    if not isinstance(b, dict): return None
    used = b.get("utilization", b.get("used_percentage", b.get("used_pct")))
    resets = parse_resets_at(b.get("resets_at", b.get("resets_at_epoch")))
    if used is None: return None
    try: used = float(used)
    except Exception: return None
    return {"used_pct": used, "resets_at_epoch": resets}

cache = load_json(CACHE_FILE)

# ---------- FETCH (tylko --scheduled i tylko gdy cache stary) ----------
fetch_err = None
age = now - float(cache.get("fetched_at_epoch") or 0)
if MODE == "--scheduled" and age >= TTL:
    try:
        creds = load_json(CREDS_FILE).get("claudeAiOauth", {})
        token = creds.get("accessToken")
        exp = creds.get("expiresAt") or 0
        exp = float(exp) / (1000.0 if exp > 4e12 else 1.0)
        if not token:
            fetch_err = "brak tokena OAuth"
        elif exp and exp < now:
            fetch_err = "token wygasl (odswiezy sie przy nastepnej sesji Claude)"
        else:
            import urllib.request
            ver = cache.get("cc_version") or UA_FALLBACK
            req = urllib.request.Request(
                "https://api.anthropic.com/api/oauth/usage",
                headers={
                    "Authorization": "Bearer " + token,
                    "anthropic-beta": "oauth-2025-04-20",
                    "User-Agent": "claude-code/" + ver,
                    "Accept": "application/json",
                })
            with urllib.request.urlopen(req, timeout=25) as r:
                body = json.load(r)
            fh = norm_bucket(body.get("five_hour"))
            sd = norm_bucket(body.get("seven_day"))
            if sd is None:
                fetch_err = "odpowiedz bez seven_day (format sie zmienil?)"
            else:
                cache["five_hour"] = fh
                cache["seven_day"] = sd
                cache["fetched_at_epoch"] = now
                cache["source"] = "api"
    except Exception as e:
        fetch_err = type(e).__name__ + ": " + str(e)[:160]

# ---------- COMPUTE ----------
sd = cache.get("seven_day") or {}
used = sd.get("used_pct")
resets = sd.get("resets_at_epoch")
fetched = float(cache.get("fetched_at_epoch") or 0)
status, proj, reason = "NO_DATA", None, "brak danych o limicie 7d"
hours_to_reset = elapsed_pct = None

if used is not None and resets:
    if now - fetched > STALE_S:
        status, reason = "STALE", "dane starsze niz %.0f h" % (STALE_S / 3600)
    elif resets < now:
        status, reason = "STALE", "okno sie zresetowalo, czekam na swieze dane"
    else:
        hours_to_reset = (resets - now) / 3600.0
        elapsed_h = max(0.0, min(168.0, 168.0 - hours_to_reset))
        elapsed_pct = elapsed_h / 168.0 * 100.0
        remaining = 100.0 - float(used)
        proj = (float(used) / elapsed_pct * 100.0) if elapsed_pct > 0.1 else None
        if elapsed_h < GRACE_H:
            status = "GRACE"
            reason = "swieze okno (%.0f h od resetu) — za malo danych" % elapsed_h
        elif hours_to_reset <= ENDGAME_H:
            if remaining > ENDGAME_REMAIN:
                status = "LOW"
                reason = "koncowka okna: zostalo %.0f%% limitu, do resetu %.0f h" % (remaining, hours_to_reset)
            else:
                status = "OK"
                reason = "koncowka okna: zostalo tylko %.0f%% limitu" % remaining
        else:
            if proj is not None and proj < EARLY_LOW:
                status = "LOW"
                reason = "projekcja %.0f%% < prog %.0f%%" % (proj, EARLY_LOW)
            else:
                status = "OK"
                reason = "projekcja %.0f%%" % (proj if proj is not None else -1)

# ---------- okno 5h: projekcja TYLKO informacyjna (zero alarmow) ----------
proj5 = None
fh_b = cache.get("five_hour") or {}
fh_used, fh_resets = fh_b.get("used_pct"), fh_b.get("resets_at_epoch")
W5 = 5 * 3600.0
GRACE5_S = float(os.environ["GRACE_HOURS_5H"]) * 3600.0
if (fh_used is not None and fh_resets and fh_resets > now
        and (now - fetched) <= STALE_S):
    el5 = max(0.0, min(W5, W5 - (fh_resets - now)))
    el5_pct = el5 / W5 * 100.0
    if el5 >= GRACE5_S and el5_pct > 0.1:
        proj5 = float(fh_used) / el5_pct * 100.0

cache["pace"] = {
    "computed_at_epoch": now,
    "elapsed_pct": round(elapsed_pct, 1) if elapsed_pct is not None else None,
    "projection_pct": round(proj, 1) if proj is not None else None,
    "projection_pct_5h": round(proj5, 1) if proj5 is not None else None,
    "hours_to_reset": round(hours_to_reset, 1) if hours_to_reset is not None else None,
    "status": status,
    "reason": reason,
}

# ---------- HISTORIA CSV (jeden wiersz na kazdy NOWY odczyt danych) ----------
try:
    if fetched and fetched != cache.get("last_history_fetched_epoch"):
        new_file = not os.path.exists(HISTORY_FILE)
        with open(HISTORY_FILE, "a") as f:
            if new_file:
                f.write("timestamp,utilization_5h,utilization_7d,projection_pct,status\n")
            fh_used = (cache.get("five_hour") or {}).get("used_pct")
            ts = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
            f.write("%s,%s,%s,%s,%s\n" % (
                ts,
                "" if fh_used is None else round(fh_used, 1),
                "" if used is None else round(float(used), 1),
                "" if proj is None else round(proj, 1),
                status))
        cache["last_history_fetched_epoch"] = fetched
except Exception:
    pass

# ---------- DECYZJA O POWIADOMIENIU ----------
last_notif = float(cache.get("last_notification_epoch") or 0)
# M50: powiadamia WYLACZNIE harmonogram (--scheduled). Pasek odpala pace.sh
# --compute-only przy kazdym odswiezeniu — bez tego warunku moglby emitowac
# duplikaty i wypalac slot cooldownu na stronie Termuksa.
# M49: cooldownu NIE zapisujemy tutaj — robi to bash DOPIERO po udanej wysylce,
# inaczej nieudany send i tak stlumilby kolejna probe na 6h.
if status == "LOW" and CAN_NOTIFY and MODE == "--scheduled" and (now - last_notif) >= COOLDOWN_S:
    title = "Claude: niskie tempo zuzycia"
    body = "Projekcja: %s%% limitu 7d, reset za %.0f h (zostalo %.0f%%). Odpal sesje autonomiczna (np. petla-noc)." % (
        ("%.0f" % proj) if proj is not None else "?",
        hours_to_reset or 0, 100.0 - float(used or 0))
    print("NOTIFY\t%s\t%s" % (title, body))

try:
    atomic_write_json(CACHE_FILE, cache)
except Exception as e:
    print("ERR cache-write: %s" % e, file=sys.stderr)

extra = (" | fetch: " + fetch_err) if fetch_err else ""
print("STATUS %s proj=%s used7d=%s elapsed=%s%% reset_za=%sh %s%s" % (
    status,
    "?" if proj is None else "%.0f%%" % proj,
    "?" if used is None else "%.0f%%" % float(used),
    "?" if elapsed_pct is None else "%.0f" % elapsed_pct,
    "?" if hours_to_reset is None else "%.0f" % hours_to_reset,
    reason, extra))
PYEOF
)"
PY_RC=$?

# --- obsluga wyniku ---
STATUS_LINE="$(printf '%s\n' "$PY_OUT" | grep '^STATUS ' | head -1)"
NOTIFY_LINE="$(printf '%s\n' "$PY_OUT" | grep '^NOTIFY' | head -1)"

log "${STATUS_LINE:-python rc=$PY_RC bez statusu}"

if [ -n "$NOTIFY_LINE" ]; then
  TITLE="$(printf '%s' "$NOTIFY_LINE" | cut -f2)"
  BODY="$(printf '%s' "$NOTIFY_LINE" | cut -f3)"
  if send_notification "$TITLE" "$BODY"; then
    log "NOTIFIED: $BODY"
    # M49: cooldown zapisujemy DOPIERO teraz (po sukcesie), atomowo
    python3 - "$CACHE_FILE" <<'PYUP' 2>/dev/null || true
import json, os, sys, tempfile, time
p = sys.argv[1]
try: c = json.load(open(p))
except Exception: sys.exit(0)
c["last_notification_epoch"] = time.time()
fd, t = tempfile.mkstemp(dir=os.path.dirname(p) or ".")
with os.fdopen(fd, "w") as f: json.dump(c, f, indent=1)
os.replace(t, p)
PYUP
  else
    log "NOTIFY-FAILED (termux-notification blad) — cooldown NIE zapisany, retry przy nast. przebiegu"
  fi
fi

if [ "$MODE" = "--status" ]; then
  echo "${STATUS_LINE:-brak danych}"
  if [ -f "$CACHE_FILE" ]; then
    python3 - "$CACHE_FILE" <<'PYEOF2'
import json, sys, time
c = json.load(open(sys.argv[1]))
p = c.get("pace") or {}
age = time.time() - float(c.get("fetched_at_epoch") or 0)
print("Dane sprzed: %.0f min (zrodlo: %s)" % (age / 60, c.get("source", "?")))
print("Powod: %s" % p.get("reason"))
PYEOF2
  fi
fi

exit 0
