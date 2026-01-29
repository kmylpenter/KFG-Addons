---
name: loop
description: Iteracja z konsensusem - praca trwa dopóki N walidatorów nie zgodzi się jednogłośnie. Tryby: create, verify, audit, solve.
version: "1.5"
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion
---

# /loop v1.5 - Iteracja z Konsensusem

---

## 🚨 EXECUTION PROTOCOL (PRZECZYTAJ NAJPIERW!)

Ten skill ma WYMUSZONE kroki. NIE MOŻESZ ich pominąć.

### KROK 0: GATE - Przed jakąkolwiek pracą

**WYKONAJ TERAZ (nie później!):**

1. Przeczytaj audit/source file
2. Policz ile masz elementów do zrobienia (issues, sekcje, etc.)
3. **NATYCHMIAST** wywołaj TaskCreate dla KAŻDEGO elementu:
   - solve: `TaskCreate("Fix C1: opis")` dla każdego issue
   - audit: `TaskCreate("Iteration 1")`, `TaskCreate("Iteration 2")`, ...
   - create: `TaskCreate("Section: Introduction")` dla każdej sekcji
4. Wywołaj `TaskList()` i POTWIERDŹ że taski istnieją

**GATE CHECK:** Czy TaskList pokazuje > 0 tasków?
- TAK → Przejdź do KROK 1
- NIE → STOP. Wróć do punktu 3 i utwórz taski.

### KROK 1: Praca

Dla każdego elementu:
1. `TaskUpdate(taskId, status="in_progress")`
2. Wykonaj pracę (fix/create/verify)
3. `TaskUpdate(taskId, status="completed")`
4. Przejdź do następnego pending

### KROK 2: CHECKPOINT (co 10 tasków)

Po każdych 10 ukończonych taskach:
1. Wywołaj `TaskList()`
2. Wyświetl: "Progress: X/Y completed (Z%)"
3. Kontynuuj automatycznie (NIE PYTAJ usera!)

### KROK 3: GATE - Przed zakończeniem

**ZANIM napiszesz "podsumowanie" lub "summary":**

1. Wywołaj `TaskList()`
2. Sprawdź: czy są jakieś pending taski?

**GATE CHECK:**
- pending > 0 → **NIE MOŻESZ ZAKOŃCZYĆ**. Wróć do KROK 1.
- pending == 0 → Możesz przejść do finalnego summary.

---

## ⛔ AUTONOMY RULES (COMPACTION-RESISTANT)

**Ta sekcja przetrwa kompakcję kontekstu - ZAWSZE jej przestrzegaj.**

| ❌ NIGDY nie pytaj | ✅ ZAMIAST tego |
|-------------------|-----------------|
| "Czy kontynuować?" | Kontynuuj automatycznie |
| "Pozostało X problemów, czy mam dalej?" | Napraw wszystkie problemy |
| "Chcesz żebym kontynuował iteracje?" | Kontynuuj do consensus |
| "Czy mogę przejść do następnego issue?" | Przejdź automatycznie |
| "Minor issues są opcjonalne" | **NIE SĄ** - napraw wszystkie |
| "Skończyłem major, wystarczy" | **NIE** - minor też musisz naprawić |

**ZASADA:** User ZAWSZE może przerwać przez `Ctrl+C`. Brak przerwania = kontynuuj.

**Jeśli nie jesteś pewien czy kontynuować → KONTYNUUJ.**

---

## 📋 MANDATORY TASK TRACKING (REQUIRED - FIRST ACTION)

```
┌─────────────────────────────────────────────────────────────┐
│  🚨 IMMEDIATE ACTION - BEFORE ANYTHING ELSE                 │
│  ─────────────────────────────────────────────────────────  │
│  Po uruchomieniu /loop, NATYCHMIAST TaskCreate dla          │
│  KAŻDEGO elementu pracy. DOPIERO POTEM zacznij iteracje.    │
│                                                             │
│  ❌ ZABRONIONE: Praca bez utworzenia Tasks                  │
│  ❌ ZABRONIONE: "Zrobię Tasks później"                      │
│  ❌ ZABRONIONE: "To tylko 5 issues, nie potrzebuję"         │
│  ❌ ZABRONIONE: ">3 elementów bez Tasks"                    │
│                                                             │
│  ✅ WYMAGANE: TaskCreate → TaskUpdate → praca               │
└─────────────────────────────────────────────────────────────┘
```

**MUSISZ używać Tasks - przetrwają kompakcję kontekstu.**

### Przy starcie skilla (NATYCHMIAST):

```
1. TaskCreate dla KAŻDEGO elementu pracy:
   - audit: TaskCreate dla "Run iteration 1", "Run iteration 2", ...
   - solve: TaskCreate dla KAŻDEGO issue z audit file
   - create: TaskCreate dla każdej sekcji do stworzenia
   - verify: TaskCreate dla każdego wymagania do sprawdzenia

2. Ustaw zależności jeśli potrzebne:
   TaskUpdate(taskId, addBlockedBy: [...])
```

### Podczas pracy (ZAWSZE):

