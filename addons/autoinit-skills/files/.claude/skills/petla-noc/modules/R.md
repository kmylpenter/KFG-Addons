# Moduł R — RÓWNOLEGŁE ŹRÓDŁA (dual-source) + DETEKTOR ROZJAZDU

Cel: doprowadzić apkę do stanu, w którym wyłączenie Zoho **nie zmienia funkcjonalności** — przez
parallel-run: apka pisze i czyta z OBU źródeł (Zoho + arkusz), z JEDNĄ globalną flagą wyboru
autorytetu. Noc wiruje to **automatycznie dla wszystkich pól `active` z katalogu Z** — ZERO decyzji
per pole (user świadomie unika babysittingu). Człowiek ma JEDNĄ dźwignię: globalny cutover Zoho→arkusz.

Zależność: konsumuje `zoho-catalog.yaml` (moduł Z) + `map.json` (A) z TEJ nocy — nie czyta kodu od zera.
**Opt-in per projekt** (`dual_source: off` default — jeden przełącznik uzbraja R na projekcie; to NIE
babysitting per pole). Z zostaje always-on (read-only); R uzbrajasz świadomie (zmienia zachowanie).
Model: szukanie write-site'ów (mechaniczne) → sonnet; wiring szwu + shim + edge-case'y → model sesji.
Wzorce: `shared/gas-rules.md` §12 (SSOT — nie powielać). Kod zmieniany → BRAMKA, nigdy w RED (jak E/K).

## Dwie różne flagi (nie myl)
- `dual_source` (config petla-noc) = czy NOC buduje wiring na projekcie. Ustawiasz raz.
- `SOURCE_OF_TRUTH` (ScriptProperties APKI) = dźwignia CUTOVERU; `zoho` (default) | `sheet`.
  Flip na `sheet` = „od teraz tylko Google Sheets" — robi CZŁOWIEK, globalnie, w dzień.

## R0. Warunki wejścia
`dual_source != off`, nie RED, nie degraded, jest katalog Z z tej nocy. Inaczej `modules.R.state=skipped`
+ powód. Projekt bez Zoho (Z0) → R bezprzedmiotowy → skip.

## R1. CO wiruje (automatycznie z katalogu Z — bez decyzji per pole)
Wszystkie pola `status: active`. Kolumnę w store zapewnia Z/D6 (additive). Obsługa per pole AUTOMATYCZNA,
ROZSTRZYGANA PO FIELD-LEVEL `access_kind` z katalogu (rollup Z5: write-back jeśli KTÓRYKOLWIEK locus
pisze do Zoho; NIE po słowniku — fail-safe na stale dict, C2):
- **`access_kind: write-back`** (apka FAKTYCZNIE zapisuje to pole do Zoho) → **dual-write** (zapis do
  Zoho jak dziś + zapis-cień do arkusza w tym samym miejscu) + dual-read.
- **każde inne pole** (read-only / record-dot / FORMULA / NIEZNANY access_kind) → **mirror-only**: apka
  tego pola NIE zapisuje, więc nie ma gdzie dual-write; do arkusza trafia przez MIRROR na szwie
  hydratacji (gdy pole czytane z Zoho — zapisz je też do arkusza) + dual-read. **To jest fail-safe na
  C2**: pole liczone w Zoho (FORMULA) NIGDY nie dostaje dual-write, nawet gdy słownik go nie oznaczył —
  bo nie ma go w zbiorze `write-back`. FORMULA dodatkowo → `dual_source.formula_pending[]` + DECYZJA
  „pełna niezależność wymaga reguły przeliczania w arkuszu" (inaczej po cutoverze zamarznie).

## R2. SZEW, nie rozsiewanie (blast-radius)
Wiruj w JEDNYM punkcie wejścia danych, nie w każdym odczycie:
- **Terminator**: hydratacja cache `deals` (`initializeDealsFromZoho`/webhook `daily_sync`) — tu wepnij
  wybór źródła; miejsc odczytu `d.Pole` NIE ruszamy (czytają cache jak dotąd).
- **TTA**: apka już czyta `DEALS_DATA` (arkusz) — szew to WRITER arkusza; R zapewnia nie-Zoho writer
  (zapis-cień z naszej bazy) + detektor. (Asymetria: TTA bliżej gotowego — patrz SKILL.md MODUŁY.)
- Write-side: dual-write w miejscach `write-back` z katalogu (mniej liczne, też lokalizowalne).

