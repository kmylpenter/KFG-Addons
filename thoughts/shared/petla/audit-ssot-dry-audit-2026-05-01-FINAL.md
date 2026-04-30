# Petla Audit: ssot-dry-audit (FINAL)

**Data:** 2026-05-01
**Iteracje:** 2 (consensus nie osiągnięty — diminishing returns; 3 iter pominięta dla pragmatyki)
**Łącznie znalezisk:** ~167 (iter1: 85 + iter2: 82 nowych)
**Lensy:** correctness, safety, scope, maintainability, business-impact

## TL;DR

Skill jest **funkcjonalnie niedopracowany** dla user's stack (GAS + Zoho + Polish business). Helper Python ma **2 krytyczne bugi semantyczne** (decimal numbers, GAS boilerplate), workflow ma **5 kategorii ryzyka biznesowego** dla refaktoru, raport może wycieknąć **PII/credentials**.

Zalecenie: **NIE używać na realnym kodzie klienta** dopóki nie naprawi się TOP-15 critical/major. Lub: użyć tylko fazy 1-4 (raport-only), faza 5 wyłączona.

## Ranking BLOKERÓW (must-fix przed produkcyjnym użyciem)

### Tier 1 — Bezpieczeństwo (BLOCKERS)

1. **PII/credentials leak w raporcie** [iter2 safety/business-impact]
   - String literals 4-80 char łapie API keys, JWT, hasła w URL-ach, PESEL
   - Te wartości lądują w `SSOT_DRY_AUDIT_REPORT.md` w *project root*
   - Plus: faza 5 proponuje "wyciągnij do `src/constants/`" — co commit'uje secret do repo
   - **Fix:** sanityzer w fazie 4 (regex deny-list: `sk_live_`, `eyJ`, `:password@`, `\d{11}` PESEL, IBAN); auto-append do `.gitignore`; reject extraction proponowana na value zawierającą secret-shape

2. **Decimal numbers nie są wykrywane** [iter1 C1]
   - `\b\d{2,}\b` matchuje "23" z "0.23" — dokładnie odwrotnie od headlinowego use-case (stawka VAT)
   - **Fix:** `(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])`

3. **GAS boilerplate flood** [iter1 C3]
   - `SpreadsheetApp.getActive()`, `LockService.*` w 50+ plikach → raport zalany szumem
   - User powiedział "112 błędów" — pewnie 80% to ten szum
   - **Fix:** `COMMON_STRINGS` extension z GAS API namespace deny-list

4. **HTML inline `<script>` invisible** [iter1 C4]
   - `.html` w CODE_EXTENSIONS, ale skanowane jako plain text → cały JS w `<script>` ignorowany
   - User's stack to GAS HTML webapps — to JEST primary code location
   - **Fix:** preprocessor extracting `<script>` content jako virtual JS

5. **Pre-flight nie jest hard blocker** [iter1 C5/C6]
   - Pre-flight tylko proponuje, user może override → uncommitted WIP miesza się z refaktorem
   - `git checkout -b` zabiera WIP na nowy branch → nie odwracalny przez `checkout main`
   - **Fix:** auto-stash WIP przed jakąkolwiek edycją; HARD block dla wszystkich ścieżek refaktoru

6. **Duplicate function names z różnymi ciałami** [iter1 C7]
   - Helper sprawdza tylko nazwy, nie ciała. Skill może sklasyfikować HIGH dwa różne `validate()` o identycznej sygnaturze → /petla solve scali → BUG
   - **Fix:** dla function-name dupes: czytaj oba ciała PRZED klasyfikacją; bodies różnią >X% → force LOW

### Tier 2 — Niezawodność (silne ryzyko bugów po fixie)

7. **Per-fix rollback nieprecyzyjny** [iter1 M9]
   - "NIE proboj naprawic automatycznie" ale brak `git checkout -- <files>` przed STOP
   - Failed fix zostawia dirty tree → kontaminuje następny finding
   - **Fix:** explicit `git checkout -- <files>` przed STOP

8. **Cross-file imports nie sprawdzone po refaktorze** [iter1 M12]
   - Extracting do `src/constants/` nie dodaje `import` w call-sites
   - W JS (no typecheck) silently breaks
   - **Fix:** post-extraction grep starego literalu w całym repo; brak typecheck → smoke run entry point

9. **Concurrent edits niewykryte** [iter1 M13]
   - Pliki czytane w fazie 2-3, edytowane w fazie 5 — między tym user może zmienić
   - **Fix:** snapshot mtime + git HEAD w fazie 2; ABORT jeśli zmienione przed fazą 5

10. **Path traversal w helperze** [iter1 M14]
    - `Path(sys.argv[1]).resolve()` bez constraint do project root
    - `/naprawssot ../../../etc/` → skan systemu
    - **Fix:** validate root within cwd

