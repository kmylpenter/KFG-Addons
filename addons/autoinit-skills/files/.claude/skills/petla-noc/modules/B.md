# Moduł B — TESTY CHARAKTERYZUJĄCE (fundament bramki)

Cel: utrwalić OBECNE zachowanie (wejście X → wyjście Y). Test charakteryzujący
NIE ocenia poprawności — jeśli funkcja ma buga, test utrwala buga (to feature:
wykryjemy ZMIANĘ zachowania, nie "błędność"). Czysta logika JS lokalnie w Node;
SpreadsheetApp/GmailApp/PropertiesService itd. za mockami z harnessu.

## Wykonanie

1. Pierwszy run w projekcie: `cp -r ~/.claude/skills/petla-noc/templates/harness/
   <projekt>/.petla-noc/harness/` (harness.js + mocks.js + example.test.js).
   Harness już jest → NIE nadpisuj (mógł być lokalnie rozszerzony); porównaj
   wersje (`HARNESS_VERSION` w nagłówku) i odnotuj rozjazd w raporcie.
2. Wybór kandydatów z map.json — kolejność opłacalności:
   a. `uses_gas_api == []` (czysta logika: parsowanie, formatowanie, obliczenia),
   b. funkcje z `priority_queue` (będą zmieniane przez E/G/I → bramka ich wymaga),
   c. funkcje czytające arkusze przez proste getValues (łatwe fixtures),
   d. POMIJAJ (na razie): funkcje z UrlFetchApp na żywo, triggery czasowe,
      funkcje >300 linii (raport: "wymaga dekompozycji zanim będzie testowalna").
3. Autor testu = subagent per PLIK (równolegle dla niezależnych plików):
   przeczytaj funkcję + jej zależności z map.json, dobierz 2-4 wejścia
   (typowe + brzegowe Z KODU — np. gałęzie if), USTAL oczekiwane wyjście
   WYŁĄCZNIE przez analizę kodu (nie zgaduj intencji; wątpliwość → mniej
   przypadków + wpis do raportu). Format pliku: patrz example.test.js
   (`module.exports = { file: "Kod.gs", tests: [{name, fixtures, run}] }`).
4. Zapis: `<projekt>/.petla-noc/tests/<nazwa-pliku-zrodlowego>.test.js`
   (jeden test-plik per plik źródłowy — bramka jest per plik).
5. Walidacja: `node harness.js <projekt> --json` → KAŻDY nowy test musi przejść
   (charakteryzuje stan obecny — fail znaczy, że test jest błędny, nie kod!).
   Fail nowego testu → popraw test (max 2 iteracje), nadal fail → usuń ten
   przypadek, wpis do raportu.
6. progress.json per plik źródłowy: `tests: none|partial|green`
   (`green` = plik ma test-plik, wszystkie testy przechodzą i pokrywają funkcje,
   które E/G/I/K chcą zmieniać; `partial` = testy są, ale nie pokrywają celu zmiany).

## Zasady

- Testy NIE zmieniają kodu źródłowego (dozwolone w RED MODE).
- Determinizm: zero `new Date()` bez fixture, zero realnego I/O — wszystko przez
  mocki/fixtures. Niedeterministyczna funkcja → testuj części deterministyczne,
  resztę raportuj.
- Top-level code pliku wykonuje się przy załadowaniu w harness (jak w GAS) —
  globale potrzebne PRZED załadowaniem źródeł wstrzykuj hookiem
  `fixtures.preload(context, state)` (harness woła go przed pętlą ładowania;
  `fixtures.extend` działa dopiero PO załadowaniu).
- OGRANICZENIE vm: top-level `const`/`let` (w tym const-arrow `const f = () =>`)
  NIE są property kontekstu — test sięga do nich przez `g.__eval("f(1,2)")`.
  Preferuj testowanie deklaracji `function`/`var`; const-arrow tylko przez __eval.
- Testy żyją w `.petla-noc/tests/` — POZA gitem (`.git/info/exclude`, patrz
  SKILL.md STAN); nie commituj ich, stan i tak przeżywa noce.