## R3. PARALLEL-RUN = ZACHOWANIE NIETKNIĘTE (zgodność z bramką)
`SOURCE_OF_TRUTH` default `zoho`:
- `zoho` → dual-read zwraca wartość Zoho (jak dziś) → ścieżka AUTORYTATYWNA zachowuje zachowanie →
  bramka zielona LEGALNIE (Zoho autorytatywne, to nie tautologia). Arkusz zapisywany w tle, rozjazdy logowane.
  **UWAGA (M4)**: zapis-cień to NOWY efekt uboczny (`openById`+write) — istniejące testy charakteryzujące
  asertujące dokładny call-set `SpreadsheetApp` lub stan shadow-workbooka MOGĄ się zaczerwienić. R to
  zmiana kodu jak E/G/K: „zielony PRZED i PO" dotyczy CAŁEGO harnessu → seam-edit czerwieni testy →
  rollback + DECYZJE; w testach dotkniętego szwu dodaj fixture shadow-workbooka (mock-tolerant).
- Zapisy-cienie do arkusza: **best-effort, izolowane try/catch (gas-rules §12)** — błąd arkusza
  NIGDY nie psuje ścieżki autorytatywnej. Nieuchylny warunek.
- CUTOVER = flip flagi na `sheet` (jeden ruch, GLOBALNY, człowiek). Po nim autorytet = arkusz,
  Zoho = cień-do-porównania (detektor łapie stragglery aż Zoho zniknie). Akcept obu: fallback gdy
  autorytet pusty.
- **GOTOWOŚĆ DO CUTOVERU (C3)** = rozjazdy ~0 przez N nocy **I** `formula_pending` PUSTE (każde pole
  FORMULA ma już regułę przeliczania w arkuszu). Flip to ręczna, NIEbramkowalna zmiana ScriptProperties
  → więc raport **ESKALUJE niepuste `formula_pending` jako BLOCKER cutoveru**, nie przypis: flip z
  zaległymi formułami = ciche zamrożenie tych pól (stale authoritative).

## R4. DETEKTOR ROZJAZDU → log + raport (+ Telegram gdy projekt ma bota)
Przy odczycie, gdy OBA źródła obecne i różne (po normalizacji typu, gas-rules §12 `__eqNorm`):
- append do `__ROZJAZD_LOG` (wzór „Errors"): pole, dealId, zoho, sheet, autorytet, timestamp, kind.
  **CAP / KILL-SWITCH (M5, nieopcjonalne)**: log FIFO-trimowany (jak `CRM_WEBHOOK_LOG` ~500 wierszy);
  **dedup** po (pole+kind) w obrębie runu; flaga `divergence_log: off` ubija logowanie i digest. TTA
  miał REALNY incydent spamu (`DEALS_DIFF_KILL`, masowa zmiana ~130 deali) — bez capa powtórzymy go.
- dual-write „odpięty" (jedna strona pusta gdy powinna być) → log `kind=unpinned`.
- DIGEST: noc czyta `__ROZJAZD_LOG`, ZAWSZE podbija ZAGREGOWANY (po dedup) licznik do porannego raportu.
  **Telegram (M6) = TYLKO gdy projekt MA bota** — dziś **TTA** (`TELEGRAM_TOKEN` w ScriptProperties).
  **Terminator NIE ma bota → wyłącznie raport.** „reuse wzorca TTA" = skopiuj wzorzec `sendTelegram`
  (per-projekt token, NIE współdzielenie instancji). To sygnał „coś się odpięło / niedopięte".

## R5. BRAMKA + TEST
Kod R za BRAMKĄ. Plik `_dual_source.gs` (generowany; wyjątek plików tworzonych — zielony pełny harness
PO). Wygeneruj test DYSKRYMINUJĄCY shim: ścieżka `SOURCE_OF_TRUTH=zoho` (==dziś), ścieżka `=sheet`,
rozjazd→log, izolacja błędu arkusza (rzuć w zapisie-cieniu → ścieżka autorytatywna nietknięta).
Mutation-harden (moduł M) obejmie shim. Fail bramki → rollback + DECYZJE (jak każda mutacja).

## Wyjścia R
- `_dual_source.gs` (gen., za bramką); flaga `SOURCE_OF_TRUTH` w ScriptProperties (default zoho);
- `__ROZJAZD_LOG` (runtime) + digest Telegram/raport;
- progress `dual_source` (enabled, source_of_truth, fields_wired, formula_pending[], divergences_last_run, telegram_configured);
- raport „PARALLEL-RUN / CUTOVER-READINESS": pola uzbrojone, rozjazdy, pola FORMULA czekające na regułę
  przeliczania, gotowość do GLOBALNEGO cutoveru (rozjazdy ~0 przez N nocy **I** `formula_pending` PUSTE)
  → DECYZJA „flip SOURCE_OF_TRUTH=sheet"; niepuste `formula_pending` → **BLOCKER**, NIE rekomenduj flipa.