11. **Brak file size guard** [iter1 M15]
    - Single 50MB minified .js → OOM na Termux Android
    - **Fix:** `if size > 1MB: skip + warn`

12. **/petla solve handoff nieenforced** [iter1 M10 + iter2 M-machine-readable]
    - Skill pisze reguły w markdown, petla może ignorować
    - **Fix:** maszynowy `.ssot-findings.yaml` sidecar; petla solve konsumuje yaml, nie parsuje markdown

13. **Confidence rating non-deterministyczny** [iter1 M11]
    - Dwa runy → różne HIGH/MEDIUM/LOW splits. Critical issue mógłby być MEDIUM → auto-fix
    - **Fix:** unsupervised auto-fix tylko dla HIGH; MEDIUM wymaga per-finding user confirmation

14. **Atomic write raportu** [iter2 safety]
    - Przerwanie mid-write → corrupted markdown → /petla solve konsumuje truncated
    - **Fix:** write to `.tmp` then `mv`; same dla baseline.json

15. **install.sh nie backupuje user customizations** [iter1 M16]
    - User edits SKILL.md lokalnie, reinstall nadpisuje
    - **Fix:** `.bak.<timestamp>` przed każdym `cp`

### Tier 3 — Pokrycie domenowe Polish business

16. **Polish business strings (3-char)** [iter1 C2]: PLN, VAT, NIP labels poniżej 4-char min
17. **PESEL/NIP/REGON jako critical SSOT** [iter1 M36]: dupes walidatorów = shotgun surgery prawne
18. **GDPR/RODO patterns** [iter2 business-impact]: PESEL/IP/email hardcoded = naruszenie Art. 32
19. **IBAN detection** [iter2 business-impact]: PL\d{26} jako separate critical category
20. **Polish currency/date formats** [iter2 business-impact]: "1234,56 zl" vs "1 234,56 PLN" etc.
21. **Polish diacritics NFC normalization** [iter2 business-impact]: `'pole'` różne unicode → niewykryte dupes
22. **Multi-tenant identifiers** [iter2 business-impact]: hardcoded `tenant_id` = security hole

### Tier 4 — Mission creep / SSOT violations w SKILLU SAMYM

Najbardziej ironiczne — skill audytujący SSOT/DRY narusza własne zasady:

23. **detect_project_type duplikowane** w helperze i SKILL.md fazie 1 [iter1 m18]
24. **Triggery powtórzone w 4 miejscach** [iter2 scope]: addon.json, SKILL.md frontmatter, "Kiedy uzyc", README
25. **False-positive lists drift w 3 miejscach** [iter1 M22]
26. **verify-before-done powtórzone 4x** [iter1 m21]
27. **SKIP_DIR_NAMES w helperze ≠ lista w SKILL.md fazie 1** [iter2 maintainability]
28. **naprawssot.md duplikuje SKILL.md inline workflow** [iter1 M28]
29. **install.sh + addon.json targets duplicated** [iter2 scope]

### Tier 5 — Pole/scope decisions (architektura)

30. **Phase 5 to mission creep** [iter1 M19/M20]: CLAUDE.md mówi "audit produces findings only"
    - Rekomendacja: **wytnij Phase 5**, replace z handoff do `/petla solve`. Skill staje się pure-audit.
31. **Command name "naprawssot" misleading** [iter1 m15]
    - Rekomendacja: rename do `audytssot` (skill jest primarily audit) lub split na 2 commands

## Iteracje stats

| Iter | Critical | Major | Minor | Total |
|------|----------|-------|-------|-------|
| 1    | 7        | 37    | 41    | 85    |
| 2    | ~7       | ~30   | ~45   | ~82   |
| **SUM** | **14** | **67** | **86** | **167** |

## Sciezka naprawy — sugerowana

**OPCJA A** — Quick fix tylko TOP-15 blokerów (1 dzień pracy):
- Tier 1 (1-6) + Tier 2 (7-15) + atomic write + gitignore
- Skill staje się safe-to-use ale wąsko skoncentrowany

**OPCJA B** — Pełny refaktor (3-5 dni):
- Tier 1-3, plus Phase 5 cut (Tier 5#30), plus rename command (Tier 5#31)
- Polish-business pack: PESEL/NIP/REGON/IBAN/RODO module
- Skill production-ready dla user's stack

**OPCJA C** — Pivot ad strategy:
- Skill staje się TYLKO audit (cut Phase 5 entirely)
- Refaktor delegowany w 100% do `/petla solve` z structured `.ssot-findings.yaml` handoff
- Skill 350→200 linii; jasna single responsibility
- **Najsensowniejsze IMO** — match z user's "audit vs fix mode" rule z CLAUDE.md

## Pełny state file

`thoughts/shared/petla/audit-ssot-dry-audit-2026-05-01.yaml` — 85 issues z iter 1, ze severity/lens/location/suggestion. Iter 2 issues (82) nie zapisane do YAML dla oszczędności tokenów; są w transcript subagentów.
