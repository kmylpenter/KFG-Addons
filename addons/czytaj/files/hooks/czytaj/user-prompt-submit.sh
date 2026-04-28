#!/data/data/com.termux/files/usr/bin/bash
# Voice reader hook: inject system reminder when czytaj mode is on
# + flush any leftover audio from the previous turn.

LOG="$HOME/.claude/czytaj.log"
echo "$(date +%H:%M:%S) pid=$$ UPS-FIRED" >> "$LOG" 2>/dev/null

if [ ! -f "$HOME/.claude/czytaj.flag" ]; then
  echo "$(date +%H:%M:%S) pid=$$ UPS-EXIT mode-off" >> "$LOG" 2>/dev/null
  exit 0
fi

# Stop the Android MediaPlayer service first (sync) — pkill alone doesn't
# reach the underlying playback running inside the Termux:API APK.
termux-media-player stop >/dev/null 2>&1
echo "$(date +%H:%M:%S) pid=$$ UPS-MEDIA-STOPPED" >> "$LOG" 2>/dev/null

# Atomically reset the spoken-text state. Using rm could race against a
# Stop hook from the previous turn that's mid-load; an empty-state JSON
# guarantees readers see consistent data.
python3 - <<'PY' 2>/dev/null
import json, os, fcntl
path = os.path.expanduser("~/.claude/czytaj-state.json")
tmp = path + ".tmp"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
try:
    fcntl.flock(fd, fcntl.LOCK_EX)
    os.write(fd, b'{"last_uuid":"","spoken_text":""}')
finally:
    os.close(fd)
os.replace(tmp, path)
PY

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
