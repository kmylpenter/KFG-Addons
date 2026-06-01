# Kontrakt: Voice Typer → czytaj "active-window" flaga

**Dla Klauda utrzymującego klawiaturę Voice Typer** (pakiet `com.utilityhub.voicekeyboard`).
To jest prompt + specyfikacja. Wklej go tamtemu Klaudowi.

## Po co to

`czytaj` (czytnik TTS działający w PRoot/Debianie wewnątrz Termuksa) ma funkcję
"przeczytaj ostatnią wiadomość" pod klawiszem. Przy KILKU otwartych oknach Claude Code
(każde w innej sesji Termuksa, każde z włączonym czytaniem) czytaj musi wiedzieć, na
KTÓRE okno user właśnie patrzy — żeby przeczytać wiadomość z TEGO okna, nie z innego.

Sprawdziliśmy wyczerpująco: **nic dostępne z PRoot/shell nie zdradza okna na wierzchu** —
prywatne `shared_prefs` Termuksa są `permission denied` dla shell-uid, `/dev/pts` też,
a Status Line renderuje się dla WSZYSTKICH aktywnych sesji (ślad aktywności, nie fokusu).
**Jedyny komponent, który zna świadomą zmianę okna przez usera, to klawiatura** — bo to
ona wywołuje przełączenie. Stąd ten kontrakt (analogiczny do istniejącej flagi mikrofonu
`voice-typer-recording-flag-CONTRACT.md` — ten sam wzorzec: klawiatura pisze, czytaj czyta).

## Co klawiatura ma robić

Gdy user przełącza się / fokusuje okno Termuksa (klawiszem przełączania okien, a najlepiej
**dedykowanymi przyciskami per-projekt**), zapisz cwd projektu tego okna do flagi.

- **Plik flagi:** `/storage/emulated/0/Download/Termux-flags/czytaj-active-window.flag`
  (ten sam katalog, do którego już piszesz `voice-typer-recording.flag` — jest zapisywalny
  dla klawiatury i czytelny dla czytaj z PRoot).
- **Format:** dokładnie JEDNA linia = cwd projektu okna na wierzchu, w przestrzeni PRoot,
  np. `/root/projekty/KFG-Addons`. Bez wymaganego znaku nowej linii (czytaj robi `.strip()`).
- **Atomowo:** pisz do pliku tymczasowego + `rename`, żeby czytaj nigdy nie złapał połowy.
- **Kiedy:** przy KAŻDYM przełączeniu / zmianie fokusu. Flaga ma ZAWSZE odzwierciedlać
  okno aktualnie oglądane.

## Trudna część: skąd klawiatura wie, KTÓRE to okno

Klawiatura (IME) wysyła do Termuksa skrót "następna sesja" — i ślepy cykl NIE wie, w którą
sesję trafił. Dlatego rekomendacja:

- **Przyciski per-projekt:** każdy przycisk (a) przełącza do konkretnej, nazwanej sesji
  Termuksa danego projektu, i (b) zapisuje cwd tego projektu do flagi. Przycisk zna swój
  cel na sztywno → marker zawsze trafny. To jest najpewniejsza droga.
- Alternatywy (jeśli wolisz jeden klawisz-cykl): musiałbyś niezawodnie ustalić sesję
  docelową — np. nazwane sesje + Termux "go to session by name/index". Mniej pewne.

Mapowanie projekt → sesja Termuksa i to, jak przełączać do konkretnej, jest po Twojej
stronie (znasz Termux session API/skróty). czytaj potrzebuje tylko poprawnego cwd w fladze.

## Strona czytaj (JUŻ ZROBIONE — nie ruszasz)

`_speak.py::_resolve_active_transcript()` czyta tę flagę z priorytetem:
1. flaga `czytaj-active-window.flag` (cwd) → koduje na `~/.claude/projects/<cwd z / na ->/`
   → najnowszy `*.jsonl` → to transkrypt do odczytu;
2. fallback: globalny marker ostatnio-promptowanej sesji;
3. fallback: najnowszy transkrypt gdziekolwiek.
Gdy flagi nie ma — działa po staremu (zero regresji). Zweryfikowane: flaga = cwd Terminatora
→ czytaj celuje w transkrypt Terminatora.

Wyzwalaczem odczytu zostaje na razie klawisz głośności (istniejący `volume_watcher.py`), który
teraz użyje tej flagi do celowania. **Opcjonalnie** klawiatura może też sama wyzwalać odczyt
od razu (zero opóźnienia, bez klawisza głośności) — ale to nadprogram; rdzeń dostawy to flaga.

## Test akceptacyjny

1. Klawiatura: po przełączeniu na okno KFG flaga zawiera `/root/projekty/KFG-Addons`;
   po przełączeniu na Terminator → `/root/projekty/Terminator-Umowy`.
2. Na oknie KFG naciśnij klawisz czytania → czytaj czyta ostatnią wiadomość KFG.
3. Przełącz na Terminator, naciśnij → czytaj czyta ostatnią wiadomość Terminatora.
4. Sprawdź `~/.claude/czytaj.log` linie `ACTION read_back ... transcript=<właściwy>.jsonl`.

## Uwaga o cwd

Flaga musi zawierać cwd w przestrzeni PRoot (`/root/projekty/...`), bo czytaj tam mapuje
katalog projektów Claude Code. Jeśli klawiatura zna tylko nazwę projektu (np. `KFG-Addons`),
czytaj ma fallback dopasowujący katalog kończący się tą nazwą — ale pełny cwd jest pewniejszy.
