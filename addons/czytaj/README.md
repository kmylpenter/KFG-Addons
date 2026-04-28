# czytaj — Tryb Czytania (Voice Reader)

Toggle TTS odczytywania odpowiedzi Claude'a. Przeznaczone do hands-free use (np. praca przy kierownicy).

## Jak działa

1. `/czytaj` — toggle trybu (włącza/wyłącza)
2. Gdy włączony:
   - Claude generuje krótsze, voice-friendly odpowiedzi (3-5 zdań, bez markdown/kodu)
   - Po każdej odpowiedzi Stop hook czyta ją na głos przez `termux-tts-speak` (polski)
3. `/czytaj` jeszcze raz — wyłącza

State: plik flag w `~/.claude/czytaj.flag` (istnieje = on).

## Wymagania

- **Termux** (Android) — obecnie tylko ta platforma
- `pkg install termux-api` — CLI tools
- **Termux:API APK z F-Droid** (osobna apka, NIE Google Play): https://f-droid.org/packages/com.termux.api/
- `python3` (zwykle preinstalowany w Termux)
- Polski głos w systemowym Google TTS (Speech Services by Google) — domyślnie powinien być

## Instalacja

```bash
cd KFG-Addons/addons/czytaj
bash install.sh
```

Skrypt:
- Kopiuje slash command do `~/.claude/commands/`
- Kopiuje hooki do `~/.claude/hooks/czytaj/`
- Patchuje `~/.claude/settings.json` (dodaje UserPromptSubmit + Stop hooki)

## Pliki

- `commands/czytaj.md` — slash command (toggle)
- `hooks/czytaj/user-prompt-submit.sh` — wstrzykuje system reminder do promptu gdy tryb on
- `hooks/czytaj/stop.sh` + `stop.py` — wyciąga ostatnią wiadomość Claude'a z transcript i odpala TTS

## Test

```bash
termux-tts-speak -l pl-PL "test polskiego głosu"
```

Jeśli słyszysz głos — wszystko OK.

## Roadmap

- Upgrade Google TTS → Piper TTS (neural, lepsza jakość PL) — opcjonalne, później
- Wsparcie Windows (PowerShell + SAPI) — gdy potrzebne
- Konfiguracja prędkości i głośności

## Tradeoffs

- Stop hook wykonuje regex na markdown — nie jest perfekcyjny dla skomplikowanych formatowań
- TTS w tle (`subprocess.Popen` z `start_new_session=True`) — proces żyje po zakończeniu hooka
- Voice-friendly formatowanie zależy od Claude'a (nie wymuszone twardo) — w razie problemów można dorzucić twardszy preprocessing w stop.py