```
TaskUpdate(taskId, status="in_progress")  ← PRZED rozpoczęciem
... wykonaj pracę ...
TaskUpdate(taskId, status="completed")    ← PO zakończeniu
```

### Kontrola postępu (CO KILKA MINUT):

```
TaskList()  → zobacz progress: "12/47 completed"
```

**❌ ZABRONIONE:** Praca bez task list przy >3 elementach.
**✅ WYMAGANE:** Każdy issue/faza/iteracja = osobny Task.

---

## 🔒 CONSENSUS RULE (HARD CONSTRAINT)

**SOLVE MODE NIE MOŻE SIĘ ZAKOŃCZYĆ DOPÓKI:**

```
┌─────────────────────────────────────────────────────────┐
│  ⚠️ ALL ISSUES = CRITICAL + MAJOR + MINOR              │
│  ─────────────────────────────────────────────────────  │
│  Severity wpływa TYLKO na KOLEJNOŚĆ, nie na to czy     │
│  naprawiać. MUSISZ naprawić WSZYSTKIE issues.          │
│                                                         │
│  ❌ BŁĘDNE MYŚLENIE:                                    │
│  "Minor issues są opcjonalne" → NIE!                   │
│  "Skończyłem major, mogę przerwać" → NIE!              │
│  "71 minor to za dużo" → NIE MA ZA DUŻO, NAPRAW!       │
│                                                         │
│  ✅ PRAWIDŁOWE MYŚLENIE:                                │
│  "Mam 71 minor issues → tworzę 71 Tasks → naprawiam"  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  WARUNEK ZAKOŃCZENIA SOLVE:                             │
│                                                         │
│  ALL validators MUST say "no more issues to fix"        │
│  ────────────────────────────────────────────────────   │
│  • Nie skończono 50% issues → KONTYNUUJ                │
│  • Nie skończono 90% issues → KONTYNUUJ                │
│  • Skończono critical+major ALE są minor → KONTYNUUJ   │
│  • Skończono wszystkie ALE nie zweryfikowano → KONTYN. │
│  • Timeout? → ZAPISZ STAN I KONTYNUUJ                  │
│  • Kompakcja? → ODCZYTAJ STAN I KONTYNUUJ              │
│  • Zmęczony? → NIE ISTNIEJE, KONTYNUUJ                 │
│  • "Minor są opcjonalne"? → NIE SĄ, KONTYNUUJ          │
│                                                         │
│  JEDYNY WARUNEK STOPU:                                  │
│  ✅ TaskList shows ALL tasks completed (incl. minor!)   │
│  ✅ AND state file shows ALL issues status=fixed        │
│  ✅ AND final validators confirm "no remaining issues"  │
└─────────────────────────────────────────────────────────┘
```

### Solve Completion Check

Po każdym ustawieniu `TaskUpdate completed`:
```python
pending = [t for t in TaskList() if t.status == "pending"]
if len(pending) > 0:
    # AUTOMATYCZNIE przejdź do następnego
    next_task = pending[0]
    TaskUpdate(next_task.id, status="in_progress")
    # ... wykonaj fix ...
else:
    # Wszystkie tasks done - SPAWN FINAL VALIDATORS
    spawn_final_verification()
```

### Final Verification (wymagane!)

Gdy wszystkie Tasks są completed, MUSISZ:
```
1. Spawn 3 validators z pytaniem:
   "Czy są jeszcze jakieś issues do naprawienia w tym repo?"

2. Jeśli KTÓRYKOLWIEK validator znajdzie coś:
   - TaskCreate dla nowego issue
   - KONTYNUUJ solve

3. TYLKO gdy 3/3 mówią "no remaining issues":
   - Zapisz final state
   - Wyświetl summary
   - ZAKOŃCZ
```

### Auto-Resume po przerwaniu

Jeśli solve został przerwany (timeout, kompakcja, error):
```
1. TaskList - zobacz completed vs pending
2. Read state file: thoughts/shared/loop/solve-*.yaml
3. Znajdź pierwszy issue z status != "fixed"
4. KONTYNUUJ od tego miejsca
5. NIE ZACZYNAJ OD NOWA
```

---

## State Files (YAML)

Każdy tryb tworzy i aktualizuje plik stanu w `thoughts/shared/loop/`:

```
thoughts/shared/loop/
├── audit-<target>-<date>.yaml     # Stan auditu
├── solve-<target>-<date>.yaml     # Stan napraw
├── verify-<target>-<date>.yaml    # Stan weryfikacji
└── create-<target>-<date>.yaml    # Stan tworzenia
```

### Audit State File Schema

