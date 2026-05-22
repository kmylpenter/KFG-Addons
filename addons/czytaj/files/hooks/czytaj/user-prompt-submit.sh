#!/data/data/com.termux/files/usr/bin/bash
# Voice reader hook: inject system reminder when czytaj mode is on
# + flush any leftover audio from the previous turn
# + claim "active session" so Stop hooks of OTHER Claude panes stay silent.

LOG="$HOME/.claude/czytaj.log"
echo "$(date +%H:%M:%S) pid=$$ UPS-FIRED" >> "$LOG" 2>/dev/null

# Capture hook input early — Claude Code sends JSON with transcript_path
# on stdin. We need transcript_path BEFORE the flag check so even when
# mode is off we don't accidentally consume stdin and break the JSON
# output downstream.
HOOK_INPUT=$(cat)

if [ ! -f "$HOME/.claude/czytaj.flag" ]; then
  echo "$(date +%H:%M:%S) pid=$$ UPS-EXIT mode-off" >> "$LOG" 2>/dev/null
  exit 0
fi

# Stop the Android MediaPlayer service first (sync) — pkill alone doesn't
# reach the underlying playback running inside the Termux:API APK.
termux-media-player stop >/dev/null 2>&1
echo "$(date +%H:%M:%S) pid=$$ UPS-MEDIA-STOPPED" >> "$LOG" 2>/dev/null

# Mark THIS session as active + reset spoken-text state. Done via _speak
# helpers so single source of truth, no duplicated atomic-write code.
HOOK_TMP=$(mktemp "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/czytaj-ups.XXXXXX")
printf '%s' "$HOOK_INPUT" > "$HOOK_TMP"
python3 <<PY 2>>"$LOG"
import json, os, sys
sys.path.insert(0, os.path.expanduser("~/.claude/hooks/czytaj"))
from _speak import mark_active_session, reset_state_atomic, _log
try:
    with open("$HOOK_TMP") as f:
        data = json.load(f)
except Exception as e:
    data = {}
    _log("UPS", "stdin-parse-fail", repr(e))
mark_active_session(data.get("transcript_path", ""))
reset_state_atomic()
_log("UPS", "marked-active", os.path.basename(data.get("transcript_path","") or "<none>"))
PY
rm -f "$HOOK_TMP"

# Kill ONLY in-progress audio clients. Leave both piper_server AND its
# piper-daemon child alive — daemon respawn costs ~5s cold start per turn
# (the bug that made every reply slow). The synth queue flushes itself
# because paplay is killed and the daemon-to-FIFO write fails fast.
for pat in termux-tts-speak termux-media-player paplay piper_stream; do
  pkill -9 -f "$pat" 2>/dev/null
done
echo "$(date +%H:%M:%S) pid=$$ UPS-KILLED-CLIENTS" >> "$LOG" 2>/dev/null
true

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"TRYB CZYTANIA WLACZONY: User slucha Twoich odpowiedzi przez TTS (np. jadac samochodem). Generuj zwiezle voice-friendly odpowiedzi: maksymalnie 3-5 zdan, bez markdown headers/list/blokow kodu, bez sciezek plikow w glosie (zamiast 'plik install.ps1' powiedz 'plik instalator'). Pytania decyzyjne wyraznie na koncu. Jesli musisz pokazac kod - zapisz do pliku i powiedz 'zapisalem do X, sprawdz jak dojedziesz'. User moze powiedziec 'rozwin' zeby dostac pelny tekst tej jednej odpowiedzi (wtedy ignoruj te regule jednorazowo). STREAMING PYTAN: jesli juz na poczatku odpowiedzi widzisz, ze bedziesz musial zadac pytanie decyzyjne (wybor sciezki, zatwierdzenie, brakujaca informacja), zacznij odpowiedz od tego pytania w jednym lub dwoch zdaniach, ZANIM zaczniesz tool calls. Hook PreToolUse natychmiast przeczyta to pytanie przez TTS, a ty kontynuujesz prace bez przerwy - user moze juz nagrywac odpowiedz rownolegle. Nie przerywaj swojej pracy - tylko strukturyzuj wczesnie."}}
JSON
