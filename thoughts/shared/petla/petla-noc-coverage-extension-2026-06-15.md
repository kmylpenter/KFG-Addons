# petla-noc — rozszerzenie: warstwowe ~100% pokrycia + użycie pełnego okna nocy

**Data:** 2026-06-15
**Status:** PLAN (scope zatwierdzony przez Kamila via AUQ: „Logika + smoke")
**Kontekst:** dyskusja o tym, czemu noc kończy się po 30–60 min i czy testy mogą odblokować auto-merge.

---

## Problem (zweryfikowane fakty)

1. **Noc kończy się za wcześnie nie z lenistwa, tylko z konstrukcji.** Warunek końca = przejście rurociągu `F→A→B→C→I→G→D→E→(P)→H→J→K` (SKILL.md:447). Time-boxy w tabeli modułów to **sufity, nie podłogi**. Brak pętli zewnętrznej „rób aż minie okno". Po kilku nocach backlog modułów wyczerpany + audyt konwerguje do minorów → noc 30–60 min.
2. **Net jest oracle'em ślepym na większość apki.** Pokrywa ~185/205 czystych funkcji serwera; **772/1099 funkcji TimeTrackingu to klient `.html` (poza zasięgiem)**; ~20 GAS-ciężkich (tempo/mediany/HR-sync) niepokrytych. Testy chodzą w Node + `vm.createContext` na **mockach**, nie na realnym GAS. Testy charakteryzujące są **zielone-z-konstrukcji** → „green" dowodzi tylko braku regresji scharakteryzowanego zachowania.
3. **Stąd ręczny merge.** Deploy na link nocny **8XA już jest automatyczny** (sekcja DEPLOY NOCNY). Ręczny jest tylko merge do main — bo main płynie do produkcji, a oracle nie widzi 70% apki (klient) ani realnego runtime'u.
4. **Marnowany potencjał.** ~20 przebiegów nocnych × 1h zamiast × 5h. Cap wspólny Opus/Fable pod presją (Fable niedostępny); **Sonnet ma osobny, niewykorzystany cap** (wczorajszy model-per-rola, commit 4aec3bb, już to wykorzystuje dla ról mechanicznych).

---

## Cel — „100%" przełożone uczciwie na 3 warstwy

| Warstwa | Co | Osiągalność | Narzędzie |
|---|---|---|---|
| 1. Logika serwera `.gs` | czyste funkcje + 20 GAS-heavy | ~pełna | unit (Node+mocki, bogatsze fixtury) |
| 2. Logika klienta `.html` | funkcje z realnym rozgałęzieniem | **selektywna** | JSDOM + mock `google.script.run` |
| 2b. Glue klienta | input→serwer→DOM | NIE unit (tautologia) | smoke |
| 3. Integracja/runtime/UI | Sheets, triggery, Zoho, scope'y, UI na tablecie | **NIE unit** | smoke na żywym 8XA |

**KPI = mutation score (testy DYSKRYMINUJĄCE), NIE % linii.**

---

## Guardraile (twarde — bez nich to coverage-theater)

- **G1 — dyskryminacja.** Test liczy się jako pokrycie tylko gdy mutacja kodu (`>`→`<`, zmiana stałej, usunięcie linii, off-by-one) czyni go RED. Zielony-z-konstrukcji bez mutation-proof = NIE liczony, NIE odblokowuje auto-merge. (To zautomatyzowany odpowiednik kontrfaktyka RED-proof z `domknij`/sealed.)
- **G2 — cap/model.** Bulk mechaniczny (scaffolding harnessu, fixtury, uruchamianie testów, mutation-runner, zbieranie metryk) → **Sonnet (osobny cap)**. Osąd (co charakteryzować, czy survived-mutant to realna luka, semantyka klienta) → **Opus w skoncentrowanych porcjach**. Rozszerza INVARIANT 7, nie wywraca.
- **G3 — wszystkie dotychczasowe wymagania nocy obowiązują:** bramka testowa, kwarantanna zamiast kasowania, zero push do main, deploy WYŁĄCZNIE 8XA, pełen unattended, RED-mode globalny.

---

## Zmiany mechanizmu

- **M1 — OUTER LOOP / budżet okna.** Po przejściu F→K: jeśli zostało okno nocy / budżet capu **I** jest kwalifikująca się robota coverage-expansion → wejdź w **FAZĘ POKRYCIA** zamiast kończyć. Koniec nocy = okno wyczerpane **LUB** brak kwalifikującej roboty (już NIE: „pipeline complete").
- **M2 — MUTATION-HARDENING istniejącego netu (~679 testów).** Runner: per plik z testami generuj N mutantów (relop-flip, const-tweak, statement-deletion, boundary), odpal testy pliku, policz killed/survived. Survived = luka → zadanie dla Opusa (wzmocnij test albo odnotuj). Sonnet uruchamia, Opus orzeka wątpliwe. **Najwyższa dźwignia pod auto-merge** — utwardza to, co już mamy.
- **M3 — rozszerzenie modułu B (charakteryzacja):**
  - *B-server:* 20 GAS-heavy — bogatsze mocki (SpreadsheetApp z fixturami danych arkusza, UrlFetchApp dla HR-sync).
  - *B-client:* harness JSDOM + mock `google.script.run`; ekstrakcja funkcji z `<script>` w `.html`; SELEKTYWNIE funkcje z logiką, pomiń glue.
- **M4 — SMOKE jako warstwa 3.** Po DEPLOY NOCNY (8XA) odpal `petla smoke` po żywym linku; kluczowe flow renderują/działają. **WARUNEK:** najpierw zweryfikować runtime puppeteer-core pod PRootem (memory: budowane pod Termuxem, chromium ARM; PRoot niezweryfikowany). Pad → smoke SKIP + raport, reszta nocy leci dalej.
- **M5 — sealing.** Test mutation-proven → oznacz jako `sealed` (jak `domknij` RED-proven). Sealed złamany = regresja (canary F). Łączy się z istniejącym mechanizmem sealed.

---

## Jak odblokowuje auto-merge (cel z poprzedniej rozmowy)

Gate można zwężać DOKŁADNIE tak szybko, jak rośnie pokrycie mutation-proven na ścieżkach krytycznych dla osiągalności. Gdy warstwa 1 jest mutation-proven + warstwa 3 (smoke) zielona na 8XA → klasy zmian czysto-logicznych mogą auto-mergować; kwarantanna martwego kodu zostaje za człowiekiem aż mapa osiągalności obejmie krawędzie klient→serwer (`google.script.run`) i triggery.

---

## Ryzyka / otwarte

- Ekstrakcja `<script>` z `.html` nietrywialna (wiele inline-scriptów, zależności DOM/global). Część funkcji może być nie do sensownej izolacji → wtedy smoke, nie unit.
- Mutation-runner na mockach: czas (N mutantów × testy) — wymaga time-boxa.
- ~~Smoke pod PRootem niezweryfikowany~~ → ZWERYFIKOWANE 2026-06-15: DZIAŁA (self-test 5/5, chromium 148 headless od strony PRoota). Warstwa 3 LIVE.
- Nawet Sonnet-heavy: osąd Opusa rośnie z liczbą survived-mutantów → time-box fazy pokrycia.

---

## Sekwencja budowy (cap-aware)

- **Foreground (bounded, wymaga osądu + sterowania usera):** MECHANIZM — SKILL.md outer-loop + end-condition + tabela modułów + przypisania modelu; template'y M2 (mutation-runner) i B-client (JSDOM harness); mirror `cp -r` + `diff -r`.
- **Night (unattended, Sonnet-heavy):** TREŚĆ — mutation-harden ~679, 20 GAS-heavy, logika klienta, smoke. To jest właśnie ta robota, która ma zapełnić okno nocy.

---

## STATUS WDROŻENIA (2026-06-15) — MECHANIZM GOTOWY

WDROŻONE (installed = SoT, mirror addonu `diff -r` IDENTICAL, empirycznie zweryfikowane):
- **M2 mutation-runner:** `mutate.js` + hook `PETLA_MUTATE` (harness 1.1, real plik nietknięty) +
  capability-guard (odmawia exit 2 na harness <1.1 zamiast cichego score 0). Self-test 0.667,
  killed 2/survived 1 (boundary `10→11`); guard RED-proven kontrfaktykiem.
- **M1 FAZA POKRYCIA:** SKILL.md (sekcja + moduł M + end-condition + flagi/config + `night_start_epoch`)
  + `modules/M.md` (loop-until-dry, budżet okna, model-per-rola, upgrade harnessu).
- **M3:** B-server (`B.md`) + B-client DOM-shim (`client-harness.js`+`client-mocks.js`, F1c, `tests-client/`).
  Self-test klienta 3/3.
- **M4 SMOKE (D5):** reuse browser-smoke. **KOREKTA: smoke DZIAŁA pod PRootem** (self-test 5/5,
  chromium 148) — wcześniejsze „niezweryfikowane" błędne. Warstwa 3 LIVE.
- **M5:** schema `files[*].mutation`, def `proven`, BRAMKA→rekomendacja AUTO-MERGE TIER (noc NIE
  pushuje do main — rekomenduje), raport POKRYCIE+TIER.
- **Koherencja:** audytssot BEZ ZMIAN; petla solve `tests`→`tautological-test`; domknij INV 3b mutation-prove.

Repo KFG-Addons (`main`) ma niezacommitowany mirror — do scommitowania na osobnej gałęzi (nie ruszam
main bez zgody). Skille INSTALOWANE już LIVE.