```yaml
# thoughts/shared/loop/audit-autoinit-2026-01-26.yaml
meta:
  mode: audit
  target: "."
  started: "2026-01-26T12:00:00"
  updated: "2026-01-26T12:15:00"
  status: in_progress | completed
  iterations: 3
  lenses: [bugs, duplicates, security, performance, style]

issues:
  - id: "C1"
    severity: critical
    lens: bugs
    item: "Missing implement_task skill"
    location: "implement_plan/SKILL.md:191"
    suggestion: "Create skill or remove references"
    found_in_iteration: 1
    status: open | fixed | wontfix

  - id: "M1"
    severity: major
    lens: style
    item: "Version mismatch v4.2 vs v4.4"
    location: "session-init/SKILL.md:7"
    suggestion: "Update header to v4.4"
    found_in_iteration: 1
    status: open

iterations:
  - number: 1
    timestamp: "2026-01-26T12:00:00"
    new_issues_found: 12
    consensus: "0/5 no_issues"

  - number: 2
    timestamp: "2026-01-26T12:10:00"
    new_issues_found: 5
    consensus: "0/3 no_new_issues"

  - number: 3
    timestamp: "2026-01-26T12:15:00"
    new_issues_found: 0
    consensus: "5/5 no_new_issues - DONE"

summary:
  total: 17
  critical: 3
  major: 9
  minor: 5
```

### Solve State File Schema

```yaml
# thoughts/shared/loop/solve-autoinit-2026-01-26.yaml
meta:
  mode: solve
  target: "."
  audit_file: "thoughts/shared/loop/audit-autoinit-2026-01-26.yaml"
  started: "2026-01-26T13:00:00"
  updated: "2026-01-26T13:45:00"
  status: in_progress | completed

fixes:
  - issue_id: "C3"
    issue: "Deprecated _deprecated_auto-init-v2 should be deleted"
    proposal:
      action: delete
      target: ".claude/skills/_deprecated_auto-init-v2/"
      rationale: "Fully superseded by session-init v4.4"
    status: proposed | approved | applied | verified | rejected
    verification:
      iteration: 1
      verdicts:
        correctness: passed
        regression: passed
        tests: skipped  # no tests for this
        style: passed
        completeness: passed
      consensus: "5/5 - VERIFIED"

  - issue_id: "M1"
    issue: "Version mismatch v4.2 vs v4.4"
    proposal:
      action: edit
      target: ".claude/skills/session-init/SKILL.md"
      changes:
        - line: 7
          old: "old content"
          new: "new content"
      rationale: "README says v4.4, content has v4.4 features"
    status: proposed
    verification: null

progress:
  total_issues: 12
  proposed: 2
  approved: 0
  applied: 0
  verified: 0
  rejected: 0
```

---

## Workflow with State Files

### Audit Workflow

```
/loop audit .

1. CREATE state file:
   thoughts/shared/loop/audit-autoinit-2026-01-26.yaml

2. ITERATION 1:
   - Spawn validators
   - Collect issues
   - APPEND to state file: issues[], iterations[]
   - UPDATE: meta.updated, meta.iterations

3. ITERATION N:
   - READ state file (get existing issues to exclude)
   - Spawn validators with "DO NOT REPEAT" list
   - APPEND new issues only
   - UPDATE state file

4. CONSENSUS reached:
   - UPDATE: meta.status = completed
   - UPDATE: summary{}
   - PRINT final report from state file
```

### Solve Workflow

```
/loop solve --issues thoughts/shared/loop/audit-autoinit-2026-01-26.yaml

1. READ audit state file
2. CREATE solve state file:
   thoughts/shared/loop/solve-autoinit-2026-01-26.yaml

3. FOR each issue (prioritized by severity):
   a. PROPOSE fix:
      - Analyze issue
      - Generate proposal (action, target, changes)
      - APPEND to state file: fixes[]
      - UPDATE: proposal.status = proposed

   b. VERIFY fix (spawn validators):
      - Agent reads state file to see proposal
      - Agent checks if fix is correct
      - APPEND verdicts to state file

   c. IF consensus:
      - APPLY fix (edit/delete/create)
      - UPDATE: proposal.status = verified

   d. IF no consensus:
      - READ feedback
      - REFINE proposal
      - RE-VERIFY

4. ALL issues verified:
   - UPDATE: meta.status = completed
   - PRINT summary
```

---

## Agent Protocol with State Files

### Audit Agent Prompt Template

```
[VALIDATOR AGENT - LENS: {lens}]

Target: {target}
State file: {state_file}

EXISTING ISSUES (DO NOT REPEAT):
{read issues from state file}

Your task: Find NEW issues not in the list above.
Focus: {lens_description}

RESPOND IN YAML:
```yaml
LENS: {lens}
STATUS: issues_found | no_new_issues
ITEMS:
  - item: "description"
    severity: critical | major | minor
    location: "file:line"
    suggestion: "how to fix"
```
```

### Solve Agent Prompt Template

```
[VALIDATOR AGENT - LENS: {lens}]

Verifying fix for issue: {issue_id}
State file: {state_file}

PROPOSED FIX:
{read proposal from state file}

CHANGES MADE:
{diff or description of changes}

Your task: Verify this fix.
Focus: {lens} - {lens_description}

RESPOND IN YAML:
```yaml
LENS: {lens}
STATUS: passed | failed
REASON: "explanation"
SUGGESTIONS: ["if failed, what to improve"]
```
```

---

## Architektura

