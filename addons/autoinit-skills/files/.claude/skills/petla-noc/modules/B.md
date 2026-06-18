# Moduł B — TESTY CHARAKTERYZUJĄCE (fundament bramki)

Cel: utrwalić OBECNE zachowanie (wejście X → wyjście Y). Test charakteryzujący
NIE ocenia poprawności — jeśli funkcja ma buga, test utrwala buga (to feature:
wykryjemy ZMIANĘ zachowania, nie "błędność"). Czysta logika JS lokalnie w Node;
SpreadsheetApp/GmailApp/PropertiesService itd. za mockami z harnessu.

## Wykonanie

1. Pierwszy run w projekcie: `cp -r ~/.claude/skills/petla-noc/templates/harness/
   <projekt>/.petla-noc/harness/` (harness.js, mocks.js, mutate.js, client-harness.js,
   client-mocks.js + przykłady). Harness już jest → NIE nadpisuj sam; porównaj
   `HARNESS_VERSION` i odnotuj rozjazd. Faktyczny UPGRADE starszej kopii (żeby dostała
   mutate.js/klienta) robi FAZA POKRYCIA raz na wejściu (SKILL.md „Upgrade harnessu").
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
- Testy żyją w `.petla-noc/tests/` — WERSJONOWANY net (committowany `.petla-noc/.gitignore`,
  patrz SKILL.md STAN; net przenośny między urządzeniami). Noc ich NIE commituje; user
  commituje rano. Stan roboczy i tak przeżywa noce.

---

## POKRYCIE GAS-HEAVY (FAZA POKRYCIA / moduł M2 — funkcje dotąd pomijane)

B pkt 2d POMIJA funkcje z UrlFetchApp na żywo, triggerami czasowymi, >300 linii. FAZA
POKRYCIA wraca do nich (to typowo najcięższa logika: tempo/mediany/HR-sync). Mocki JUŻ
to wspierają — to była POLITYKA B, nie brak narzędzia:
- **UrlFetchApp:** `fixtures.http: [{match: "substring"|/regex/, code, body}]` (mocks.js);
  catch-all `{match:/.*/, code:200, body:""}` przy wielu fetchach. `body` = realna próbka
  odpowiedzi (np. JSON z HR). Asercje na `state.fetches` (co wysłano) + na wyniku funkcji.
- **Triggery czasowe:** testuj CIAŁO handlera z syntetycznym eventem (`g.onTimeTrigger({...})`),
  nie fakt instalacji (ScriptApp mock zapisuje newTrigger w `state.triggers`).
- **Funkcje >300 linii:** charakteryzuj przez wejście/wyjście; zbyt wiele gałęzi → pokryj
  najważniejsze ścieżki + wpis „pełne pokrycie wymaga dekompozycji".
Każdy nowy test → natychmiast mutation-harden (`modules/M.md` M1).

## POKRYCIE KLIENTA (FAZA POKRYCIA / moduł M3 — logika .html)

Klient (`*.html` z inline `<script>`) to typowo ~70% funkcji projektu, dotąd POZA zasięgiem.
Runner: `client-harness.js` + `client-mocks.js` (DOM-shim, NIE jsdom — zależność-free, PRoot-safe).

1. Kandydaci: funkcje z `<script>` mające LOGIKĘ — rozgałęzienia, obliczenia, parsowanie,
   walidację, decyzję „który serwer wołać". POMIŃ czysty glue (odczyt inputu →
   `google.script.run` → zapis DOM bez logiki): charakteryzuje wiring, nie poprawność →
   warstwa SMOKE (DEPLOY NOCNY), NIE unit.
2. Test-plik: `.petla-noc/tests-client/<plik.html>.test.js`, format jak `client-example.test.js`
   (`module.exports = {file:"<plik>.html", tests:[{name, fixtures, run(g,state,assert)}]}`).
   `fixtures.dom` seeduje elementy (`{"#id":{value,text,checked,...}}`); `fixtures.server`
   programuje odpowiedzi `google.script.run.<fn>`; asercje na `state` (serverCalls, alerts,
   styleSets, listeners) i na DOM przez `g.document.getElementById(...)`.
3. Walidacja: `node client-harness.js <projekt> --json` → exit 0 (zielony na obecnym kodzie).
4. Zapis `files[<plik.html>].client_tests = green|partial`. Dyskryminacja RĘCZNA (autor
   dobiera wejście rozróżniające) — automat mutacji klienta = przyszłe rozszerzenie.
5. OGRANICZENIE: DOM-shim pokrywa typowe API (getElementById, value/textContent/innerHTML,
   classList, addEventListener, google.script.run, alert, localStorage). Nieobsłużone API →
   shim RZUCA „[client-mock] X not implemented"; rozszerz przez `fixtures.extend(ctx,state)`
   albo wpis do raportu „klient wymaga rozszerzenia shima: <API>".
