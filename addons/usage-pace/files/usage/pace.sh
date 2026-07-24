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
# API_TTL_S — jak czesto wolno realnie siegnac do api/oauth/usage. Osobny od
#   CACHE_TTL_S, bo tamten pilnuje swiezosci danych ze stdin paska, a ten —
#   ruchu sieciowego. Kubelki per-model (limits[] weekly_scoped) plyna WYLACZNIE stad.
API_TTL_S="${API_TTL_S:-600}"
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
CREDS_FILE="$CREDS_FILE" CACHE_TTL_S="$CACHE_TTL_S" API_TTL_S="$API_TTL_S" \
GRACE_HOURS="$GRACE_HOURS" \
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
API_TTL = float(os.environ["API_TTL_S"])
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
# Gate na WLASNYM znaczniku last_api_fetch_epoch, nie na fetched_at_epoch:
# pasek statusu nadpisuje fetched_at_epoch danymi ze stdin co ~300 s, wiec gate
# na nim praktycznie nigdy nie przepuszczal fetchu w trakcie pracy (a wtedy
# wlasnie patrzysz na pasek). Kubelki per-model sa TYLKO z API — bez tego
# rozdzielenia bylyby martwe. --refresh = fetch bez powiadomien (wola pasek).
api_age = now - float(cache.get("last_api_fetch_epoch") or 0)
if MODE in ("--scheduled", "--refresh") and api_age >= API_TTL:
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
                # ---- kubelki per-model (2026-07-16) ----
                # Pole seven_day_sonnet swiadomie NIE jest czytane: serwer zwraca
                # null nawet po realnym zuzyciu Sonneta, a /usage w CC potwierdza
                # brak linii "Current week (Sonnet only)" — kubelek nie istnieje
                # dla tego konta. Gdyby kiedys ozyl, przyjdzie w limits[] nizej.
                # limits[] kind=weekly_scoped niesie cap per model
                # (dzis: "Fable" = wspolny kubelek premium Opus+Fable — potwierdzone
                # empirycznie: rosnie przy pracy na Opusie). Trzymamy WSZYSTKIE
                # scoped, bez allowlisty — CC filtruje je statsigiem
                # (tengu_usage_overage_included_models), ktory tu bywa pusty.
                scoped = []
                for lim in (body.get("limits") or []):
                    if not isinstance(lim, dict) or lim.get("kind") != "weekly_scoped":
                        continue
                    name = (((lim.get("scope") or {}).get("model") or {}).get("display_name"))
                    b = norm_bucket({"utilization": lim.get("percent"),
                                     "resets_at": lim.get("resets_at")})
                    if name and b:
                        b["display_name"] = name
                        scoped.append(b)
                cache["model_scoped"] = scoped
                # extra usage = spill-over PONAD limit planu (kredyty/pieniadze).
                # Anthropic kontynuuje prace po wyczerpaniu okna, jesli wlaczone.
                # used_credits jest w setnych jednostki waluty (6040 = 60.40 EUR).
                eu = body.get("extra_usage")
                # is_enabled jest WIARYGODNE: false = miesieczny limit (np. user €50)
                # osiagniety LUB user wylaczyl -> brak spill-over (twardy stop, zero
                # wydatkow). used_credits/currency bywaja null gdy wylaczone -> zachowaj
                # ostatnia znana kwote (do informacji "ile dotad zuzyto").
                if isinstance(eu, dict):
                    prev_eu = cache.get("extra_usage") or {}
                    uc = eu.get("used_credits")
                    cache["extra_usage"] = {
                        "is_enabled": bool(eu.get("is_enabled")),
                        "used_credits": uc if uc is not None else prev_eu.get("used_credits"),
                        "currency": eu.get("currency") or prev_eu.get("currency"),
                        "monthly_limit": eu.get("monthly_limit") if eu.get("monthly_limit") is not None else prev_eu.get("monthly_limit"),
                    }
                cache["fetched_at_epoch"] = now
                cache["last_api_fetch_epoch"] = now
                cache["source"] = "api"
    except Exception as e:
        fetch_err = type(e).__name__ + ": " + str(e)[:160]

