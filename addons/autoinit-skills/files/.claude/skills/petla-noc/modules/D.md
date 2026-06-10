# Moduł D — AUDYT (reuse /petla audit z lensami GAS)

Cel: pełny audyt critical/major/minor w formacie petli + kategorie specyficzne GAS.
NIE wymyślaj własnego protokołu — WYKONUJESZ tryb audit skilla petla.

## Wykonanie

1. Przeczytaj `~/.claude/skills/petla/SKILL.md` → "Tryb: AUDIT" (workflow, state
   file, konsensus, stop-conditions, TREE GUARD). Stosujesz go 1:1, z różnicami:
   - state/wyniki w `<projekt>/.petla-noc/reports/audit-<projekt>-<data>.yaml`,
   - `--profile standard`, severity_floor minor (noc ma czas; minory i tak
     agregowane wg reguł petli), max_iter wg time-boxu (start: 2),
   - lensy: 5 GAS-owych poniżej (jak custom --lenses).
2. **Lensy GAS** (prompty per petla Subagent Spawn Template; checklisty
   ze wskazaniem shared/gas-rules.md — agent MA przeczytać gas-rules):

| Lens | Checklist (skrót; pełne reguły w gas-rules) |
|---|---|
| gas-batch | getValue/setValue/appendRow w pętlach, flush w pętli, wielokrotny getDataRange (gas-rules 4); skutek: timeout 6 min (gas-rules 5) |
| gas-config | hardkodowane ID arkuszy/maile/URL-e/klucze (gas-rules 9) — per wystąpienie jako issue |
| gas-errors | puste catch, catch-tylko-log, UrlFetchApp/MailApp/SpreadsheetApp/CalendarApp/GmailApp bez try (gas-rules 8) |
| gas-structure | funkcje >200 linii, duplikacja logiki SSOT/DRY (możesz uruchomić helper `python3 ~/.claude/skills/ssot-dry-audit/scripts/detect_duplicates.py <projekt> --allow-outside-cwd --output ...` — ścieżka jest argumentem POZYCYJNYM, a flaga --allow-outside-cwd konieczna, gdy CWD nie jest przodkiem projektu — i skonsumować findings), top-level code z side-effectami |
| gas-deadcode | weryfikacja dead_candidate z map.json: per kandydat sprawdź WSZYSTKIE warunki gas-rules 3 (greps word-boundary po .gs i .html); wynik per kandydat: QUALIFIED / DISQUALIFIED(powód) / DOUBT(powód) |

3. Per projekt audyt = osobny przebieg (fan-out lensów per petla); projekty
   sekwencyjnie albo (małe) równolegle — limit MAX_AGENTS petli obowiązuje.
4. Wynik: audit YAML zgodny ze schematem petli (issues z id/severity/lens/item/
   location/suggestion/found_in_iteration/status) + dodatkowe pole per issue:
   `gas_category: batch|config|errors|structure|deadcode` i dla deadcode:
   `quarantine_check: {refs_gs: 0, refs_html: 0, string_refs: 0, handler: false,
   runtime_30d: unknown|0|N}` — to wejście modułu E.
5. Merge z fresh_debt (moduł F2 dopisuje do tego samego pliku — dedup po
   file:line+item). Criticale → priority_queue w progress.json.
6. Audit YAML żyje w `.petla-noc/reports/` poza gitem (SKILL.md STAN) — bez
   commitu. RAPORT NOCNY: zliczenia per severity per projekt.

## Zasady

- Audyt jest READ-ONLY (TREE GUARD per petla). Wszelkie "przy okazji naprawię" → NIE (to moduł E).
- Time-box przekroczony w trakcie iteracji → dokończ iterację (werdykty muszą
  wrócić), zapisz stan petli, audit kontynuuje następnej nocy (resume per petla).
