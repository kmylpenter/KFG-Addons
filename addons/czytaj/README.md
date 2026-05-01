# czytaj — Tryb Czytania (Voice Reader)

Toggle TTS odczytywania odpowiedzi Claude'a. Przeznaczone do hands-free use (np. praca przy kierownicy).

## Jak działa

1. `/czytaj` — toggle trybu (włącza/wyłącza)
2. Gdy włączony:
   - Claude generuje krótsze, voice-friendly odpowiedzi (3-5 zdań, bez markdown/kodu)
   - Po każdej odpowiedzi Stop hook czyta ją na głos przez Piper (neural, polski)
3. `/czytaj` jeszcze raz — wyłącza
4. `rozwin` — magiczne słowo: w jednej odpowiedzi Claude pomija reguły zwięzłości i daje pełny tekst.

State: plik flag w `~/.claude/czytaj.flag` (istnieje = on).

## Pauza (`/pauza`)

Android 16 bez root nie pozwala wykryć kiedy WhatsApp/Spotify/Messenger
gra dźwięk (wszystkie 4 API są zablokowane: dumpsys, cmd media_session,
notification listener, AudioPlaybackConfiguration). Zamiast auto-detekcji
masz **manualną pauzę**:

- `/pauza` — wstrzymuje TTS na 60 sekund (drugie wywołanie wznawia natychmiast)
- `touch ~/.claude/czytaj-pause.flag` — pauza nieskończona (pusty plik)
- `echo $(($(date +%s) + 300)) > ~/.claude/czytaj-pause.flag` — pauza N sekund

Podczas pauzy hooki SKIPują z `reason=other-audio`. Po wygaśnięciu flag
plik kasuje się automatycznie.

Dodatkowo TTS sam się wstrzyma gdy:
- music volume = 0 (telefon wyciszony — celowo NIE sprawdzamy notification stream
  bo tryb "nie przeszkadzaj" często ścisza notification a TTS przez music gra dalej)
- już mówimy (kolejne hooki czekają na zakończenie obecnego TTS)

## Detekcja odblokowania ekranu (zalecane)

Najbardziej niezawodny "wyłącznik": TTS gra TYLKO gdy ekran jest odblokowany.
Telefon w kieszeni / odłożony / na blokadzie = absolutna cisza. Gdy aktywnie
korzystasz z urządzenia (np. kodujesz na pasku narzędzi w aucie) = czyta.

Ponieważ Android non-root nie udostępnia stanu blokady przez żadne CLI,
korzystamy z **Wireless Debugging** Androida — Termux paruje się sam ze
sobą przez localhost ADB i wywołuje `dumpsys window`. Brzmi groźnie, ale
to standardowy mechanizm developerski, nie root, daje tylko shell uid.

### Jednorazowy setup

```bash
bash ~/.claude/hooks/czytaj/setup-adb-pairing.sh
```

Skrypt poprowadzi przez:
1. Włączenie Developer Options (jeśli jeszcze nie) i Wireless Debugging
2. Otwarcie "Pair device with pairing code" i wprowadzenie portu + kodu
3. Połączenie + smoke test
4. Zapisanie konfiguracji

Po reboocie telefonu uruchom:
```bash
bash ~/.claude/hooks/czytaj/adb-connect.sh
```
(pairing przeżywa restart, sama sesja połączenia nie).

### Ryzyka

- **Sieć WiFi**: w publicznej sieci ktoś teoretycznie mógłby próbować
  sparować się z twoim telefonem, ale wymaga to fizycznego zobaczenia
  6-cyfrowego kodu wyświetlanego na ekranie. W domu/aucie ryzyko zerowe.
- **Apki bankowe**: niektóre wykrywają Developer Mode i odmawiają
  działania. Sprawdź swój bank zanim zostawisz Developer Options ON.
- **Nie root'uje, nie odblokowuje bootloadera, nie zmienia security**.

### Wyłączenie

```bash
rm ~/.claude/czytaj-adb.flag
```
Detekcja przestaje działać (TTS znów gra niezależnie od stanu ekranu).
Pairing pozostaje — żeby usunąć całkowicie: `adb kill-server` i wyłącz
Wireless Debugging w Settings.

## Wymagania

- **Termux** (Android) — obecnie tylko ta platforma
- `pkg install termux-api` — CLI tools
- **Termux:API APK z F-Droid** (osobna apka, NIE Google Play): https://f-droid.org/packages/com.termux.api/
- `python3` (zwykle preinstalowany w Termux)
- **Piper TTS (WYMAGANY)** — neural model offline. Zbuduj wg instrukcji
  z `gyroing/piper-tts-for-termux` (binarka + libpiper.so + espeak-ng-data
  + pl_PL-gosia-medium.onnx). Bez Pipera addon NIE czyta głosem (fallback
  termux-tts-speak został usunięty bo zawiesza się na Android 14+).

## Instalacja

```bash
cd KFG-Addons/addons/czytaj
bash install.sh
```

Skrypt:
- Kopiuje slash command do `~/.claude/commands/`
- Kopiuje hooki do `~/.claude/hooks/czytaj/`
- Patchuje `~/.claude/settings.json` (dodaje UserPromptSubmit + PreToolUse + Stop hooki)

## Pliki

- `commands/czytaj.md` — slash command (toggle, deleguje do toggle.sh)
- `commands/pauza.md` — slash command (pauza 60s / wznowienie)
- `hooks/czytaj/toggle.sh` — single source of truth dla on/off
- `hooks/czytaj/user-prompt-submit.sh` — wstrzykuje system reminder + reset state
- `hooks/czytaj/pre-tool-use.sh` + `pre-tool-use.py` — streaming pytań przed tool calls
- `hooks/czytaj/stop.sh` + `stop.py` — wyciąga ostatnią wiadomość z transcript i odpala TTS
- `hooks/czytaj/_speak.py` — wspólna logika (retry, pauza, kolejność audio)

## Test

```bash
# Smoke test (wymaga uruchomionego daemona):
echo "test polskiego głosu" | python3 ~/.claude/hooks/czytaj/piper_stream.py
```

Jeśli słyszysz głos — Piper działa.

## Roadmap

- Wsparcie Windows (PowerShell + SAPI) — gdy potrzebne
- Konfiguracja prędkości i głośności
- Long-lived player daemon (zastępuje subprocess chain — Tier-2 audytu)

## Tradeoffs

- Stop hook wykonuje regex na markdown — nie jest perfekcyjny dla skomplikowanych formatowań
- TTS w tle (`subprocess.Popen` z `start_new_session=True`) — proces żyje po zakończeniu hooka
- Voice-friendly formatowanie zależy od Claude'a (nie wymuszone twardo) — w razie problemów można dorzucić twardszy preprocessing w stop.py