# ---------- COMPUTE ----------
def eval_window(used, resets, fetched_at, prev_hwm=None):
    """Ocena okna tygodniowego — JEDNA matematyka dla glownego 7d i dla kubelkow
    per-model (limits[] weekly_scoped), zeby progi i projekcja nigdy sie nie rozjechaly.
    Zapis HWM zostaje po stronie wywolujacego (rozne miejsca w cache).

    Re-base guard (rollout Anthropica) — wersja HWM (high-water-mark):
    API bywa prze-bazowuje licznik w DOL w trakcie okna (glitch rolloutu,
    NIEZMIENIONY resets_at). W oknie o stalym resecie uzycie tylko ROSNIE az do
    resetu — kazdy spadek to glitch API, NIE realny spadek tempa. Dlatego:
      * USED chronimy high-water-markiem (max w oknie) — glitch nie zbija projekcji,
      * ELAPSED liczymy ZAWSZE od realnego startu okna (resets - 7d).
    Stara wersja kotwiczyla elapsed do chwili glitcha (rebase_epoch=teraz) -> elapsed
    bywal ~0 -> projekcja absurd (28%/8% = 333%) i resetowala sie przy kazdym glitchu.
    """
    r = {"status": "NO_DATA", "reason": "brak danych o limicie 7d", "proj": None,
         "used_hwm": None, "elapsed_pct": None, "hours_to_reset": None, "spillover": False}
    if used is None or not resets:
        return r
    if now - fetched_at > STALE_S:
        r["status"], r["reason"] = "STALE", "dane starsze niz %.0f h" % (STALE_S / 3600)
        return r
    if resets < now:
        r["status"], r["reason"] = "STALE", "okno sie zresetowalo, czekam na swieze dane"
        return r
    used = float(used)
    r["spillover"] = used >= 100.0  # przekroczony limit planu -> spill-over na kredyty
    r["hours_to_reset"] = (resets - now) / 3600.0
    r["used_hwm"] = max(used, float(prev_hwm)) if prev_hwm is not None else used
    elapsed_h = max(0.0, min(168.0, (now - (resets - WINDOW_S)) / 3600.0))  # ZAWSZE realny elapsed okna
    r["elapsed_pct"] = elapsed_h / 168.0 * 100.0
    remaining = 100.0 - r["used_hwm"]
    r["proj"] = (r["used_hwm"] / r["elapsed_pct"] * 100.0) if r["elapsed_pct"] > 0.1 else None
    if elapsed_h < GRACE_H:
        r["status"] = "GRACE"
        r["reason"] = "swieze okno (%.0f h od startu) — za malo danych" % elapsed_h
    elif r["hours_to_reset"] <= ENDGAME_H:
        if remaining > ENDGAME_REMAIN:
            r["status"] = "LOW"
            r["reason"] = "koncowka okna: zostalo %.0f%% limitu, do resetu %.0f h" % (remaining, r["hours_to_reset"])
        else:
            r["status"] = "OK"
            r["reason"] = "koncowka okna: zostalo tylko %.0f%% limitu" % remaining
    elif r["proj"] is not None and r["proj"] < EARLY_LOW:
        r["status"] = "LOW"
        r["reason"] = "projekcja %.0f%% < prog %.0f%%" % (r["proj"], EARLY_LOW)
    else:
        r["status"] = "OK"
        r["reason"] = "projekcja %.0f%%" % (r["proj"] if r["proj"] is not None else -1)
    return r

sd = cache.get("seven_day") or {}
used = sd.get("used_pct")
resets = sd.get("resets_at_epoch")
fetched = float(cache.get("fetched_at_epoch") or 0)

wkey = round(resets / 3600.0) if resets else None   # klucz okna zaokr. do godziny (API jitteruje resets sub-sek.)
hwm = cache.get("seven_day_hwm") or {}
prev_hwm = hwm.get("used_hwm") if (wkey is not None and hwm.get("reset_key") == wkey) else None
w7 = eval_window(used, resets, fetched, prev_hwm)
status, proj, reason = w7["status"], w7["proj"], w7["reason"]
used_hwm, elapsed_pct, hours_to_reset = w7["used_hwm"], w7["elapsed_pct"], w7["hours_to_reset"]
spillover = w7["spillover"]  # True = jestes PONAD 100% limitu planu -> leci extra usage (kredyty)
if used_hwm is not None and wkey is not None:
    cache["seven_day_hwm"] = {"reset_key": wkey, "used_hwm": used_hwm}

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