```
┌─────────────────────────────────────────────────────────────┐
│  WORK PHASE: Main context wykonuje pracę                    │
└─────────────────────┬───────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  VERIFY PHASE: N agentów równolegle sprawdza                │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────┐  │
│  │ Agent 1 │ │ Agent 2 │ │ Agent 3 │ │ Agent 4 │ │ Agent5│  │
│  │ (lens1) │ │ (lens2) │ │ (lens3) │ │ (lens4) │ │(lens5)│  │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └───┬───┘  │
│       ▼           ▼           ▼           ▼          ▼      │
│    verdict     verdict     verdict     verdict    verdict   │
└─────────────────────┬───────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  CONSENSUS CHECK                                            │
│  ALL "completed"? ──YES──► DONE ✓                           │
│         │                                                   │
│        NO                                                   │
│         ▼                                                   │
│  Aggregate missing items → powrót do WORK PHASE             │
└─────────────────────────────────────────────────────────────┘
```

---

## Użycie

```
/loop <mode> <target> [options]

Modes:
  create   - Twórz plik, weryfikuj kompletność
  verify   - Sprawdź zgodność z wzorcem/planem
  audit    - Szukaj problemów w kodzie
  solve    - Napraw problemy z listy

Options:
  --agents N       - Liczba walidatorów (default: 5)
  --max-iter N     - Max iteracji (default: 10)
  --lenses "..."   - Custom lenses dla agentów
```

---

## TRYB: create

**Cel:** Stwórz kompletny plik poprzez iteracyjne ulepszanie.

**Przykład:**
```
/loop create docs/API.md --source src/api/
```

### Flow

```
ITERATION 1:
├── WORK: Main tworzy pierwszą wersję dokumentacji
├── VERIFY: 5 agentów sprawdza (różne lenses)
│   ├── Agent 1 (completeness): "Brakuje sekcji Authentication"
│   ├── Agent 2 (accuracy): "Endpoint /users ma błędny typ response"
│   ├── Agent 3 (examples): "Brak przykładów dla POST endpoints"
│   ├── Agent 4 (consistency): "completed ✓"
│   └── Agent 5 (clarity): "Sekcja Errors niejasna"
├── CONSENSUS: 1/5 completed → CONTINUE
└── AGGREGATE: [Authentication, response type, examples, clarity]

ITERATION 2:
├── WORK: Main naprawia 4 problemy
├── VERIFY: 5 agentów ponownie sprawdza
│   ├── Agent 1: "completed ✓"
│   ├── Agent 2: "completed ✓"
│   ├── Agent 3: "completed ✓"
│   ├── Agent 4: "completed ✓"
│   └── Agent 5: "completed ✓"
├── CONSENSUS: 5/5 completed → DONE ✓
```

### Lenses dla create (default)

| Lens | Agent sprawdza |
|------|----------------|
| completeness | Czy wszystkie sekcje są obecne? |
| accuracy | Czy informacje są poprawne vs kod? |
| examples | Czy są przykłady użycia? |
| consistency | Czy format jest spójny? |
| clarity | Czy jest zrozumiałe? |

### Implementacja create

```
1. PRZYGOTOWANIE
   - Przeczytaj source files
   - Określ scope dokumentu
   - Stwórz pierwszą wersję

2. LOOP
   iteration = 0
   WHILE iteration < max_iter:

     # VERIFY PHASE - spawn N agents IN PARALLEL (jedna wiadomość!)
     Task({
       subagent_type: "general-purpose",
       prompt: "[LENS: completeness] Sprawdź czy dokument {target} jest kompletny względem {source}.
                Odpowiedz TYLKO w formacie:
                STATUS: completed | incomplete
                MISSING: [lista brakujących elementów lub 'none']"
     })
     # ... pozostałe 4 agenty w TEJ SAMEJ wiadomości

     # AGGREGATE
     verdicts = collect_all_responses()

     # CONSENSUS CHECK
     IF all(v.status == "completed" for v in verdicts):
       RETURN "DONE after {iteration} iterations"

     # WORK PHASE
     missing_items = flatten([v.missing for v in verdicts])
     deduplicated = unique(missing_items)

     FOR item IN deduplicated:
       # Main naprawia każdy brak
       fix(target, item)

     iteration += 1

   RETURN "MAX_ITERATIONS reached - review manually"
```

---

## TRYB: verify

**Cel:** Sprawdź czy coś jest zgodne z wzorcem/planem.

**Przykład:**
```
/loop verify src/ --against thoughts/shared/plans/auth-plan.md
```

### Flow

```
ITERATION 1:
├── VERIFY: 5 agentów sprawdza zgodność implementacji z planem
│   ├── Agent 1 (structure): "Brakuje pliku src/middleware/auth.ts"
│   ├── Agent 2 (api): "Endpoint /login nie zwraca refresh token"
│   ├── Agent 3 (tests): "Brak testów dla password reset"
│   ├── Agent 4 (types): "completed ✓"
│   └── Agent 5 (security): "Brak rate limiting na /login"
├── CONSENSUS: 1/5 → CONTINUE
└── OUTPUT: Lista niezgodności
```

**UWAGA:** W trybie verify Main NIE naprawia - tylko raportuje.
Użyj `solve` jeśli chcesz też naprawiać.

### Lenses dla verify (default)

