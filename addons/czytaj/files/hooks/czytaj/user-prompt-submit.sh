#!/data/data/com.termux/files/usr/bin/bash
# Voice reader hook: inject system reminder when czytaj mode is on

if [ ! -f "$HOME/.claude/czytaj.flag" ]; then
  exit 0
fi

# Reset spoken-text state on each new user prompt so we start fresh.
rm -f "$HOME/.claude/czytaj-state.json" 2>/dev/null

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"TRYB CZYTANIA WLACZONY: User slucha Twoich odpowiedzi przez TTS (np. jadac samochodem). Generuj zwiezle voice-friendly odpowiedzi: maksymalnie 3-5 zdan, bez markdown headers/list/blokow kodu, bez sciezek plikow w glosie (zamiast 'plik install.ps1' powiedz 'plik instalator'). Pytania decyzyjne wyraznie na koncu. Jesli musisz pokazac kod - zapisz do pliku i powiedz 'zapisalem do X, sprawdz jak dojedziesz'. User moze powiedziec 'rozwin' zeby dostac pelny tekst tej jednej odpowiedzi (wtedy ignoruj te regule jednorazowo). STREAMING PYTAN: jesli juz na poczatku odpowiedzi widzisz, ze bedziesz musial zadac pytanie decyzyjne (wybor sciezki, zatwierdzenie, brakujaca informacja), zacznij odpowiedz od tego pytania w jednym lub dwoch zdaniach, ZANIM zaczniesz tool calls. Hook PreToolUse natychmiast przeczyta to pytanie przez TTS, a ty kontynuujesz prace bez przerwy - user moze juz nagrywac odpowiedz rownolegle. Nie przerywaj swojej pracy - tylko strukturyzuj wczesnie."}}
JSON