# ---------- kubelki per-model: TA SAMA projekcja co dla glownego okna 7d ----------
# Kubelek weekly_scoped ma wlasny licznik i wlasny resets_at, ale to takie samo okno
# tygodniowe -> liczymy go eval_window (jedna matematyka, te same progi, ten sam HWM).
# Swiezosc mierzymy last_api_fetch_epoch, a NIE fetched_at_epoch: kubelki plyna
# wylacznie z API, a fetched_at_epoch nadpisuje pasek ze stdin co ~300 s (kubelki by
# wtedy udawaly swieze, gdy fetch od godzin nie przechodzi).
api_fetched = float(cache.get("last_api_fetch_epoch") or 0)
scoped_list = [b for b in (cache.get("model_scoped") or []) if isinstance(b, dict)]
scoped_names = set(b.get("display_name") for b in scoped_list if b.get("display_name"))
prev_scoped_hwm = cache.get("model_scoped_hwm") or {}
scoped_hwm = dict((k, v) for k, v in prev_scoped_hwm.items() if k in scoped_names)  # bez sierot po znikniętych kubelkach
for b in scoped_list:
    name, b_resets = b.get("display_name"), b.get("resets_at_epoch")
    b_key = round(b_resets / 3600.0) if b_resets else None
    prev_b = scoped_hwm.get(name) or {}
    prev_b_hwm = prev_b.get("used_hwm") if (b_key is not None and prev_b.get("reset_key") == b_key) else None
    wb = eval_window(b.get("used_pct"), b_resets, api_fetched, prev_b_hwm)
    b["used_hwm"] = round(wb["used_hwm"], 1) if wb["used_hwm"] is not None else None
    b["projection_pct"] = round(wb["proj"], 1) if wb["proj"] is not None else None
    b["status"] = wb["status"]
    if name and b_key is not None and wb["used_hwm"] is not None:
        scoped_hwm[name] = {"reset_key": b_key, "used_hwm": wb["used_hwm"]}
cache["model_scoped_hwm"] = scoped_hwm

eu = cache.get("extra_usage") or {}
cache["pace"] = {
    "computed_at_epoch": now,
    "elapsed_pct": round(elapsed_pct, 1) if elapsed_pct is not None else None,
    "used_hwm": round(used_hwm, 1) if used_hwm is not None else None,  # wartosc CHRONIONA (max w oknie) = to wyswietlamy, spojnie z projekcja
    "projection_pct": round(proj, 1) if proj is not None else None,
    "projection_pct_5h": round(proj5, 1) if proj5 is not None else None,
    "hours_to_reset": round(hours_to_reset, 1) if hours_to_reset is not None else None,
    "status": status,
    "reason": reason,
    "spillover": spillover,                       # PONAD limit -> leca kredyty
    "extra_used_credits": eu.get("used_credits"), # w setnych waluty (6040 = 60.40)
    "extra_currency": eu.get("currency"),
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
        hours_to_reset or 0, 100.0 - (used_hwm if used_hwm is not None else float(used or 0)))
    print("NOTIFY\t%s\t%s" % (title, body))

try:
    atomic_write_json(CACHE_FILE, cache)
except Exception as e:
    print("ERR cache-write: %s" % e, file=sys.stderr)

extra = (" | fetch: " + fetch_err) if fetch_err else ""
used_disp = used_hwm if used_hwm is not None else used   # HWM = wartosc chroniona; spojna z projekcja
print("STATUS %s proj=%s used7d=%s elapsed=%s%% reset_za=%sh %s%s" % (
    status,
    "?" if proj is None else "%.0f%%" % proj,
    "?" if used_disp is None else "%.0f%%" % float(used_disp),
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
for b in (c.get("model_scoped") or []):
    if isinstance(b, dict) and b.get("display_name"):
        u = b.get("used_hwm") if b.get("used_hwm") is not None else b.get("used_pct")
        pr = b.get("projection_pct")
        print("Kubelek %s: %s%% -> projekcja %s [%s]" % (
            b["display_name"],
            "?" if u is None else "%.0f" % float(u),
            "?" if pr is None else "%.0f%%" % pr,
            b.get("status", "?")))
if p.get("spillover"):
    print(">>> SPILL-OVER AKTYWNY: jestes PONAD limit planu — leca extra usage (kredyty)")
uc = p.get("extra_used_credits")
if uc:
    print("Extra usage zuzyte: %.2f %s" % (uc / 100.0, p.get("extra_currency") or ""))
PYEOF2
  fi
fi

exit 0