| Lens | Agent sprawdza |
|------|----------------|
| structure | Czy pliki/foldery są zgodne z planem? |
| api | Czy endpointy/interfejsy są zgodne? |
| tests | Czy testy pokrywają wymagania? |
| types | Czy typy są zgodne ze specyfikacją? |
| security | Czy wymagania bezpieczeństwa spełnione? |

---

## TRYB: audit

**Cel:** Znajdź wszystkie problemy w kodzie.

**Przykład:**
```
/loop audit src/ --lenses "bugs,duplicates,security,performance,style"
```

### Initialization

```bash
# 1. Create directory
mkdir -p thoughts/shared/loop

# 2. Generate state file name
STATE_FILE="thoughts/shared/loop/audit-$(basename $TARGET)-$(date +%Y-%m-%d).yaml"

# 3. Initialize state file
cat > $STATE_FILE << 'EOF'
meta:
  mode: audit
  target: "."
  started: "2026-01-26T12:00:00"
  updated: "2026-01-26T12:00:00"
  status: in_progress
  iterations: 0
  lenses: [bugs, duplicates, security, performance, style]

issues: []

iterations: []

summary:
  total: 0
  critical: 0
  major: 0
  minor: 0
EOF
```

### Flow

```
ITERATION 1:
├── AUDIT: 5 agentów szuka problemów (równolegle)
│   ├── Agent 1 (bugs): "Znalazłem: null pointer w user.ts:42"
│   ├── Agent 2 (duplicates): "Znalazłem: funkcja formatDate zduplikowana w 3 plikach"
│   ├── Agent 3 (security): "Znalazłem: SQL injection w query.ts:15"
│   ├── Agent 4 (performance): "no issues found"
│   └── Agent 5 (style): "Znalazłem: inconsistent naming w api/"
├── AGGREGATE: Lista wszystkich znalezionych problemów
└── OUTPUT: audit-report.md

ITERATION 2:
├── AUDIT: Agenci szukają NOWYCH problemów (nie powtarzają starych)
│   ├── Agent 1: "no new issues"
│   ├── Agent 2: "Znalazłem: jeszcze jedna duplikacja validateEmail"
│   ├── Agent 3: "no new issues"
│   ├── Agent 4: "no new issues"
│   └── Agent 5: "no new issues"
├── CONSENSUS: 4/5 "no new issues" ale 1 znalazł coś → CONTINUE

ITERATION 3:
├── AUDIT: Wszyscy szukają dalej
│   └── ALL: "no new issues"
├── CONSENSUS: 5/5 → DONE ✓
└── OUTPUT: Kompletna lista problemów w audit-report.md
```

### Lenses dla audit (default)

| Lens | Agent szuka |
|------|-------------|
| bugs | Potencjalne błędy, null pointers, edge cases |
| duplicates | Zduplikowany kod, podobne funkcje |
| security | Luki bezpieczeństwa, injection, XSS |
| performance | N+1 queries, memory leaks, slow operations |
| style | Niespójności, naming, conventions |

### Output format

```markdown
# Audit Report

Generated: 2026-01-26
Iterations: 3
Target: src/

## Summary
- Total issues: 12
- Critical: 2
- Major: 4
- Minor: 6

## Issues by Category

### Bugs (3)
1. **[CRITICAL]** Null pointer in `user.ts:42`
   - Line: `const name = user.profile.name`
   - Risk: Crash if user.profile is undefined

### Duplicates (2)
1. `formatDate` duplicated in:
   - `utils/date.ts:15`
   - `helpers/format.ts:23`
   - `components/DatePicker.tsx:8`

### Security (2)
1. **[CRITICAL]** SQL injection in `query.ts:15`
...
```

---

## TRYB: solve

**Cel:** Napraw problemy z listy (np. z audit).

**Przykład:**
```
/loop solve --issues thoughts/shared/loop/audit-autoinit-2026-01-26.yaml
```

### Initialization

```bash
# 1. Read audit file to get issues
AUDIT_FILE=$1  # e.g., thoughts/shared/loop/audit-autoinit-2026-01-26.yaml

# 2. Generate solve state file name
SOLVE_FILE="thoughts/shared/loop/solve-$(basename $TARGET)-$(date +%Y-%m-%d).yaml"

# 3. Initialize solve state file
cat > $SOLVE_FILE << 'EOF'
meta:
  mode: solve
  target: "."
  audit_file: "thoughts/shared/loop/audit-autoinit-2026-01-26.yaml"
  started: "2026-01-26T13:00:00"
  updated: "2026-01-26T13:00:00"
  status: in_progress

fixes: []

progress:
  total_issues: 0
  proposed: 0
  approved: 0
  applied: 0
  verified: 0
  rejected: 0
EOF
```

### Solve Proposal Schema

Każdy fix MUSI mieć pełną propozycję ZANIM zostanie zastosowany:

```yaml
fixes:
  - issue_id: "C3"
    issue: "Deprecated folder should be deleted"
    proposal:
      action: delete | edit | create | move
      target: "path/to/file"
      changes:  # tylko dla action: edit
        - line: 7
          old: "old content"
          new: "new content"
      rationale: "Why this fix is correct"
    status: proposed | approved | applied | verified | rejected
```

### Flow

