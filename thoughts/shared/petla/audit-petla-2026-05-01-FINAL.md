# Petla Self-Audit (FINAL)

**Data:** 2026-05-01
**Iteracja:** 1 (skipped iter 2 — root causes wystarczająco jasne, user chciał fix)
**Lensy:** prompt-quality, consensus-logic, iteration-termination, prompt-coverage, state-handoff

## Hipoteza usera (potwierdzona)

> "Po petla audyt, gdyby uruchomić jeszcze raz, są wykrywane kolejne problemy. To by oznaczało że nie robi wystarczająco dużo iteracji, albo nie dochodzi do konsensusu i twierdzi że jest, więc prawdopodobnie błędne prompty dla agentów."

**Empirycznie potwierdzone**: w tej samej sesji `/petla audit` na ssot-dry-audit znalazł 85 issues iter 1, **82 NEW issues iter 2** (zerowy overlap). Dla 4-plikowego skilla — dramatyczne. Implikuje multi-czynnikowy bug.

## ROOT CAUSES (5 critical)

### 1. **TIMEOUT/MALFORMED/EMPTY → "no_issues" bias** ⚠️ smoking gun

Lines 675-690 SKILL.md (przed fix):
- TIMEOUT → "Traktuj jako no_issues z flagą timed_out=true"
- MALFORMED retry once → potem "treat as no_issues"
- EMPTY RETURN → same as timeout

**Skutek:** 2 agentów timeout + 3 mówi no_issues = "5/5 no_issues" → **FALSE CONSENSUS**. Cisza ≠ czysto.

**Fix wgrany:** Three-state semantics — `no_issues | issues_found | INCONCLUSIVE`. Timeout/malformed/empty → INCONCLUSIVE → blokuje konsensus, wymaga re-spawn. Explicit `check_consensus()` algorytm w SKILL.md.

### 2. **`get_lens_instructions(lens, mode)` nigdy nie zdefiniowane**

Line 631 referenced abstrakcyjnie, ale całe SKILL.md nie zawiera implementacji. Agenci dostawali pusty/generic prompt — każdy interpretował "bugs" wg własnego widzimisię. Stąd 80%+ disjoint findings między iteracjami.

**Fix wgrany:** Inline `LENS_INSTRUCTIONS` registry z konkretnymi rubrykami:
- `bugs`: 10 explicit patterns (null deref, off-by-one, race, leaks, cache mismatch...)
- `security`: OWASP-aligned 10 patterns
- `duplicates`, `performance`, `style`: równie konkretne checklisty
- `correctness`, `regression`, `tests`, `completeness` (solve mode): per-step verification
- Custom lens fallback: auto-derive checklist + warning

### 3. **Brak coverage proof**

Validator output schema miał tylko ITEMS. Agent mógł zwrócić `STATUS: no_issues` bez czytania ani jednego pliku — orchestrator nie miał jak zweryfikować.

**Fix wgrany:**
- Required fields: `FILES_EXAMINED` (≥5 lub all-files-in-scope), `PATTERNS_CHECKED` (≥5 z lens checklist z statusem CHECKED+0/CHECKED+N/UNABLE)
- `verify_coverage_proof()` w consensus check → odrzuca "no_issues" bez evidence
- Stop conditions wymagają `coverage_complete()` (95%+ files examined cumulatively)

### 4. **Stuck detection broken**

Line 1101-1110 stara wersja: `set(prev_issues) == set(curr_issues)`. Gdy każda iteracja znajduje INNE issues → stuck_count nigdy nie inkrementuje → loop biegnie do MAX_ITER → silent false-DONE.

**Fix wgrany:** Multi-criteria `evaluate_stop_conditions()`:
- `converged` HIGH: 2× clean iters AND coverage ≥95%
- `max_iter_reached` MEDIUM: hit cap z malejącym slope
- `unbounded` LOW: discovery rate ≥70%/iter — agenci samplują, nie exhaustują → OSTRZEŻENIE
- `stuck` MEDIUM: classic same-issues-3× repeat
- Each level wymusza explicit confidence w final raporcie

### 5. **Exclude-list crowding**

Iter 2+ otrzymywało full text 50+ items. Token budget zjedzony przez exclude list, nie przez analizę kodu. Agent czytał exclude i myślał "wszystko pokryte, no_issues".

**Fix wgrany:**
- `compress_existing_summary()` — agreguje do `<file> [<lens>]: 5C/12M/3m already found` (kategorie + counts, nie full text)
- Cap 50 lines, reszta w state file
- Re-iteration prompt explicit: "Exclude list = output dedup, NOT search-scope limitation. Search ENTIRE target as if iter 1."
- Adversarial self-check section (devil's advocate przed verdict)

## Inne fixy bonusowe

- **Lens table per audit/solve** zachowana ale uzupełniona checklistami w registry
- **Iteration context** w prompcie: "iter 1 = entry points, iter 2 = leaf modules + error paths, iter 3+ = adversarial"
- **Iter number passed do agenta** żeby wiedział której strategii użyć
- **SELF_CHECK_NOTES** required field

## Czego NIE naprawiłem (świadome decyzje)

- **Adaptive MAX_ITER** — udokumentowane w stop conditions, ale nie zaimplementowane (małe ryzyko, można dodać później)
- **Partition mode** (każdy agent dostaje swoją sekcję plików) — wspomniane jako future feature, nie w v3.1
- **Final sweep z DIFFERENT lens rotation** — stop conditions już poprawiają trustworthiness; rotacja byłaby nice-to-have
- **Iteration coverage matrix w state file schema** — można dodać w v3.2

## Pliki

- `~/.claude/skills/petla/SKILL.md` (1538 linii — wzrost z 1341)
- `addons/autoinit-skills/files/.claude/skills/petla/SKILL.md` (synced)
- State: `thoughts/shared/petla/audit-petla-2026-05-01.yaml`
- Ten raport

## Jak teraz weryfikować że bug naprawiony

1. Uruchom `/petla audit` na ssot-dry-audit ponownie. Oczekiwanie:
   - Iter 1 znajdzie ~85-100 issues (jak poprzednio, ale każdy agent ZWERYFIKOWAŁ FILES_EXAMINED ≥5)
   - Iter 2 znajdzie zauważalnie MNIEJ — bo exclude lista jest skompresowana, agenci szukają fresh territory, mają konkretną checklistę
   - Final report wyświetli `converged HIGH` lub `unbounded LOW` — eksplicytna confidence, nie milcząca "done"
2. Jeśli iter 2 nadal znajdzie 80% NEW → coverage proof nie wystarczy, trzeba partition mode (v3.2)