```
INPUT: audit-report.md z 12 problemami

ITERATION 1:
├── WORK: Main naprawia problem #1 (SQL injection)
├── VERIFY: Agenci sprawdzają fix
│   ├── Agent 1 (correctness): "Fix poprawny ✓"
│   ├── Agent 2 (regression): "Nie wprowadza nowych bugów ✓"
│   ├── Agent 3 (tests): "Brakuje testu dla tego fixa"
│   ├── Agent 4 (style): "completed ✓"
│   └── Agent 5 (completeness): "completed ✓"
├── CONSENSUS: 4/5 → dodaj test
└── WORK: Main dodaje brakujący test

ITERATION 2:
├── VERIFY: Ponowna weryfikacja
│   └── ALL: "completed ✓"
├── CONSENSUS: 5/5 → Problem #1 FIXED ✓
└── NEXT: Problem #2...

[...powtórz dla wszystkich 12 problemów...]

DONE: 12/12 problemów naprawionych i zweryfikowanych
```

### Lenses dla solve (default)

| Lens | Agent weryfikuje |
|------|------------------|
| correctness | Czy fix rozwiązuje problem? |
| regression | Czy nie wprowadza nowych bugów? |
| tests | Czy jest test dla fixa? |
| style | Czy fix jest zgodny ze stylem kodu? |
| completeness | Czy fix jest kompletny? |

---

## Konfiguracja

### Custom lenses

```
/loop audit src/ --lenses "memory,threads,api-contracts,error-handling"
```

Każda lens staje się osobnym agentem sprawdzającym ten aspekt.

### Agents count

```
/loop create docs/API.md --agents 3  # szybciej, mniej thorough
/loop audit src/ --agents 7          # wolniej, bardziej thorough
```

### Max iterations

```
/loop create docs/ --max-iter 5      # safety limit
```

---

## Protokół agenta walidatora

Każdy agent MUSI odpowiedzieć w formacie:

```yaml
LENS: <nazwa>
STATUS: completed | incomplete | issues_found | no_issues
ITEMS:
  - item: "Opis problemu/braku"
    severity: critical | major | minor
    location: "plik:linia" (opcjonalne)
    suggestion: "Sugestia naprawy" (opcjonalne)
```

### Przykład odpowiedzi agenta

```yaml
LENS: security
STATUS: issues_found
ITEMS:
  - item: "SQL injection vulnerability"
    severity: critical
    location: "src/db/query.ts:15"
    suggestion: "Use parameterized queries instead of string concatenation"
  - item: "Missing input validation"
    severity: major
    location: "src/api/users.ts:42"
    suggestion: "Add zod schema validation"
```

---

## Implementacja główna

> **Note:** Poniższy pseudokod opisuje LOGIKĘ działania skilla.
> Claude wykonuje te kroki używając narzędzi (Read, Write, Task, etc.),
> nie uruchamiając dosłownie tego kodu.

### Krok 1: Parse argumenty

```python
mode = args[0]       # create | verify | audit | solve
target = args[1]     # ścieżka lub plik
options = parse_options(args[2:])

# Initialize mode-specific variables
max_iter = options.get('max_iter', 10)
state_file = f"thoughts/shared/loop/{mode}-{basename(target)}-{date()}.yaml"

# For solve mode: load issues from audit file
if mode == "solve":
    issues_list = load_yaml(options.issues)['issues']

# For create mode: get source files
if mode == "create":
    source = options.get('source', target)
```

### Krok 2: Setup lenses

```python
DEFAULT_LENSES = {
  "create": ["completeness", "accuracy", "examples", "consistency", "clarity"],
  "verify": ["structure", "api", "tests", "types", "security"],
  "audit": ["bugs", "duplicates", "security", "performance", "style"],
  "solve": ["correctness", "regression", "tests", "style", "completeness"]
}

lenses = options.lenses or DEFAULT_LENSES[mode]
agents_count = options.agents or len(lenses)
```

### Krok 3: Main loop

```python
iteration = 0
all_issues = []  # dla audit
fixed_issues = []  # dla solve

while iteration < max_iter:

    # === WORK PHASE (tylko dla create i solve) ===
    if mode == "create" and iteration == 0:
        create_initial_version(target, source)
    elif mode == "create" and iteration > 0:
        fix_missing_items(target, aggregated_missing)
    elif mode == "solve":
        fix_next_issue(issues_list, fixed_issues)

    # === VERIFY PHASE ===
    # CRITICAL: Spawn ALL agents in ONE message for parallel execution!
    verdicts = spawn_validators_parallel(
        lenses=lenses,
        target=target,
        mode=mode,
        context=get_context_for_mode(mode)
    )

    # === CONSENSUS CHECK ===
    if check_consensus(verdicts, mode):
        return success(iteration)

    # === AGGREGATE ===
    if mode in ["create", "verify"]:
        aggregated_missing = aggregate_missing(verdicts)
    elif mode == "audit":
        new_issues = aggregate_issues(verdicts)
        all_issues.extend(new_issues)
        if not new_issues:  # no new issues found
            return success_with_report(all_issues)

    iteration += 1

return max_iterations_reached()
```

### Helper Functions (Conceptual)

Te funkcje opisują INTENCJĘ - Claude realizuje je przez narzędzia:

| Function | Claude wykonuje przez |
|----------|----------------------|
| `check_consensus(verdicts)` | Sprawdź czy wszystkie verdicts mają status "completed" lub "no_issues" |
| `aggregate_missing(verdicts)` | Zbierz wszystkie ITEMS z verdicts, deduplikuj |
| `aggregate_issues(verdicts)` | Zbierz issues, zapisz do state file |
| `create_initial_version()` | Write tool - stwórz pierwszą wersję pliku |
| `fix_missing_items()` | Edit tool - napraw braki z poprzedniej iteracji |
| `fix_next_issue()` | Edit/Write/Bash - napraw kolejny issue z listy |
| `get_context_for_mode()` | Read state file + relevant files |
| `success()` / `success_with_report()` | Zapisz final state, wyświetl summary |

### Krok 4: Spawn validators (PARALLEL!)

**KRYTYCZNE:** Wszystkie Task() calls w JEDNEJ wiadomości!

```python
def spawn_validators_parallel(lenses, target, mode, context):
    # Ta funkcja zwraca instrukcję dla Claude aby
    # wysłał wiele Task() w jednej wiadomości

    prompts = []
    for lens in lenses:
        prompts.append(f"""
[VALIDATOR AGENT - LENS: {lens}]

You are validating: {target}
Mode: {mode}
Your focus: {lens}

{get_lens_instructions(lens, mode)}

Context:
{context}

RESPOND ONLY IN THIS FORMAT:
```yaml
LENS: {lens}
STATUS: completed | incomplete | issues_found | no_issues
ITEMS:
  - item: "description"
    severity: critical | major | minor
    location: "file:line"
    suggestion: "how to fix"
```
""")

    return prompts  # Claude spawns all in parallel
```

---

## Przykłady użycia

### Tworzenie dokumentacji

```
User: /loop create docs/README.md --source src/

Claude:
├── [WORK] Tworzę pierwszą wersję README...
├── [VERIFY] Spawning 5 validators...
│   (5 Task() calls in one message)
├── [RESULTS]
│   ├── completeness: incomplete - brakuje sekcji Installation
│   ├── accuracy: completed ✓
│   ├── examples: incomplete - brak przykładów API
│   ├── consistency: completed ✓
│   └── clarity: completed ✓
├── [CONSENSUS] 3/5 - continuing...
├── [WORK] Dodaję Installation i przykłady API...
├── [VERIFY] Re-validating...
│   └── ALL: completed ✓
└── [DONE] README.md complete after 2 iterations
```

### Audyt bezpieczeństwa

```
User: /loop audit src/ --lenses "security,injection,auth,crypto"

Claude:
├── [AUDIT] Spawning 4 security validators...
├── [RESULTS - Iteration 1]
│   ├── security: 3 issues found
│   ├── injection: 1 critical issue
│   ├── auth: 2 issues found
│   └── crypto: no issues
├── [AGGREGATE] 6 unique issues
├── [AUDIT - Iteration 2] Looking for MORE issues...
│   └── ALL: no new issues
└── [DONE] Audit complete. Report: audit-report.md
```

### Weryfikacja implementacji

```
User: /loop verify src/ --against thoughts/shared/plans/feature-plan.md

Claude:
├── [VERIFY] Checking implementation against plan...
├── [RESULTS]
│   ├── structure: 2 missing files
│   ├── api: 1 endpoint not implemented
│   ├── tests: 3 test cases missing
│   ├── types: completed ✓
│   └── security: 1 requirement not met
├── [REPORT] Implementation is 78% complete
│   Missing:
│   - src/middleware/rateLimit.ts
│   - src/utils/encryption.ts
│   - POST /api/v2/refresh endpoint
│   - Tests for auth flow
│   - Rate limiting on /login
```

---

## Safety

### Max iterations
Default: 10. Zapobiega nieskończonym pętlom.

### Timeout per agent
Każdy agent ma 2 minuty na odpowiedź.

### Stuck detection
Jeśli te same issues powtarzają się 3x → przerwij i zapytaj usera.

### Manual override
User może w każdej chwili przerwać: `ctrl+c` lub odpowiedź "stop"

### Path validation
**IMPORTANT:** Target paths from user input should be validated before use:
- Use `basename` to prevent path traversal (e.g., `../../../etc`)
- Validate paths are within project directory
- State files are created in `thoughts/shared/loop/` which is safe

### Delete operations
**CRITICAL:** Delete operations in solve mode (`action: delete`) require:
1. **User confirmation** before executing
2. Clear display of what will be deleted
3. Prefer `move` to archive over `delete` when possible

Example confirmation prompt:
```
"Issue S3 suggests deleting .claude/skills/deprecated/.
 Should I delete this folder? (yes/no)"
```

---

## Integracja z innymi skillami

| Skill | Integracja z /loop |
|-------|-------------------|
| `/session-init` | Po wygenerowaniu planu → `/loop verify` |
| `/implement_plan` | Po implementacji → `/loop verify --against plan` |
| `/build` | Po build → `/loop audit` |
| `/fix` | Debug → `/loop solve --issues` |

---

## Tips

1. **Więcej agentów = wolniej ale dokładniej** - dla krytycznych rzeczy użyj 7-10
2. **Custom lenses** - dostosuj do swojego projektu
3. **Audit → Solve pipeline** - najpierw znajdź, potem napraw
4. **Verify po implement_plan** - upewnij się że wszystko zrobione

---

## 🚀 QUICK START GUIDES

### Quick: Audit a codebase

```
/loop audit src/

1. TaskCreate("Iteration 1"), TaskCreate("Iteration 2"), ...
2. Spawn 5 agents per iteration (bugs, duplicates, security, performance, style)
3. Collect issues into state file
4. Continue until consensus (5/5 "no new issues")
5. Generate audit report
```

### Quick: Fix issues from audit

```
/loop solve --issues thoughts/shared/loop/audit-*.yaml

1. Read audit file → get list of issues
2. TaskCreate for EACH issue (C1, M1, M2, ...)
3. For each issue: propose fix → verify → apply
4. TaskUpdate(completed) after each
5. Final verification: spawn 3 validators to confirm "no remaining issues"
```

### Quick: Create documentation

```
/loop create docs/API.md --source src/api/

1. TaskCreate("Create initial version"), TaskCreate("Refine v2"), ...
2. Create first draft
3. Validators check completeness, accuracy, examples, consistency, clarity
4. Iterate until 5/5 "completed"
```

### Quick: Verify implementation

```
/loop verify src/ --against thoughts/shared/plans/feature.md

1. TaskCreate for each requirement in plan
2. Validators check structure, api, tests, types, security
3. Report gaps (does NOT fix - use solve for that)
```

---

## 🔄 COMPACTION RECOVERY PROTOCOL

**Jeśli sesja została przerwana przez kompakcję kontekstu:**

### Step 1: Identify where you are

```
TaskList()

Output:
#1 [completed] Fix C1: Missing error handling
#2 [completed] Fix C2: SQL injection
#3 [in_progress] Fix M1: Version mismatch     ← YOU ARE HERE
#4 [pending] Fix M2: Duplicate code
...
```

### Step 2: Read state file

```
Read("thoughts/shared/loop/solve-*.yaml")

Look for:
- meta.status: in_progress
- fixes: find one with status=applied but not verified, or status=proposed
- progress: see what's done
```

### Step 3: Continue from current task

```
# Find the in_progress or first pending task
current_task = TaskList().find(status="in_progress")
    OR TaskList().find(status="pending")[0]

# Get full context
TaskGet(current_task.id)

# Continue work
TaskUpdate(current_task.id, status="in_progress")
... do the work ...
TaskUpdate(current_task.id, status="completed")
```

### Step 4: Repeat until done

```
WHILE TaskList() has pending tasks:
    next = first pending task
    do the work
    mark completed
```

**⚠️ CRITICAL:** Po kompakcji NIGDY nie zaczynaj od nowa! Zawsze sprawdź TaskList i state file.

---

## ⚡ PARALLEL AGENT SPAWNING

**KRYTYCZNE:** Aby agenci działali równolegle, WSZYSTKIE Task() calls MUSZĄ być w JEDNEJ wiadomości!

### ❌ WRONG - Sequential (wolne)

```
# Message 1
Task(agent1_prompt)

# Message 2 (after agent1 returns)
Task(agent2_prompt)

# Message 3 (after agent2 returns)
Task(agent3_prompt)
```

### ✅ CORRECT - Parallel (szybkie)

```
# SINGLE MESSAGE with ALL agents spawned together:
Task(subagent_type="general-purpose", description="validator1", prompt="...")
Task(subagent_type="general-purpose", description="validator2", prompt="...")
Task(subagent_type="general-purpose", description="validator3", prompt="...")
Task(subagent_type="general-purpose", description="validator4", prompt="...")
Task(subagent_type="general-purpose", description="validator5", prompt="...")
```

All 5 agents run simultaneously because they're in one message block.

---

## 📊 PROGRESS REPORTING FORMAT

Use consistent format for progress updates:

```
═══════════════════════════════════════════════════════
  /loop solve - Progress Report
═══════════════════════════════════════════════════════
  Mode: solve
  Target: autoinit-skills
  State: thoughts/shared/loop/solve-autoinit-2026-01-28.yaml
───────────────────────────────────────────────────────
  Issues: 17 total
    ✅ Fixed:    12 (71%)
    🔄 Current:   1 (M5: Duplicate validation)
    ⏳ Pending:   4
───────────────────────────────────────────────────────
  By Severity:
    Critical: 3/3 ✅
    Major:    6/9 (67%)
    Minor:    3/5 (60%)
═══════════════════════════════════════════════════════
```

---

## 🎯 SEVERITY-BASED ORDERING

Issues are processed in this order:

```
1. CRITICAL (blocks functionality)
   → Fix FIRST, no exceptions

2. MAJOR (significant problems)
   → Fix SECOND, after all critical

3. MINOR (style, improvements)
   → Fix LAST, but MUST fix all
   → "Minor" does NOT mean "optional"
```

**Remember:** ALL issues must be fixed. Severity only affects ORDER, not WHETHER to fix.
