---
name: session-init
description: CCv3 Session Architect - przygotowanie wielogodzinnej sesji autonomicznej z Dual Enhancement (Feature + Validation). Triggers: session-init, session init, plan session, prepare session, init session
version: "4.4"
user-invocable: true
allowed-tools: AskUserQuestion, Read, Write, Edit, Glob, Grep, Task, Bash, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# /session-init - CCv3 Session Architect v4.4

## ⚠️ AUTONOMY RULES (COMPACTION-RESISTANT)

**Ta sekcja przetrwa kompakcję kontekstu - ZAWSZE jej przestrzegaj.**

| ❌ NIGDY nie pytaj | ✅ ZAMIAST tego |
|-------------------|-----------------|
| "Czy kontynuować?" | Kontynuuj automatycznie |
| "Pozostało X, czy mam dalej?" | Kontynuuj do końca |
| "Chcesz żebym kontynuował?" | Kontynuuj bez pytania |
| "Czy mogę przejść do następnej fazy?" | Przejdź automatycznie |

**ZASADA:** User ZAWSZE może przerwać przez `Ctrl+C`. Brak przerwania = kontynuuj.

**Jeśli nie jesteś pewien czy kontynuować → KONTYNUUJ.**

---

## 📋 TASKS INTEGRATION (MANDATORY - FIRST ACTION)

```
┌─────────────────────────────────────────────────────────────┐
│  🚨 IMMEDIATE ACTION - BEFORE ANYTHING ELSE                 │
│  ─────────────────────────────────────────────────────────  │
│  Po uruchomieniu /session-init, NATYCHMIAST TaskCreate      │
│  dla każdej fazy. DOPIERO POTEM zacznij wywiad/analizę.     │
│                                                             │
│  ❌ ZABRONIONE: Praca bez utworzenia Tasks                  │
│  ❌ ZABRONIONE: "Zrobię Tasks później"                      │
│  ❌ ZABRONIONE: "To krótki projekt, nie potrzebuję"         │
│                                                             │
│  ✅ WYMAGANE: TaskCreate → TaskUpdate → praca               │
└─────────────────────────────────────────────────────────────┘
```

**Tasks przetrwają kompakcję kontekstu - bez nich zgubisz postęp.**

### Na starcie session-init (NATYCHMIAST):
```
Na starcie session-init:
1. TaskCreate: "Analyze project type"
2. TaskCreate: "Generate feature spec"
3. TaskCreate: "Create validation checkpoints"
4. TaskCreate: "Write implementation plan"
5. TaskCreate: "Generate handoff document"
```

### Workflow:
```
1. TaskCreate dla każdej fazy
2. TaskUpdate status="in_progress" gdy zaczynasz
3. TaskUpdate status="completed" gdy kończysz
4. TaskList aby zobaczyć co pozostało
```

### Po kompakcji kontekstu:
```
Jeśli nie pamiętasz gdzie byłeś:
1. TaskList - zobacz pending tasks
2. Kontynuuj od pierwszego pending
```

---

## DUAL ENHANCEMENT: Features + Validation + **Opinionated UI Defaults**

Przygotowuje wielogodzinną sesję autonomiczną z:
- **6x więcej features** (rozbudowana specyfikacja)
- **10-15x więcej checkpointów** (rozbudowana walidacja)
- **EXECUTABLE checkpoints** (v4: command + expected + on_failure)
- **Visual smoke tests** (v4: dla frontend/fullstack/canvas)
- **Definition of Done** (v4: explicit criteria per project type)
- **🆕 OPINIONATED UI DEFAULTS** (v4.2: konkretny stack zamiast pytań)
- **🆕 ANTI-CONVERGENCE PATTERNS** (v4.2: jawne zakazy dla AI slop)
- **🆕 AESTHETIC COMMITMENT** (v4.2: wybór kierunku PRZED kodowaniem)

---

## 🆕 CO NOWEGO W v4.2

### Problem v4.0/v4.1:
- Plany 370 linii wykonywane >1h z **mizernym rezultatem wizualnym**
- **DWUKROTNIE** zbudowano aplikacje z nieużywalnym UI
- ALE: prosty `frontenddesign` skill od Anthropic daje świetne wyniki
- **ROOT CAUSE**: session-init mówi "zapytaj usera" → sesja autonomiczna nie może pytać → agent wymyśla → chaos

### ⚠️ KLUCZOWA LEKCJA: OPINIONATED DEFAULTS > PYTANIA

**Dlaczego frontenddesign skill działa lepiej:**

| Aspekt | session-init v4.1 | frontenddesign | Efekt |
|--------|-------------------|----------------|-------|
| Stack | "Zapytaj usera" | "Użyj shadcn/ui + Tailwind" | Spójne komponenty |
| Fonty | "Zależy od projektu" | "NIGDY Inter/Roboto" | Distinctive look |
| Kolory | "User musi podać" | "Dominant + sharp accent" | Profesjonalny UI |
| Layout | "Zależy od wireframe" | "Asymetria, overlap dozwolone" | Interesujący design |

### ⚠️ ZJAWISKO: DISTRIBUTIONAL CONVERGENCE

AI przy samplowaniu wybiera "bezpieczne" opcje które dominują w danych treningowych:
- Inter font (najczęstszy)
- Purple gradients on white (typowy "modern" look)
- Symetryczne layouty (łatwe do generowania)
- Solid backgrounds (najprostsze)

**Efekt = "AI SLOP"** - natychmiast rozpoznawalny jako AI-generated.

**Rozwiązanie v4.2:**
1. **EXPLICIT ANTI-PATTERNS** - jawnie zakazuj "bezpieczne" wzorce
2. **PERMISSION SPACE** - daj AI "pozwolenie" na odważne wybory
3. **OPINIONATED DEFAULTS** - konkretny stack, nie pytania

### Rozwiązanie v4.2:

| Zmiana | Opis |
|--------|------|
| **UI_DEFAULTS** | Wymuszony stack: shadcn/ui + Tailwind + Geist font |
| **ANTI_PATTERNS** | Explicit lista zakazów + alternatywy (INSTEAD structure) |
| **AESTHETIC_COMMITMENT** | Agent MUSI wybrać kierunek estetyczny PRZED kodowaniem |
| **SINGLE UI AUTHORITY** | Jeden agent decyduje o designie (bez committee) |
| **Executable Checkpoints** | Każdy CP ma `command` + `expected` + `on_failure` |
| **Visual Smoke Gates** | Sprawdzają OBECNOŚĆ i BŁĘDY (nie estetykę) |

### Nowe sekcje v4.2:
- `3.4 UI_DEFAULTS` - **🆕** opinionated stack (shadcn/ui, Tailwind, Geist)
- `3.5 ANTI_PATTERNS` - **🆕** explicit visual anti-convergence
- `3.6 AESTHETIC_COMMITMENT` - **🆕** wybór kierunku przed kodowaniem
- `3.2 Definition of Done` - explicit criteria
- `3.3 Design Reference Policy` - skąd brać wartości
- `0.3 gate_visual_*` - visual smoke test gates
- `checkpoint_schema` - executable format

### Sekcje z v4.1 (zachowane):
- Executable Checkpoints, Visual Smoke Gates, Design Reference Policy

---

## ⛔ KRYTYCZNE - PRZECZYTAJ NAJPIERW!

**DO ZADAWANIA PYTAŃ MUSISZ UŻYĆ NARZĘDZIA `AskUserQuestion`!**

```
AskUserQuestion(
  questions: [
    { question: "...", header: "Cel", options: [...], multiSelect: false }
  ]
)
```

- ❌ NIE WOLNO pisać pytań jako zwykły tekst
- ❌ NIE WOLNO wypisywać opcji A) B) C) D) w wiadomości
- ✅ MUSISZ użyć tool AskUserQuestion
- ✅ CZEKAJ na odpowiedź przed kontynuacją

---

## OUTPUT SESSION-INIT

```
/session-init → wywiad → delegacja → generuje:

thoughts/
├── shared/
│   ├── handoffs/
│   │   └── session-YYYY-MM-DD-HHMM.yaml    # CCv3 handoff
│   └── plans/
│       └── session-plan.md                  # Detailed roadmap
├── ledgers/
│   └── CONTINUITY_session.md               # CCv3 ledger

.claude/
└── session-config.yaml                      # Orchestration config (optional)
```

---

## INTEGRATION: implement_plan v2.1

Po wygenerowaniu planu, implementacja odbywa się przez **implement_plan** skill.

### Automatic Mode Selection

implement_plan automatycznie wybiera tryb na podstawie złożoności:

| Tasks | Mode | Opis |
|-------|------|------|
| 1-3 | Direct | Implementacja bezpośrednia |
| 4-9 | Handoffs | Agent chain z rich context |
| 10+ | Tasks | Parallel agents + dependencies |

> Pełna dokumentacja trybów: zobacz `implement_plan` skill.

### Plan → Tasks Conversion

Session-init generates plan with phases. implement_plan converts to Tasks:

```
Phase 1: Setup
  └── P1.1: Install packages       → Task #1 (owner: setup-agent)
  └── P1.2: Configure env          → Task #2 (owner: setup-agent)

Phase 2: Implementation
  └── P2.1: Create model           → Task #3 (blockedBy: #1, #2)
  └── P2.2: Add validation         → Task #4 (blockedBy: #3)
  └── P2.3: Create endpoints       → Task #5 (blockedBy: #3)
```

### Cross-Session Persistence

Plan includes `task_list_id` for persistence:

```yaml
execution:
  tasks_enabled: true
  task_list_id: "session-2025-01-23-2230"
```

Start new session with same task list:
```bash
CLAUDE_CODE_TASK_LIST_ID="session-2025-01-23-2230" claude
```

### Visual Progress (ctrl+t)

```
Tasks (3 done, 1 in progress, 5 pending)

✓ #1 P1.1: Install packages (setup-agent)
✓ #2 P1.2: Configure env (setup-agent)
✓ #3 P2.1: Create model (backend-dev)
■ #4 P2.2: Add validation (backend-dev)
□ #5 P2.3: Create endpoints (backend-dev) ⚠ blocked by #4
```

---

## FAZA 0: ENVIRONMENT VALIDATION (obowiązkowa)

### ⛔ PRZED STARTEM - SPRAWDŹ ŚRODOWISKO

Sesja autonomiczna MUSI zweryfikować środowisko PRZED jakąkolwiek pracą.
**Jeśli validation fails → STOP (nie kontynuuj do Fazy 1).**

---

### 0.1 PREFLIGHT CHECKS

```yaml
preflight:
  # ─── SYSTEM ───
  - check: "Git dostępny"
    command: "git --version"
    expected: "git version"
    on_fail: stop

  - check: "Working directory jest repo"
    command: "git rev-parse --git-dir"
    expected: ".git"
    on_fail: stop

  - check: "Brak uncommitted changes"
    command: "git status --porcelain"
    expected: ""
    on_fail: warn

  # ─── RUNTIME (conditional) ───
  - check: "Node.js dostępny"
    command: "node --version"
    expected: "v"
    on_fail: stop
    condition: "package.json exists"

  - check: "Python dostępny"
    command: "python3 --version"
    expected: "Python 3"
    on_fail: stop
    condition: "pyproject.toml OR requirements.txt exists"

  # ─── DEPENDENCIES ───
  - check: "Dependencies installed"
    command: "test -d node_modules && echo 'OK'"
    expected: "OK"
    on_fail: stop
    fix_command: "npm install"
    condition: "package.json exists"

  # ─── BUILD ───
  - check: "Build passes"
    command: "npm run build 2>&1; echo $?"
    expected: "0"
    on_fail: stop
    condition: "package.json has build script"

  # ─── TESTS BASELINE ───
  - check: "Existing tests pass"
    command: "npm test 2>&1 | tail -5"
    expected: "passing"
    on_fail: stop
    condition: "test script exists"
```

### 0.2 PREFLIGHT EXECUTION

```
╔══════════════════════════════════════════════════════════════╗
║  PHASE 0: ENVIRONMENT VALIDATION                             ║
╠══════════════════════════════════════════════════════════════╣
│  SYSTEM:                                                     │
│    ✅ Git dostępny                                           │
│    ✅ Working directory jest repo                            │
│  RUNTIME:                                                    │
│    ✅ Node.js v20.x                                          │
│  DEPENDENCIES:                                               │
│    ✅ node_modules exists                                    │
│  BUILD:                                                      │
│    ✅ Build passes                                           │
│  TESTS:                                                      │
│    ✅ Existing tests pass                                    │
╠══════════════════════════════════════════════════════════════╣
│  RESULT: ✅ ALL CHECKS PASSED                                │
│  → Proceeding to Phase 1                                     │
╚══════════════════════════════════════════════════════════════╝
```

**Na failure:**
```
╔══════════════════════════════════════════════════════════════╗
│  ❌ PREFLIGHT FAILED                                         │
│  FAILED CHECK: Dependencies installed                        │
│  💡 FIX: npm install                                         │
╠══════════════════════════════════════════════════════════════╣
│  RESULT: ❌ BLOCKED - Cannot proceed                         │
╚══════════════════════════════════════════════════════════════╝
```

---

### 0.3 PHASE GATES

Phase Gates definiują warunki przejścia między fazami.

```yaml
phase_gates:
  gate_0_to_1:
    name: "Environment → Discovery"
    conditions:
      - "All preflight checks passed"
      - "No 'blocks_start' blockers"
    on_fail: stop

  gate_1_to_2:
    name: "Discovery → Interview"
    conditions:
      - "Tech stack identified"
      - "Codebase structure scanned"
    on_fail: retry

  gate_2_to_3:
    name: "Interview → Analysis"
    conditions:
      - "At least 10 interview rounds"
      - "Session constraints captured"
      - "MVP features identified"
      - "User confirmed understanding"
    on_fail: continue_interview

  gate_3_to_4:
    name: "Analysis → Agent Delegation"
    conditions:
      - "Project type determined"
      - "Complexity assessed"
      - "Features categorized"
    on_fail: retry

  gate_4_to_5:
    name: "Delegation → File Generation"
    conditions:
      - "All agents responded"
      - "Features enhanced >= 2x"
      - "Checkpoints >= 5x"
      - "Conflicts resolved"
    on_fail: retry_agents

  gate_5_to_6:
    name: "Files → Validation"
    conditions:
      - "YAML handoff created"
      - "YAML is valid"
    on_fail: fix_files

  gate_6_to_done:
    name: "Validation → Ready"
    conditions:
      - "All validation criteria met"
    on_fail: fix_and_retry

# ═══════════════════════════════════════════════════════════════
# v4.0: VISUAL SMOKE TEST GATES (dla frontend/fullstack/canvas)
# ═══════════════════════════════════════════════════════════════

  gate_visual_phase_2:
    name: "Visual Smoke Test - After Core UI"
    applies_to: [frontend, fullstack, canvas_3d, game]
    after_phase: 2
    conditions:
      # Note: Cleanup orphan dev server after test
      - command: "npm run dev & PID=$!; sleep 5; RESULT=$(curl -s localhost:${DEV_PORT:-5173}); kill $PID 2>/dev/null; echo \"$RESULT\""
        expected:
          contains: "<div"
          not_contains: "Error"
      - command: "npm run dev & PID=$!; sleep 5; RESULT=$(curl -s localhost:${DEV_PORT:-5173} | wc -c); kill $PID 2>/dev/null; echo \"$RESULT\""
        expected:
          min_value: 100  # nie pusty response
    on_fail: halt_and_debug
    message: "⚠️ VISUAL CHECK FAILED: Strona nie renderuje się poprawnie"

  gate_visual_phase_5:
    name: "Visual Smoke Test - After Features"
    applies_to: [frontend, fullstack, canvas_3d, game]
    after_phase: 5
    conditions:
      - command: "npx playwright test tests/smoke.spec.ts"
        expected:
          exit_code: 0
    on_fail: halt_and_debug
    message: "⚠️ SMOKE TEST FAILED: Sprawdź screenshot i console errors"

  gate_visual_final:
    name: "Visual Verification - Before Complete"
    applies_to: [frontend, fullstack, canvas_3d, game]
    after_phase: 10
    conditions:
      - command: "npx playwright test"
        expected:
          exit_code: 0
      - screenshot: "final-state.png"
        verify: "not_blank AND has_content"
    on_fail: halt_and_notify_user
    message: "⚠️ FINAL VISUAL CHECK: Poproś użytkownika o weryfikację"
```

---

## FAZA 1: Rozpoznanie kontekstu

### 1.1 Sprawdź środowisko CCv3:
```
Glob: thoughts/ledgers/*, thoughts/shared/handoffs/*, .claude/settings.json
```

- Czy CCv3 jest skonfigurowany?
- Czy są istniejące handoffy/ledgery?
- Jaki tech stack (package.json, pyproject.toml, go.mod)?

### 1.2 Jeśli istnieją handoffy z dzisiaj:

**Zapytaj użytkownika (AskUserQuestion):**
```
Znalazłem istniejące pliki sesji:
- thoughts/shared/handoffs/session-[data].yaml

Co chcesz zrobić?
```

**Opcje:**
- "Nowa sesja" - nowy plan, archiwizuj stare
- "Kontynuuj istniejącą" - wczytaj i kontynuuj
- "Anuluj"

### 1.3 Quick scan codebase (jeśli dostępny TLDR):
```bash
tldr structure . --depth 2
```

Jeśli TLDR niedostępny - użyj Glob do zmapowania struktury.

---

## FAZA 2: WYWIAD (MINIMUM 10 rund)

### ⚠️ DLACZEGO TAK DUŻO PYTAŃ?

**Session-init Philosophy:** Im więcej szczegółów:
- ✅ Lepszy Feature Enhancement (więcej kontekstu dla agentów)
- ✅ Lepsza Validation Matrix (więcej edge cases)
- ✅ Mniej zgadywania podczas pracy autonomicznej
- ✅ Wyższa jakość końcowego rozwiązania

### ZASADY WYWIADU:
- ✅ Pytaj o CEL BIZNESOWY i EFEKT KOŃCOWY
- ✅ Pytaj o funkcjonalności z perspektywy UŻYTKOWNIKA
- ✅ Pytaj o obawy, ryzyka, blokery
- ✅ Pytaj o priorytety (MVP vs Full)
- ✅ Pytaj o CZAS i BUDŻET sesji (nowe!)
- ✅ DYNAMICZNIE generuj pytania na podstawie odpowiedzi
- ❌ NIE zakładaj - PYTAJ

---

### RUNDA 0: Greenfield vs Brownfield (ZAWSZE PIERWSZE PYTANIE!)

**To pytanie determinuje cały flow wywiadu.**

```
AskUserQuestion(
  questions: [{
    question: "Czy zaczynamy od zera czy rozbudowujemy istniejący projekt?",
    header: "Tryb",
    options: [
      { label: "Greenfield - nowy projekt", description: "Buduję coś zupełnie nowego, nie ma jeszcze kodu" },
      { label: "Brownfield - rozbudowa", description: "Mam już działający projekt, chcę dodać nowe funkcje" }
    ],
    multiSelect: false
  }]
)
```

#### Jeśli GREENFIELD:
→ Kontynuuj standardowy flow (Runda 1+)
→ Pytaj o tech stack, architekturę, wszystko od zera

#### Jeśli BROWNFIELD:

**Krok 1: Sprawdź czy projekt był tworzony przez CCv3**

```
AskUserQuestion(
  questions: [{
    question: "Czy projekt był tworzony/rozbudowywany przez session-init + implement_plan?",
    header: "Historia",
    options: [
      { label: "Tak - pełne CCv3", description: "Mam thoughts/, ledger, handoffy - Claude zna strukturę" },
      { label: "Częściowo CCv3", description: "Używałem niektórych skilli ale nie pełnego flow" },
      { label: "Nie - zewnętrzny projekt", description: "Kod pisany ręcznie lub przez inne narzędzia" }
    ],
    multiSelect: false
  }]
)
```

**Krok 2A: Jeśli "Tak - pełne CCv3":**
```yaml
brownfield_ccv3:
  # Claude wie czego się spodziewać:
  read_existing:
    - "thoughts/shared/plans/*.md"           # Istniejące plany
    - "thoughts/ledgers/CONTINUITY_*.md"     # Stan projektu
    - "thoughts/shared/handoffs/*.yaml"      # Historia handoffów

  context_available:
    - Previous plan structure
    - Feature naming convention
    - Checkpoint format
    - Tech stack decisions
    - Architectural patterns used

  interview_adaptation:
    skip:
      - Tech stack questions (already known)
      - Architecture questions (already decided)
    focus_on:
      - "Jaką NOWĄ funkcjonalność chcesz dodać?"
      - "Gdzie w istniejącej strukturze to pasuje?"
      - "Czy nowa funkcja wymaga zmian w istniejącym kodzie?"
      - "Jakie API/contracts muszą być zachowane?"
```

**Krok 2B: Jeśli "Częściowo CCv3":**
```yaml
brownfield_partial:
  # Częściowy kontekst
  check_for:
    - "thoughts/" directory
    - ".claude/settings.json"
    - Existing patterns

  interview_adaptation:
    - Quick scan istniejącego kodu
    - Pytaj o tech stack (potwierdź wykryte)
    - Focus na integrację nowej funkcji
```

**Krok 2C: Jeśli "Nie - zewnętrzny projekt":**
```yaml
brownfield_external:
  # Brak kontekstu CCv3 - pełny onboard
  required_steps:
    1. Onboard:
       - tldr structure . --depth 3
       - Analyze package.json / pyproject.toml
       - Identify patterns and conventions
    2. Create initial ledger:
       - Document discovered architecture
       - Note existing conventions
    3. Interview adaptation:
       - Confirm detected tech stack
       - Ask about integration points
       - Understand existing constraints
```

**Krok 3: Brownfield-specific questions**

Po ustaleniu kontekstu, ZAMIAST standardowych pytań o tech stack:

```yaml
brownfield_interview:
  runda_1_adaptation:
    instead_of: "Co dokładnie ma powstać?"
    ask: "Jaką NOWĄ funkcjonalność chcesz dodać do istniejącego projektu?"

  runda_2_adaptation:
    instead_of: "Kto będzie tego używał?"
    ask: "Czy nowa funkcja jest dla tych samych użytkowników co istniejące?"

  brownfield_specific:
    - "Które istniejące moduły będą dotknięte przez nową funkcję?"
    - "Czy są części kodu które NIE MOGĄ być zmieniane?"
    - "Jakie istniejące API/interfejsy muszą być zachowane?"
    - "Czy nowa funkcja wymaga migracji danych?"
    - "Jakie testy już istnieją i muszą dalej przechodzić?"
```

---

### RUNDA 1: Wizja projektu
1. "Co dokładnie ma powstać? Opisz efekt końcowy."
2. "Jaki problem to rozwiązuje? Dlaczego to budujesz?"
3. "Kto będzie tego używał?"

---

### RUNDA 2: Użytkownicy i kontekst
4. "Opisz typowego użytkownika - kim jest, co robi?"
5. "W jakim kontekście będą używać produktu?"
6. "Czy są specjalne potrzeby? (dostępność, język, urządzenia)"

---

### RUNDA 3: Funkcjonalności core
7. "Jakie są 3-5 NAJWAŻNIEJSZYCH funkcji?"
8. "Co użytkownik ma móc zrobić krok po kroku? (user journey)"
9. "Czy są funkcje które MUSZĄ działać offline?"

**DYNAMICZNE:** Dla każdej funkcji → "Opisz dokładniej jak ma działać [funkcja X]"

---

### RUNDA 4: Funkcjonalności szczegółowe
10. "Czy potrzebna jest rejestracja/logowanie?"
11. "Czy są dane do przechowywania? Jakie?"
12. "Czy potrzebne są powiadomienia?"
13. "Czy potrzebna jest integracja z innymi systemami?"

**DYNAMICZNE:**
- Jeśli logowanie → "OAuth, email/hasło, czy oba?"
- Jeśli dane → "Czy dane są wrażliwe?"
- Jeśli integracje → "Z jakimi systemami? Czy mają API?"

---

### RUNDA 5: UI/UX (jeśli ma interfejs) - **ROZSZERZONA v4.2**
14. "Jak ma wyglądać? Masz referencje, mockupy, wireframe?"
15. "Czy ma być responsywne?"
16. "Jakie są najważniejsze ekrany/widoki?"

**⚠️ PYTANIA O STACK (v4.2) - jeśli user nie odpowie, użyj UI_DEFAULTS:**
17a. "Masz preferencje co do component library? (default: shadcn/ui)"
17b. "CSS framework? (default: Tailwind)"
17c. "Preferowany font? (default: Geist, unikam Inter/Roboto)"

**🆕 PYTANIA O KIERUNEK ESTETYCZNY (v4.2 - OBOWIĄZKOWE):**
```
AskUserQuestion(
  questions: [{
    question: "Jaki kierunek estetyczny preferujesz?",
    header: "Estetyka",
    options: [
      { label: "Brutally minimal", description: "Dużo whitespace, tylko esencja" },
      { label: "Soft & organic", description: "Ciepły, przyjazny, zaokrąglony" },
      { label: "Editorial/magazine", description: "Typografia-driven, publikacja" },
      { label: "Luxury refined", description: "Elegancki, premium, serif" }
    ],
    multiSelect: false
  }]
)
```

**Mapowanie odpowiedzi na styl:**
| Odpowiedź | Fonty | Kolory | Layout |
|-----------|-------|--------|--------|
| Brutally minimal | Geist Bold + Light | Monochrome | Max whitespace |
| Soft & organic | DM Sans, Outfit | Warm neutrals | Flowing, curved |
| Editorial | Playfair + Geist | B&W + accent | Multi-column |
| Luxury refined | Serif display | Muted + gold | Precise grid |

**⚠️ JEŚLI USER WYBIERZE "Other":**
→ Zapytaj o szczegóły i zmapuj na najbliższy kierunek
→ Zapisz w planie jako `aesthetic_direction`

**DYNAMICZNE (dla projektów 3D/Canvas):**
- "Jaki ma być rozmiar obiektów na scenie? (np. budynki 2x2 jednostki)"
- "Jaka odległość między obiektami? (np. 10 jednostek)"
- "Z jakiej perspektywy ma być widok? (izometryczny, top-down, etc.)"
- "Ile obiektów ma być widocznych jednocześnie?"

**⚠️ ZMIANA v4.2:** Jeśli użytkownik nie odpowiada na pytania wizualne:
→ **UŻYJ UI_DEFAULTS** (sekcja 3.4) zamiast pytać ponownie
→ **WYBIERZ aesthetic_direction** na podstawie typu projektu:
  - Dashboard/tools → brutally_minimal
  - Consumer app → soft_organic
  - Portfolio/blog → editorial
  - SaaS/enterprise → luxury_refined
→ Zapisz wybrany kierunek w planie i kontynuuj

---

### RUNDA 6: MVP vs Full scope
17. "Co MUSI być w pierwszej wersji (MVP)?"
18. "Co może poczekać na v2?"
19. "Gdybyś miał tylko 1 dzień - co byś zbudował?"

---

### RUNDA 7: Kryteria sukcesu
20. "Po czym poznasz że projekt jest GOTOWY?"
21. "Jakie metryki będą świadczyć o sukcesie?"
22. "Kto będzie akceptował że projekt jest 'done'?"

---

### RUNDA 8: Ryzyka i obawy
23. "Co Cię NAJBARDZIEJ martwi w tym projekcie?"
24. "Co może pójść nie tak?"
25. "Jakie są największe unknowns?"

---

### RUNDA 9: Blokery i zależności
26. "Czy są rzeczy które mogą ZABLOKOWAĆ pracę?"
27. "Czy czekasz na coś od kogoś?"
28. "Czy potrzebujesz dostępu do czegoś czego nie masz?"

---

### RUNDA 10: Sesja autonomiczna (NOWE!)
29. "Ile czasu chcesz przeznaczyć na tę sesję? (np. 2h, 4h, overnight)"
30. "Jaki jest maksymalny budżet? (np. $20, $50, bez limitu)"
31. "Czy chcesz być powiadamiany o postępach? Jak często?"
32. "Co powinno zatrzymać sesję? (sukces, błąd, pytanie do Ciebie)"

---

### RUNDA 11+: Kontynuuj jeśli projekt złożony

Dodatkowe rundy dla:
- Środowisko i deployment (33-36)
- Testowanie i jakość (37-40)
- Dokumentacja (41-43)
- Bezpieczeństwo (44-47)
- Skalowanie (48-50)

---

### ZAKOŃCZENIE WYWIADU

**ZAWSZE zapytaj na końcu:**
> "Czy jest coś o czym nie zapytałem a powinienem wiedzieć?"

**Następnie podsumuj:**
> "Rozumiem że chcesz [CEL]. MVP to [LISTA]. Sesja max [CZAS], budżet [KWOTA]. Czy to poprawne?"

---

## FAZA 3: Analiza i kategoryzacja

### 3.1 Określ na podstawie wywiadu:

```yaml
project_analysis:
  type: [frontend|backend|fullstack|mobile|CLI|script]
  complexity: [simple|medium|complex]
  estimated_hours: [1-2|4-8|8-24|24+]
  tech_stack: [detected technologies]

  features:
    must_have: [lista z wywiadu]
    should_have: [lista z wywiadu]
    nice_to_have: [lista z wywiadu]

  session:
    max_duration: [z wywiadu]
    max_cost: [z wywiadu]
    termination_signal: [z wywiadu]
```

### 3.2 Definition of Done (KRYTYCZNE dla v4!)

**⚠️ UWAGA:** AI interpretuje "w pełni funkcjonalna" jako "kod się kompiluje".
User interpretuje jako "aplikacja działa i wygląda dobrze".

**MUSISZ EXPLICIT zdefiniować co oznacza "done" dla tego projektu:**

```yaml
definition_of_done:
  # ─── DLA FRONTEND / FULLSTACK ───
  frontend:
    visual:
      - "Strona się renderuje (nie biały ekran)"
      - "Brak błędów w konsoli przeglądarki"
      - "Core elementy widoczne na ekranie"
      - "Layout zgodny z wireframe ±20%"
    functional:
      - "User flows są wykonywalne"
      - "Aplikacja reaguje na input"
      - "Nawigacja działa"
    technical:
      - "npm run build passes"
      - "Testy przechodzą"
      - "Brak TypeScript errors"

  # ─── DLA BACKEND / API ───
  backend:
    functional:
      - "Endpointy odpowiadają"
      - "Health check passes"
      - "CRUD operations work"
    technical:
      - "Build passes"
      - "Tests pass"
      - "No security warnings"

  # ─── DLA 3D / CANVAS / GAME ───
  canvas_3d:
    visual:
      - "Scene renderuje się (nie pusty canvas)"
      - "Obiekty są widoczne (nie poza frustum)"
      - "Kamera patrzy na scenę"
      - "Koordynaty są spójne (camera frustum vs object positions)"
      # ═══ v4.1: DESIGN REFERENCE REQUIRED ═══
      - "Wartości layout pochodzą ze specyfikacji (nie arbitralne)"
      - "Odległości między obiektami zgodne z design_reference"
    functional:
      - "Interakcja działa (pan/zoom/click)"
    technical:
      - "No WebGL errors"
      - "FPS > 30"

    # ═══ v4.1: MEASURABLE CRITERIA ═══
    measurable:
      object_spacing:
        description: "Odległość między obiektami"
        source_required: true  # MUSI być podane przez usera lub z mockupu
        verification: |
          # Przez DevTools/Three.js inspector:
          # distance(obj1.position, obj2.position) >= specified_spacing
      object_visibility:
        description: "Wszystkie obiekty widoczne w viewport"
        verification: |
          # Sprawdź czy bounding box każdego obiektu jest w frustum kamery
      no_overlap:
        description: "Obiekty się nie nakładają wizualnie"
        verification: |
          # Sprawdź czy bounding boxes się nie przecinają (z marginesem)
```

**W każdej fazie sprawdź czy Definition of Done jest spełnione!**

### 3.3 Design Reference Policy (KRYTYCZNE dla UI projektów!)

**⚠️ PROBLEM:** AI nie może wymyślać wartości liczbowych dla layoutu.

Wartości takie jak:
- Spacing między elementami (px, units)
- Rozmiary elementów (width, height)
- Camera frustum / zoom levels
- Font sizes, margins, paddings
- Pozycje elementów na scenie 3D

**MUSZĄ pochodzić z jednego z tych źródeł:**

```yaml
design_reference_policy:
  # ─── ŹRÓDŁA WARTOŚCI (w kolejności preferencji) ───
  value_sources:
    1_user_provided:
      description: "Użytkownik jawnie podał wartości"
      example: "Budynki mają być oddalone o 50 jednostek"
      action: "Użyj dokładnie tych wartości"

    2_mockup_derived:
      description: "Zmierzone z dostarczonego mockupu/wireframe"
      example: "Na mockupie przycisk ma ~100px szerokości"
      action: "Użyj wartości z mockupu, udokumentuj źródło"

    3_existing_codebase:
      description: "Wartości z istniejącego kodu w projekcie"
      example: "Inne komponenty używają spacing: 16px"
      action: "Zachowaj spójność z istniejącym kodem"

    4_framework_defaults:
      description: "Domyślne wartości frameworka (Tailwind, Material, etc.)"
      example: "Tailwind gap-4 = 1rem = 16px"
      action: "Użyj domyślnych, udokumentuj"

    5_ask_user:
      description: "Żadne z powyższych nie dostępne"
      action: |
        ZATRZYMAJ się i zapytaj:
        "Jakie mają być odległości między [elementami]?
         Opcje: A) 16px (standardowe), B) 32px (luźne), C) Podaj własne"

  # ─── NIGDY NIE RÓB ───
  forbidden:
    - "Wymyślanie arbitralnych wartości (np. spacing = 4.5)"
    - "Używanie 'magicznych liczb' bez uzasadnienia"
    - "Zakładanie że jakakolwiek wartość 'będzie dobrze wyglądać'"

  # ─── WYMAGANA DOKUMENTACJA ───
  documentation:
    for_every_visual_value:
      - source: "[skąd ta wartość]"
      - rationale: "[dlaczego ta a nie inna]"
      - adjustable: "[czy user może łatwo zmienić]"
```

**Przykład DOBREGO podejścia:**
```yaml
# W planie:
visual_values:
  building_spacing:
    value: 60
    unit: "world units"
    source: "user_provided"
    rationale: "Użytkownik powiedział: elementy 20x dalej od siebie niż obecnie (3 * 20 = 60)"

  camera_frustum:
    value: 200
    source: "derived"
    rationale: "Frustum musi pomieścić 5x5 budynków * 60 spacing = ~300, więc 200 z marginesem"
```

**Przykład ZŁEGO podejścia (v4.0):**
```yaml
# W planie:
constants:
  BUILDING_SPACING: 4.5  # ← SKĄD TA WARTOŚĆ?!
  CAMERA_FRUSTUM: 30     # ← I TA?!
# Brak źródła, brak uzasadnienia → wizualny chaos
```

---

### 3.4 UI_DEFAULTS - Opinionated Stack (🆕 v4.2)

**⚠️ KLUCZOWA ZMIANA:** Zamiast pytać usera o stack - WYMUSZAJ defaults.
User może nadpisać, ale jeśli nie poda → użyj TYCH wartości.

```yaml
ui_defaults:
  # ═══════════════════════════════════════════════════════════════
  # WYMUSZONY STACK (jeśli user nie poda innego)
  # ═══════════════════════════════════════════════════════════════

  component_library:
    default: "shadcn/ui"
    rationale: "Pre-built, customizable, consistent components"
    alternatives: ["Radix UI", "Headless UI", "Chakra UI"]

  css_framework:
    default: "Tailwind CSS"
    rationale: "Utility-first, predictable, design-system ready"
    alternatives: ["CSS Modules", "styled-components"]

  typography:
    primary_font: "Geist"
    mono_font: "JetBrains Mono"
    fallback: "system-ui, sans-serif"
    rationale: "Distinctive, modern, NOT generic (Inter/Roboto)"

  color_approach:
    strategy: "Dominant color + sharp accent"
    css_variables: true
    dark_mode: "prefers-color-scheme OR toggle"

  spacing_scale:
    base: "4px"
    scale: [4, 8, 12, 16, 24, 32, 48, 64, 96]
    rationale: "Consistent rhythm, Tailwind-compatible"

  layout:
    max_width: "1200px"
    default_gap: "16px (gap-4)"
    container: "centered with padding"

  icons:
    default: "Lucide React"
    alternatives: ["Heroicons", "Phosphor"]

  # ═══════════════════════════════════════════════════════════════
  # PROJECT-TYPE SPECIFIC DEFAULTS
  # ═══════════════════════════════════════════════════════════════

  web_app:
    framework: "Next.js 14+ (App Router)"
    state: "React hooks + context (or Zustand for complex)"
    forms: "React Hook Form + Zod"

  dashboard:
    charts: "Recharts"
    tables: "TanStack Table"
    layout: "Sidebar + main content"

  landing_page:
    animations: "Framer Motion"
    sections: ["Hero", "Features", "CTA", "Footer"]

  canvas_3d:
    library: "Three.js + React Three Fiber"
    controls: "OrbitControls"
    camera: "Orthographic for isometric, Perspective for 3D"
```

**Jak używać w planie:**
```yaml
# W session-plan.yaml:
tech_stack:
  source: "ui_defaults"  # ← zamiast "user_provided" lub "ask_user"
  overrides:
    typography.primary_font: "Bricolage Grotesque"  # user nadpisał
```

---

### 3.5 ANTI_PATTERNS - Visual Anti-Convergence (🆕 v4.2)

**⚠️ CRITICAL:** AI naturalnie wybiera "bezpieczne" opcje = AI SLOP.
Ta sekcja JAWNIE ZAKAZUJE wzorce konwergencji.

```yaml
anti_patterns:
  # ═══════════════════════════════════════════════════════════════
  # TYPOGRAPHY - NIGDY NIE UŻYWAJ
  # ═══════════════════════════════════════════════════════════════

  forbidden_fonts:
    list:
      - "Inter"
      - "Roboto"
      - "Arial"
      - "Open Sans"
      - "Lato"
      - "Source Sans Pro"
      - "system default sans-serif as primary"
    reason: "Generic, overused, instantly recognizable as 'safe choice'"

  instead_use:
    display_fonts:
      - "Bricolage Grotesque"
      - "Playfair Display"
      - "Space Grotesk"
      - "Clash Display"
      - "Satoshi"
    body_fonts:
      - "Geist"
      - "DM Sans"
      - "Plus Jakarta Sans"
      - "Outfit"
    mono_fonts:
      - "JetBrains Mono"
      - "Fira Code"
      - "Berkeley Mono"
    technique: "Pair distinctive display font with refined body font"
    weight_contrast: "Use extremes: 100-200 (thin) vs 700-900 (bold)"
    size_jumps: "3x+ between heading and body"

  # ═══════════════════════════════════════════════════════════════
  # COLOR - NIGDY NIE UŻYWAJ
  # ═══════════════════════════════════════════════════════════════

  forbidden_colors:
    patterns:
      - "Purple/violet gradient on white background"
      - "Blue-to-purple gradient (AI signature)"
      - "Evenly distributed pastel palettes"
      - "Gray-on-gray low contrast"
      - "Rainbow gradients"
    reason: "These are statistical modes in training data = AI slop"

  instead_use:
    approaches:
      - "Dominant single color + one sharp accent"
      - "Monochromatic with texture variation"
      - "High contrast: near-black + bright accent"
      - "Warm/cool tension (not gradient blend)"
    dark_mode: "True dark (#0a0a0a) not gray (#374151)"
    technique: "Commit to a palette, use CSS variables"

  # ═══════════════════════════════════════════════════════════════
  # LAYOUT - NIGDY NIE UŻYWAJ
  # ═══════════════════════════════════════════════════════════════

  forbidden_layouts:
    patterns:
      - "Perfect symmetry everywhere"
      - "Centered everything"
      - "Equal-width columns"
      - "Predictable grid without breaks"
      - "Cards in neat rows without variation"
    reason: "Too safe, boring, forgettable"

  instead_use:
    techniques:
      - "Asymmetric layouts"
      - "Overlapping elements"
      - "Diagonal flow / angular sections"
      - "Grid-breaking hero elements"
      - "Generous negative space OR controlled density (not medium)"
      - "Varied card sizes in grids"
    rule: "At least ONE unexpected layout choice per page"

  # ═══════════════════════════════════════════════════════════════
  # BACKGROUNDS - NIGDY NIE UŻYWAJ
  # ═══════════════════════════════════════════════════════════════

  forbidden_backgrounds:
    patterns:
      - "Pure solid white (#ffffff)"
      - "Pure solid gray"
      - "Flat color without depth"
    reason: "Lacks atmosphere and depth"

  instead_use:
    techniques:
      - "Subtle gradient meshes"
      - "Noise/grain textures (opacity 0.02-0.05)"
      - "Geometric patterns (low opacity)"
      - "Layered transparencies"
      - "Subtle shadows for depth"
      - "Off-white tints (warm: #fffbf5, cool: #f8fafc)"

  # ═══════════════════════════════════════════════════════════════
  # MOTION - UNIKAJ
  # ═══════════════════════════════════════════════════════════════

  avoid_motion:
    patterns:
      - "No animations at all"
      - "Excessive micro-interactions everywhere"
      - "Linear easing (robotic feel)"

  instead_use:
    strategy: "High-impact moments > scattered animations"
    techniques:
      - "Orchestrated page load with staggered reveals"
      - "Hover states that surprise"
      - "Scroll-triggered animations (sparingly)"
      - "Ease-out for enters, ease-in for exits"
    focus: "One well-done animation > ten mediocre ones"
```

**INSTEAD Structure Rule:**
Każdy zakaz MUSI mieć pozytywną alternatywę. Nie wystarczy powiedzieć "nie rób X" - powiedz "zamiast X rób Y".

---

### 3.6 AESTHETIC_COMMITMENT - Kierunek przed kodowaniem (🆕 v4.2)

**⚠️ OBOWIĄZKOWE DLA PROJEKTÓW Z UI:**
Agent MUSI wybrać kierunek estetyczny PRZED napisaniem pierwszej linii kodu UI.

```yaml
aesthetic_commitment:
  # ═══════════════════════════════════════════════════════════════
  # DOSTĘPNE KIERUNKI ESTETYCZNE
  # ═══════════════════════════════════════════════════════════════

  directions:
    brutally_minimal:
      description: "Maximum whitespace, essential elements only"
      typography: "Large, bold headings, minimal body text"
      colors: "Monochrome or 2-color max"
      layout: "Generous negative space, clear hierarchy"
      motion: "None or very subtle"

    maximalist_rich:
      description: "Dense, detailed, information-rich"
      typography: "Multiple font weights, decorative elements"
      colors: "Rich palette, gradients, textures"
      layout: "Layered, overlapping, complex grids"
      motion: "Elaborate animations, transitions"

    brutalist_raw:
      description: "Intentionally rough, unconventional"
      typography: "Stark contrasts, unusual choices"
      colors: "High contrast, bold primaries"
      layout: "Broken grids, unexpected positioning"
      motion: "Jarring or none"

    soft_organic:
      description: "Friendly, approachable, warm"
      typography: "Rounded fonts, comfortable sizes"
      colors: "Warm neutrals, soft accents"
      layout: "Flowing, curved sections, plenty of padding"
      motion: "Gentle, spring-based animations"

    luxury_refined:
      description: "Premium, elegant, sophisticated"
      typography: "Serif headings, refined spacing"
      colors: "Muted palette, gold/cream accents"
      layout: "Precise grid, ample margins"
      motion: "Subtle, smooth, confident"

    editorial_magazine:
      description: "Publication-style, content-focused"
      typography: "Strong typographic hierarchy, pull quotes"
      colors: "Mostly black/white with strategic color"
      layout: "Multi-column, image-text interplay"
      motion: "Page-turn effects, scroll reveals"

    retro_futuristic:
      description: "Nostalgic tech, neon-tinged"
      typography: "Monospace, pixelated accents"
      colors: "Neon on dark, CRT glow effects"
      layout: "Terminal-inspired, tech borders"
      motion: "Glitch effects, scanlines"

    playful_toy:
      description: "Fun, colorful, game-like"
      typography: "Rounded, bouncy fonts"
      colors: "Bright, saturated, varied"
      layout: "Informal, floating elements"
      motion: "Bouncy, springy, delightful"

  # ═══════════════════════════════════════════════════════════════
  # PROCES WYBORU
  # ═══════════════════════════════════════════════════════════════

  selection_process:
    1_context_analysis:
      questions:
        - "Kto jest użytkownikiem? (developer, enterprise, consumer)"
        - "Jaki ton komunikacji? (profesjonalny, casual, tech)"
        - "Jakie emocje ma wywoływać? (zaufanie, ekscytacja, spokój)"

    2_commitment:
      action: "Wybierz JEDEN kierunek i zapisz w planie"
      format: |
        aesthetic_direction:
          chosen: "brutally_minimal"
          rationale: "Dashboard dla devów - focus na danych, nie dekoracji"
          constraints:
            - "Max 2 kolory + neutrals"
            - "Żadnych dekoracyjnych elementów"
            - "Typography-driven hierarchy"

    3_consistency:
      rule: "TRZYMAJ SIĘ wybranego kierunku przez całą sesję"
      forbidden: "Mieszanie kierunków (np. minimalist hero + maximalist footer)"

  # ═══════════════════════════════════════════════════════════════
  # MATCHING COMPLEXITY
  # ═══════════════════════════════════════════════════════════════

  implementation_matching:
    rule: "Complexity kodu MUSI odpowiadać wybranej estetyce"
    examples:
      - direction: "maximalist_rich"
        code: "Elaborate animations, layered components, rich state"
      - direction: "brutally_minimal"
        code: "Restrained, precise, no extra features"
    warning: "Minimalist design + elaborate code = inconsistent"
```

**OBOWIĄZKOWY OUTPUT:**
Przed rozpoczęciem implementacji UI, plan MUSI zawierać:
```yaml
aesthetic_commitment:
  direction: "[chosen_direction]"
  rationale: "[why this fits the project]"
  key_constraints: [list of 3-5 rules to follow]
```

---

### 3.7 Wybierz agentów do delegacji:

| Typ projektu | Agenci Feature | Agenci Validation |
|--------------|----------------|-------------------|
| Backend API | oracle, architect | arbiter, sleuth, scout |
| Frontend | oracle, architect | arbiter, sleuth |
| Fullstack | oracle, architect, security | arbiter, sleuth, scout |
| Mobile | oracle, architect | arbiter, sleuth |
| CLI | oracle | arbiter, sleuth |

---

### 3.8 UI_SINGLE_AUTHORITY - Uproszczona delegacja dla UI (🆕 v4.2)

**⚠️ PROBLEM Z v4.1:** Zbyt wielu agentów konsultujących design = brak spójności.

```yaml
ui_delegation:
  # ═══════════════════════════════════════════════════════════════
  # SINGLE AUTHORITY RULE
  # ═══════════════════════════════════════════════════════════════

  principle: |
    Dla decyzji WIZUALNYCH jeden agent (lub główny kontekst)
    jest JEDYNYM źródłem prawdy. Bez "committee design".

  visual_decisions:
    owner: "main_context OR single_delegated_agent"
    not_delegated_to:
      - "Multiple agents voting on colors"
      - "Oracle + architect + security all giving UI opinions"
      - "Wave of agents each modifying visual direction"

  # ═══════════════════════════════════════════════════════════════
  # CO DELEGOWAĆ VS ZACHOWAĆ
  # ═══════════════════════════════════════════════════════════════

  delegate_to_agents:
    oracle:
      - "Research best practices for [feature type]"
      - "Find examples of similar apps"
      - "Documentation lookup"
    architect:
      - "Component structure"
      - "State management approach"
      - "Data flow design"
    arbiter:
      - "Test specifications"
      - "Accessibility requirements"
    security:
      - "Auth patterns"
      - "Input validation"

  keep_in_main_context:
    - "Aesthetic direction choice"
    - "Color palette decisions"
    - "Typography selection"
    - "Layout structure"
    - "Animation approach"
    - "Overall visual consistency"

  # ═══════════════════════════════════════════════════════════════
  # FORBIDDEN PATTERNS
  # ═══════════════════════════════════════════════════════════════

  forbidden:
    - pattern: "Agent A suggests blue, Agent B suggests green"
      problem: "No single authority → compromise → mediocre"

    - pattern: "Oracle researches 5 UI approaches, plan includes all"
      problem: "Franken-design from multiple sources"

    - pattern: "Visual-validator proposes fixes without aesthetic context"
      problem: "Fixes may break aesthetic direction"

  # ═══════════════════════════════════════════════════════════════
  # CORRECT APPROACH
  # ═══════════════════════════════════════════════════════════════

  correct_approach:
    1: "Main context commits to aesthetic_direction FIRST"
    2: "Agents receive aesthetic_direction as CONSTRAINT"
    3: "Agent suggestions must align with chosen direction"
    4: "Main context has VETO on any visual change"

  agent_prompt_addition: |
    CONTEXT: This project uses "{aesthetic_direction}" aesthetic.
    Your suggestions MUST align with this direction.
    Do NOT propose visual changes that conflict with:
    - {typography_choice}
    - {color_approach}
    - {layout_style}
```

**Praktyczna implementacja:**
```yaml
# W task delegation dla UI projektu:
delegation:
  oracle:
    prompt: |
      Research component patterns for {feature}.
      CONSTRAINT: Project uses "brutally_minimal" aesthetic.
      Only suggest patterns that match: monochrome, max whitespace, typography-driven.

  architect:
    prompt: |
      Design component structure for {feature}.
      CONSTRAINT: Aesthetic is "brutally_minimal".
      Prefer: simple props, no decorative wrappers, lean components.
```

---

## FAZA 4: DUAL ENHANCEMENT - DELEGACJA AGENTÓW

### ⚠️ KIEDY DELEGACJA JEST OBOWIĄZKOWA

**MUSISZ delegować jeśli KTÓRYKOLWIEK warunek:**

| Warunek | Akcja |
|---------|-------|
| Complexity = medium/complex | → DELEGUJ wszystko |
| Session > 2h | → DELEGUJ wszystko |
| Features > 3 | → DELEGUJ feature enhancement |
| Ma UI | → DELEGUJ (accessibility, UX) |
| Ma security requirements | → DELEGUJ security agent |

**Możesz pominąć TYLKO jeśli:**
- Complexity = simple
- Session < 1h
- 1-2 proste features
- Brak UI, brak security

---

### 4.0 WAVE-BASED DELEGATION (v3.1)

**WAŻNE:** Agenci mają zależności - nie uruchamiaj wszystkich równolegle!

```yaml
# Dependency graph:
# Wave 1 (parallel): oracle, scout, sleuth - zbieranie danych
# Wave 2 (parallel, after Wave 1): architect, security - design
# Wave 3 (after Wave 2): arbiter - testing
#
# oracle ──┐
# scout ───┼──► architect ──┐
# sleuth ──┘      │         │
#                 ▼         ├──► arbiter
#              security ────┘

delegation_waves:
  wave_1:
    name: "Data Gathering"
    agents: [oracle, scout, sleuth]
    parallel: true
    timeout: "3min"
    purpose: "Zbierz best practices, analizę codebase, ryzyka"

  wave_2:
    name: "Design"
    agents: [architect, security]
    parallel: true
    depends_on: wave_1
    timeout: "3min"
    input_from:
      architect: [oracle.feature_enhancements, scout.codebase_analysis]
      security: [oracle.security_considerations, sleuth.security_risks]
    purpose: "Zaprojektuj architekturę i hardening"

  wave_3:
    name: "Validation"
    agents: [arbiter]
    depends_on: wave_2
    timeout: "3min"
    input_from:
      arbiter: [architect.architecture, security.requirements]
    purpose: "Zaprojektuj strategię testowania"
```

**Execution:**
```
1. WAVE 1: Uruchom oracle, scout, sleuth (równolegle)
2. Czekaj na wszystkie odpowiedzi (timeout 3min)
3. WAVE 2: Uruchom architect i security z kontekstem z Wave 1
4. Czekaj na odpowiedzi
5. WAVE 3: Uruchom arbiter z kontekstem z Wave 2
6. Agreguj wszystkie wyniki
```

---

### 4.1 FEATURE ENHANCEMENT AGENTS

**WAVE 1** - uruchom równolegle (Task tool):

#### Agent: oracle (Best Practices) [WAVE 1]
```
KONTEKST: Planujemy sesję autonomiczną.
PROJEKT: [typ projektu]
TECH STACK: [technologie]
USER FEATURES: [lista features z wywiadu]

ZADANIE: Rozbuduj specyfikację features o industry best practices.

Dla KAŻDEJ feature z listy odpowiedz:
1. Czy ta feature jest kompletna? Co brakuje?
2. Jakie są industry standards dla tego typu funkcji?
3. Jakie są common pitfalls których unikać?
4. Jakie security considerations?

DODATKOWO zaproponuj features których user nie wymienił ale powinien mieć:
- Security features
- Error handling
- Logging/monitoring
- Configuration
- Edge cases handling

FORMAT YAML:
```yaml
feature_enhancements:
  - original: "[feature z wywiadu]"
    additions:
      - name: "[co dodać]"
        rationale: "[dlaczego]"
        priority: [must_have|should_have|nice_to_have]
    pitfalls:
      - "[czego unikać]"
    security:
      - "[security consideration]"

new_features:
  - name: "[nowa feature]"
    rationale: "[dlaczego potrzebna]"
    priority: [must_have|should_have|nice_to_have]
    category: [security|error_handling|monitoring|config|ux]
```
```

#### Agent: architect (Structure & Patterns) [WAVE 2]
```
KONTEKST: Planujemy sesję autonomiczną.
PROJEKT: [typ projektu]
TECH STACK: [technologie]
USER FEATURES: [lista features z wywiadu]
CODEBASE STRUCTURE: [output z TLDR lub Glob]

ZADANIE: Zaproponuj właściwą architekturę i strukturę.

1. Jaka struktura katalogów/modułów?
2. Jakie design patterns użyć?
3. Jak podzielić na komponenty/serwisy?
4. Jakie interfaces/contracts zdefiniować?
5. Jak obsłużyć błędy (error handling strategy)?
6. Jak logować (logging strategy)?

FORMAT YAML:
```yaml
architecture:
  structure:
    - path: "[ścieżka]"
      purpose: "[cel]"

  patterns:
    - pattern: "[nazwa wzorca]"
      where: "[gdzie użyć]"
      rationale: "[dlaczego]"

  components:
    - name: "[nazwa]"
      responsibility: "[odpowiedzialność]"
      interfaces: ["[interface]"]

  error_handling:
    strategy: "[strategia]"
    error_types:
      - type: "[typ błędu]"
        handling: "[jak obsłużyć]"

  logging:
    strategy: "[strategia]"
    levels:
      - level: "[poziom]"
        when: "[kiedy logować]"
```
```

#### Agent: security (jeśli dotyczy) [WAVE 2]
```
KONTEKST: Planujemy sesję autonomiczną.
PROJEKT: [typ projektu]
TECH STACK: [technologie]
USER FEATURES: [lista features z wywiadu]
SENSITIVE DATA: [z wywiadu - jakie dane]

ZADANIE: Zdefiniuj wymagania security.

1. Jakie dane wymagają ochrony?
2. Jakie authentication/authorization?
3. Jakie encryption potrzebne?
4. Jakie OWASP Top 10 considerations?
5. Jakie compliance requirements?
6. Jakie hardening steps?

FORMAT YAML:
```yaml
security:
  data_protection:
    - data: "[typ danych]"
      classification: [public|internal|confidential|secret]
      protection: "[jak chronić]"

  authentication:
    method: "[metoda]"
    requirements:
      - "[wymaganie]"

  authorization:
    model: "[RBAC|ABAC|etc]"
    roles:
      - role: "[rola]"
        permissions: ["[uprawnienie]"]

  owasp_checklist:
    - risk: "[nazwa ryzyka OWASP]"
      mitigation: "[jak mitygować]"
      checkpoint: "[jak sprawdzić]"

  hardening:
    - area: "[obszar]"
      action: "[akcja]"
      priority: [must|should|could]
```
```

---

### 4.2 QUALITY VALIDATION AGENTS

Uruchom równolegle (Task tool):

#### Agent: arbiter (Test Strategy) [WAVE 3]
```
KONTEKST: Planujemy sesję autonomiczną.
PROJEKT: [typ projektu]
TECH STACK: [technologie]
FEATURES: [lista features - oryginalne + enhanced]
ARCHITECTURE: [output z architect]

ZADANIE: Zaprojektuj kompletną strategię testowania.

Dla KAŻDEJ feature rozpisz:
1. Unit tests (minimum 5 per feature)
2. Integration tests (minimum 3 per flow)
3. Edge case tests (minimum 3 per feature)

Dodatkowo:
4. Regression tests (co nie może się zepsuć)
5. Performance tests (jeśli dotyczy)
6. Security tests (jeśli dotyczy)
7. Quality gates (coverage, performance thresholds)

FORMAT YAML:
```yaml
test_strategy:
  unit_tests:
    - feature: "[nazwa feature]"
      tests:
        - test: "[nazwa testu]"
          assertion: "[co sprawdza]"
        # minimum 5 testów per feature

  integration_tests:
    - flow: "[nazwa flow]"
      tests:
        - test: "[nazwa testu]"
          steps: ["[krok 1]", "[krok 2]"]
          expected: "[oczekiwany wynik]"
        # minimum 3 testy per flow

  edge_cases:
    - feature: "[nazwa feature]"
      cases:
        - case: "[opis edge case]"
          test: "[jak testować]"
          expected: "[oczekiwany wynik]"
        # minimum 3 edge cases per feature

  regression:
    - area: "[obszar]"
      test: "[co sprawdzić]"

  security_tests:
    - vulnerability: "[typ]"
      test: "[jak testować]"
      expected: "[oczekiwany wynik]"

  quality_gates:
    coverage:
      overall: [%]
      critical_paths: [%]
    performance:
      - metric: "[metryka]"
        threshold: "[próg]"
```
```

#### Agent: visual-validator (Visual Verification) [WAVE 3] - ONLY FOR FRONTEND/CANVAS

**⚠️ OBOWIĄZKOWY dla projektów z UI!** (frontend, fullstack, game, canvas)

**WAŻNE (v4.1):** Visual-validator sprawdza OBECNOŚĆ i BŁĘDY, nie ESTETYKĘ.
AI może wykryć "element istnieje" ale nie "wygląda ładnie".

```
KONTEKST: Planujemy sesję autonomiczną dla projektu z UI.
PROJEKT: [typ projektu]
TECH STACK: [technologie]
FEATURES: [lista features]
DEFINITION_OF_DONE: [z sekcji 3.2]
DESIGN_REFERENCE: [mockup/wireframe jeśli dostępny - KRYTYCZNE!]

ZADANIE: Zaprojektuj EXECUTABLE checkpointy wizualne.

⚠️ OGRANICZENIA AI:
- AI MOŻE sprawdzić: obecność elementu, widoczność, brak błędów konsoli
- AI MOŻE zmierzyć: pozycja (x,y), rozmiar (width,height) przez DevTools
- AI MOŻE porównać: screenshot vs dostarczone mockup
- AI NIE MOŻE ocenić: "czy to wygląda dobrze" bez wzorca

Dla KAŻDEGO widoku/komponentu:
1. Jaki HTML element powinien istnieć? (obecność)
2. Jaki selector go identyfikuje? (DOM)
3. Czy jest widoczny (nie display:none)? (visibility)
4. Czy są błędy w konsoli? (health)
5. Czy pozycja/rozmiar są zgodne z mockupem? (TYLKO jeśli mockup dostępny!)

FORMAT YAML:
```yaml
visual_verification:
  # ═══════════════════════════════════════════════════════════
  # TIER 1: HEALTH CHECKS (AI może w pełni zweryfikować)
  # ═══════════════════════════════════════════════════════════
  health_checks:
    smoke_test:
      description: "Aplikacja się uruchamia i wyświetla"
      command: |
        npm run dev &
        sleep 5
        curl -s http://localhost:5173 | grep -q '<div id="root">'
      expected:
        exit_code: 0
      ai_can_verify: true  # ← AI może to w pełni zweryfikować
      on_failure: halt

    console_errors:
      description: "Brak błędów w konsoli"
      command: |
        npx playwright test console-check.spec.ts
      expected:
        errors: 0
      ai_can_verify: true
      on_failure: halt

    elements_exist:
      description: "Wymagane elementy istnieją w DOM"
      command: |
        npx playwright test dom-presence.spec.ts
      ai_can_verify: true
      on_failure: halt

  # ═══════════════════════════════════════════════════════════
  # TIER 2: MEASURABLE CHECKS (AI może zmierzyć i porównać)
  # ═══════════════════════════════════════════════════════════
  measurable_checks:
    - component: "[nazwa komponentu]"
      verification:
        type: devtools_measurement
        selector: "[CSS selector]"
        measures:
          - property: "boundingBox.width"
            expected: ">= 100"  # wartość z mockupu lub user-provided
            source: "mockup/user"
          - property: "visibility"
            expected: "visible"
      ai_can_verify: true
      on_failure: warn

  # ═══════════════════════════════════════════════════════════
  # TIER 3: COMPARISON CHECKS (wymaga mockupu!)
  # ═══════════════════════════════════════════════════════════
  comparison_checks:
    - name: "Layout matches mockup"
      requires: "design_reference"  # ← BEZ MOCKUPU TA SEKCJA JEST PUSTA
      command: |
        npx playwright screenshot http://localhost:5173 current.png
        # Porównanie przez AI vision lub pixel diff
      reference_file: "[path do mockupu]"
      ai_can_verify: "partial"  # AI może porównać ale nie ocenić "czy ok"
      tolerance: "layout positions ±20%"
      on_failure: warn_and_request_human_review

  # ═══════════════════════════════════════════════════════════
  # TIER 4: HUMAN REVIEW (AI NIE MOŻE zweryfikować)
  # ═══════════════════════════════════════════════════════════
  human_review_required:
    - name: "Estetyka i UX"
      description: "Czy layout wygląda profesjonalnie?"
      ai_can_verify: false  # ← JAWNE - AI nie może tego ocenić
      action: "Wygeneruj screenshot, poproś użytkownika o review"
      screenshot_path: "screenshots/final-review.png"
      questions_for_user:
        - "Czy elementy są odpowiednio rozmieszczone?"
        - "Czy kolory i typografia są akceptowalne?"
        - "Czy coś wymaga poprawy przed kontynuacją?"
```
```

**Wygeneruj też smoke test script:**
```typescript
// tests/smoke.spec.ts
import { test, expect } from '@playwright/test';

test('app renders without errors', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', m => {
    if (m.type() === 'error') errors.push(m.text());
  });

  await page.goto('http://localhost:5173');
  await expect(page.locator('body')).not.toBeEmpty();
  await page.waitForSelector('[data-testid="app"]', { timeout: 5000 });

  expect(errors).toHaveLength(0);
  await page.screenshot({ path: 'smoke-test.png' });
});
```

#### Agent: sleuth (Risk Analysis) [WAVE 1]
```
KONTEKST: Planujemy sesję autonomiczną.
PROJEKT: [typ projektu]
TECH STACK: [technologie]
FEATURES: [lista features]
USER CONCERNS: [obawy z wywiadu]

ZADANIE: Zidentyfikuj wszystkie ryzyka i blokery.

1. Technical risks (co może się zepsuć technicznie)
2. Regression risks (co możemy zepsuć przez przypadek)
3. Integration risks (zewnętrzne zależności)
4. Data risks (migracje, utrata danych)
5. Performance risks
6. Security risks
7. Blockers (co może zatrzymać pracę)

Dla KAŻDEGO ryzyka podaj mitigation i checkpoint.

FORMAT YAML:
```yaml
risks:
  technical:
    - risk: "[opis ryzyka]"
      probability: [low|medium|high]
      impact: [low|medium|high|critical]
      mitigation: "[jak zmitigować]"
      checkpoint: "[jak sprawdzić że OK]"

  regression:
    - risk: "[co możemy zepsuć]"
      affected: ["[co affected]"]
      mitigation: "[jak uniknąć]"
      checkpoint: "[jak sprawdzić]"

  integration:
    - dependency: "[zewnętrzna zależność]"
      risk: "[co może pójść nie tak]"
      mitigation: "[jak obsłużyć]"
      checkpoint: "[jak sprawdzić]"

  blockers:
    - blocker: "[opis blokera]"
      severity: [blocks_start|blocks_phase|warning]
      owner: [user|system|external]
      action: "[co zrobić]"
      checkpoint: "[jak sprawdzić że odblokowane]"
```
```

#### Agent: scout (Codebase Analysis) [WAVE 1]
```
KONTEKST: Planujemy sesję autonomiczną.
PROJEKT: [ścieżka projektu]
FEATURES: [lista features do implementacji]

ZADANIE: Przeanalizuj codebase i zwróć:

1. Affected files (które pliki będą modyfikowane)
2. Dependent files (które importują affected)
3. Test files (które testy trzeba zaktualizować)
4. Config files (które config trzeba zmienić)
5. Dependencies (zewnętrzne paczki potrzebne)

FORMAT YAML:
```yaml
codebase_analysis:
  affected_files:
    - path: "[ścieżka]"
      action: [create|modify|delete]
      complexity: [low|medium|high]
      reason: "[dlaczego]"

  dependent_files:
    - path: "[ścieżka]"
      imports_from: ["[affected file]"]
      change_required: [yes|no|maybe]

  test_files:
    - path: "[ścieżka]"
      status: [exists|needs_creation|needs_update]
      coverage_for: ["[affected file]"]

  config_files:
    - path: "[ścieżka]"
      changes:
        - "[co zmienić]"

  dependencies:
    add:
      - package: "[nazwa]"
        version: "[wersja]"
        reason: "[dlaczego potrzebna]"
    update:
      - package: "[nazwa]"
        from: "[obecna]"
        to: "[nowa]"
        reason: "[dlaczego]"
```
```

---

### 4.3 AGREGACJA WYNIKÓW

Po zebraniu wszystkich odpowiedzi od agentów:

1. **Merge feature enhancements:**
   - Core features (z wywiadu)
   - Oracle additions (best practices)
   - Architect additions (structure)
   - Security additions (hardening)

2. **Merge validation checkpoints:**
   - Unit tests (z arbiter)
   - Integration tests (z arbiter)
   - Edge cases (z arbiter + oracle)
   - Security tests (z arbiter + security)
   - Risk checkpoints (z sleuth)

3. **Resolve conflicts:**
   - Jeśli agent proponuje coś sprzecznego z wywiadem → pytaj usera
   - Jeśli priority się różni → weź wyższy

4. **Count totals:**
   - Policz features: original vs enhanced
   - Policz checkpoints: expected ratio 10-15x

---

## FAZA 5: GENEROWANIE PLIKÓW

### 5.1 session-plan.yaml (główny output)

```yaml
# thoughts/shared/handoffs/session-YYYY-MM-DD-HHMM.yaml
# Generated by /session-init v4.2 with Opinionated UI Defaults

meta:
  type: session_init
  version: "4.2"
  created: "[timestamp]"
  source: "/session-init"

  enhancement_stats:
    original_features: [N]
    enhanced_features: [M]
    feature_multiplier: "[M/N]x"

    original_checkpoints: [X]
    enhanced_checkpoints: [Y]
    checkpoint_multiplier: "[Y/X]x"

  agents_consulted:
    - oracle
    - architect
    - arbiter
    - sleuth
    - scout
    # + security jeśli użyty

# ════════════════════════════════════════════════════════════
# SESSION CONFIG
# ════════════════════════════════════════════════════════════

session:
  goal: "[cel z wywiadu - 1-2 zdania]"

  context:
    project_type: "[typ]"
    tech_stack: ["[tech1]", "[tech2]"]
    complexity: "[simple|medium|complex]"

  termination:
    max_duration: "[z wywiadu, np. 4h]"
    max_cost: "[z wywiadu, np. $30]"
    success_signal: "[z wywiadu]"
    stop_on_blocker: [true|false]

  notifications:
    frequency: "[z wywiadu, np. every 30min]"
    channels: ["[np. terminal]"]

# ════════════════════════════════════════════════════════════
# 🆕 v4.2: UI STACK & AESTHETIC (dla projektów z UI)
# ════════════════════════════════════════════════════════════

ui_config:
  # Stack - z UI_DEFAULTS lub user override
  stack:
    component_library: "shadcn/ui"        # default, user może zmienić
    css_framework: "Tailwind CSS"
    typography:
      primary: "Geist"
      mono: "JetBrains Mono"
    icons: "Lucide React"
    source: "ui_defaults"                 # lub "user_provided"

  # Aesthetic commitment (OBOWIĄZKOWE)
  aesthetic:
    direction: "[brutally_minimal|soft_organic|editorial|luxury_refined|...]"
    rationale: "[dlaczego ten kierunek pasuje do projektu]"
    constraints:
      - "[ograniczenie 1, np. Max 2 kolory + neutrals]"
      - "[ograniczenie 2, np. Typography-driven hierarchy]"
      - "[ograniczenie 3, np. No decorative elements]"

  # Anti-patterns to enforce
  anti_patterns_enforced:
    fonts: ["Inter", "Roboto", "Arial"]     # ZAKAZANE
    colors: ["purple gradient", "rainbow"]   # ZAKAZANE
    layouts: ["perfect symmetry"]            # ZAKAZANE

  # Design values (jeśli user podał lub derived)
  values:
    spacing_base: "4px"
    max_width: "1200px"
    border_radius: "[sharp|rounded|pill]"
    source: "[ui_defaults|user_provided|mockup_derived]"

# ════════════════════════════════════════════════════════════
# ENHANCED FEATURES
# ════════════════════════════════════════════════════════════

features:
  # ─── CORE (from interview) ───
  core:
    - id: F1
      name: "[feature 1]"
      priority: must_have
      source: user

    # ... więcej core features

  # ─── ENHANCED BY ORACLE ───
  best_practices:
    - id: F[N+1]
      name: "[feature]"
      detail: "[szczegóły]"
      priority: [must_have|should_have]
      rationale: "[dlaczego]"
      source: oracle

    # ... więcej best practices

  # ─── ENHANCED BY ARCHITECT ───
  architecture:
    - id: F[N+M+1]
      name: "[feature]"
      detail: "[szczegóły]"
      priority: [should_have|nice_to_have]
      rationale: "[dlaczego]"
      source: architect

    # ... więcej architecture features

  # ─── ENHANCED BY SECURITY ───
  security:
    - id: F[...]
      name: "[feature]"
      detail: "[szczegóły]"
      priority: must_have
      rationale: "[dlaczego]"
      source: security

    # ... więcej security features

# ════════════════════════════════════════════════════════════
# v4.0: EXECUTABLE CHECKPOINT SCHEMA
# ════════════════════════════════════════════════════════════
#
# ⚠️ PROBLEM W v3: Checkpointy były OPISOWE ("[ ] Scene renders")
#    AI oznaczało je jako done jeśli kod się kompilował.
#    Nie było sposobu na WYKONANIE i WERYFIKACJĘ checkpointu.
#
# ✅ ROZWIĄZANIE v4: Checkpointy są WYKONYWALNE
#    Każdy checkpoint ma command + expected + on_failure
#
# ═══════════════════════════════════════════════════════════

checkpoint_schema:
  # ─── FORMAT EXECUTABLE CHECKPOINT ───
  executable:
    - id: "CP-{PHASE}-{NUM}"
      description: "[co sprawdzamy]"
      priority: must_pass  # must_pass | should_pass | nice_to_have
      verification:
        type: command       # command | assertion | playwright | manual
        command: |
          npm run dev &
          sleep 5
          curl -s http://localhost:5173 | grep -q '<div id="root">'
        expected:
          exit_code: 0
          # LUB: contains: "text"
          # LUB: not_contains: "Error"
          # LUB: min_value: 100
        timeout: "30s"
      on_failure:
        action: halt        # halt | retry | skip | notify_user
        max_retries: 2
        fallback: null

  # ─── TYPY WERYFIKACJI ───
  verification_types:
    command:
      description: "Uruchom bash command, sprawdź exit code"
      example: "curl -s localhost:5173 | grep -q '<div'"

    assertion:
      description: "Sprawdź warunek w kodzie (test)"
      example: "npm test -- --grep 'renders'"

    playwright:
      description: "Visual test z Playwright"
      example: "npx playwright test smoke.spec.ts"

    manual:
      description: "Wymaga weryfikacji użytkownika"
      example: "Sprawdź screenshot i potwierdź"
      use_sparingly: true

  # ─── PRIORITY LEVELS ───
  priorities:
    must_pass:
      description: "Blokuje dalszą pracę jeśli fail"
      on_failure: halt
    should_pass:
      description: "Ostrzega ale kontynuuje"
      on_failure: warn_and_continue
    nice_to_have:
      description: "Loguje ale nie blokuje"
      on_failure: log

# ════════════════════════════════════════════════════════════
# VALIDATION MATRIX
# ════════════════════════════════════════════════════════════

validation:
  # ─── VISUAL SMOKE TEST (v4 - OBOWIĄZKOWY dla UI) ───
  visual_smoke:
    enabled: true  # dla frontend/fullstack/canvas
    checkpoints:
      - id: VS-1
        description: "Strona się renderuje"
        verification:
          type: command
          command: "npm run dev & sleep 5 && curl -s localhost:5173 | grep -q '<'"
          expected:
            exit_code: 0
        on_failure:
          action: halt
        priority: must_pass

      - id: VS-2
        description: "Brak błędów w konsoli"
        verification:
          type: playwright
          command: "npx playwright test tests/console-check.spec.ts"
          expected:
            exit_code: 0
        on_failure:
          action: halt
        priority: must_pass

      - id: VS-3
        description: "Core element widoczny"
        verification:
          type: playwright
          command: "npx playwright test tests/core-visible.spec.ts"
          expected:
            exit_code: 0
        on_failure:
          action: halt
        priority: must_pass

  # ─── UNIT TESTS ───
  unit_tests:
    total: [N]
    tests:
      - id: U1
        feature: F1
        test: "[nazwa testu]"
        assertion: "[co sprawdza]"
        checkpoint: "[ ] [checkpoint text]"

      # ... wszystkie unit tests z arbiter

  # ─── INTEGRATION TESTS ───
  integration_tests:
    total: [N]
    tests:
      - id: I1
        flow: "[nazwa flow]"
        test: "[nazwa testu]"
        steps: ["[krok]"]
        checkpoint: "[ ] [checkpoint text]"

      # ... wszystkie integration tests

  # ─── EDGE CASES ───
  edge_cases:
    total: [N]
    tests:
      - id: E1
        feature: F1
        case: "[opis]"
        checkpoint: "[ ] [checkpoint text]"

      # ... wszystkie edge cases

  # ─── SECURITY TESTS ───
  security_tests:
    total: [N]
    tests:
      - id: S1
        vulnerability: "[typ]"
        test: "[jak testować]"
        checkpoint: "[ ] [checkpoint text]"

      # ... wszystkie security tests

  # ─── REGRESSION TESTS ───
  regression_tests:
    total: [N]
    tests:
      - id: R1
        area: "[obszar]"
        checkpoint: "[ ] [checkpoint text]"

      # ... wszystkie regression tests

  # ─── QUALITY GATES ───
  quality_gates:
    coverage:
      overall: [%]
      critical: [%]
    performance:
      - metric: "[metryka]"
        threshold: "[próg]"
        checkpoint: "[ ] [checkpoint text]"

# ════════════════════════════════════════════════════════════
# RISKS & BLOCKERS
# ════════════════════════════════════════════════════════════

risks:
  - id: RISK1
    category: [technical|regression|integration|data|security]
    risk: "[opis]"
    probability: [low|medium|high]
    impact: [low|medium|high|critical]
    mitigation: "[jak zmitigować]"
    checkpoint: "[ ] [jak sprawdzić]"

  # ... wszystkie ryzyka z sleuth

blockers:
  - id: BLOCK1
    blocker: "[opis]"
    severity: [blocks_start|blocks_phase|warning]
    owner: [user|system|external]
    action: "[co zrobić]"
    status: [pending|resolved]
    checkpoint: "[ ] [jak sprawdzić]"

  # ... wszystkie blokery

# ════════════════════════════════════════════════════════════
# CODEBASE ANALYSIS
# ════════════════════════════════════════════════════════════

codebase:
  affected_files:
    total: [N]
    high_complexity: [M]
    files:
      - path: "[ścieżka]"
        action: [create|modify]
        complexity: [low|medium|high]

  dependencies:
    add: ["[package]"]
    update: ["[package]"]

# ════════════════════════════════════════════════════════════
# IMPLEMENTATION PHASES
# ════════════════════════════════════════════════════════════

phases:
  - name: "Phase 1: Setup"
    estimated: "[czas]"
    agent: null
    features: [F_IDs]
    checkpoints:
      - "[ ] [checkpoint 1]"
      - "[ ] [checkpoint 2]"
    blockers_required: [BLOCK_IDs]

  - name: "Phase 2: Core Implementation"
    estimated: "[czas]"
    agent: kraken
    features: [F_IDs]
    checkpoints:
      - "[ ] [checkpoint 1]"
      # ... checkpointy dla tej fazy

  - name: "Phase 3: [nazwa]"
    # ... kolejne fazy

  - name: "Phase N: Testing & Validation"
    estimated: "[czas]"
    agent: arbiter
    checkpoints:
      # Wszystkie testy

  - name: "Phase N+1: Finalize"
    estimated: "[czas]"
    checkpoints:
      - "[ ] Documentation updated"
      - "[ ] PR created"
      - "[ ] CI passes"

# ════════════════════════════════════════════════════════════
# AGGREGATED CHECKPOINTS (for progress tracking)
# ════════════════════════════════════════════════════════════

all_checkpoints:
  total: [TOTAL]
  by_phase:
    setup: [N]
    implementation: [N]
    testing: [N]
    finalization: [N]
  by_priority:
    must_pass: [N]
    should_pass: [N]
    nice_to_pass: [N]

# ════════════════════════════════════════════════════════════
# WORKFLOW HINTS (for CCv3)
# ════════════════════════════════════════════════════════════

workflow:
  recommended: "[/build greenfield|/build brownfield|/fix|/refactor]"
  flags:
    - "--skip-discovery"  # already done in interview
  agents_sequence:
    - "[agent1]"
    - "[agent2]"

# ════════════════════════════════════════════════════════════
# TASK ORCHESTRATION (CCv3 v2.1 - implement_plan integration)
# ════════════════════════════════════════════════════════════

execution:
  # Mode selection based on plan complexity
  mode: "[direct|handoffs|tasks]"  # auto-selected based on task count

  # Task persistence for cross-session continuity
  tasks_enabled: true
  task_list_id: "session-{YYYY-MM-DD-HHMM}"

  # Parallel execution domains (for Mode 3)
  domains:
    - name: "backend"
      owner: "backend-dev"
      tasks: [task_ids]
    - name: "frontend"
      owner: "frontend-dev"
      tasks: [task_ids]
    - name: "testing"
      owner: "test-runner"
      tasks: [task_ids]

  # Mode selection guide:
  # - direct: 1-3 tasks, simple work
  # - handoffs: 4-9 tasks, sequential, rich context needed
  # - tasks: 10+ tasks OR parallel work OR cross-session
```

---

### 5.2 session-plan.md (human-readable)

```markdown
# thoughts/shared/plans/session-plan.md

# Session Plan: [CEL]

**Generated:** [timestamp]
**Session-init version:** 3.0 (Dual Enhancement)

---

## Overview

| Metric | Value |
|--------|-------|
| Goal | [cel] |
| Complexity | [simple/medium/complex] |
| Estimated | [czas] |
| Max cost | [budżet] |
| Features | [original] → [enhanced] ([X]x) |
| Checkpoints | [original] → [enhanced] ([Y]x) |

---

## Enhanced Features

### 🔴 MUST HAVE (MVP)

#### Core (from interview)
- **F1: [nazwa]** - [opis]
- **F2: [nazwa]** - [opis]

#### Best Practices (from oracle)
- **F[N]: [nazwa]** - [opis]
  - *Rationale:* [dlaczego]

#### Security (from security agent)
- **F[N]: [nazwa]** - [opis]
  - *Rationale:* [dlaczego]

### 🟡 SHOULD HAVE

- **F[N]: [nazwa]** - [opis]

### 🟢 NICE TO HAVE (v2)

- **F[N]: [nazwa]** - [opis]

---

## Validation Matrix

### Unit Tests ([N] total)

#### [Feature 1]
- [ ] [test 1]
- [ ] [test 2]
- [ ] [test 3]

#### [Feature 2]
- [ ] [test 1]
...

### Integration Tests ([N] total)

#### [Flow 1]
- [ ] [test 1]
- [ ] [test 2]

### Edge Cases ([N] total)

- [ ] [edge case 1]
- [ ] [edge case 2]

### Security Tests ([N] total)

- [ ] [security test 1]
- [ ] [security test 2]

### Regression Tests ([N] total)

- [ ] [regression test 1]

### Quality Gates

| Metric | Target | Checkpoint |
|--------|--------|------------|
| Coverage | [%] | [ ] Met |
| [Performance metric] | [threshold] | [ ] Met |

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation | Checkpoint |
|------|-------------|--------|------------|------------|
| [risk 1] | [P] | [I] | [mitigation] | [ ] Verified |

---

## Blockers

| Blocker | Severity | Owner | Action | Status |
|---------|----------|-------|--------|--------|
| [blocker 1] | [sev] | [owner] | [action] | ⏳ Pending |

---

## Implementation Phases

### Phase 1: Setup (~[czas])

**Features:** F1, F2
**Checkpoints:**
- [ ] [checkpoint 1]
- [ ] [checkpoint 2]

### Phase 2: Core Implementation (~[czas])

**Agent:** kraken
**Features:** F3, F4, F5
**Checkpoints:**
- [ ] [checkpoint 1]
- [ ] [checkpoint 2]
...

### Phase N: Testing (~[czas])

**Agent:** arbiter
**Checkpoints:**
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Coverage gates met

### Phase N+1: Finalize (~[czas])

**Checkpoints:**
- [ ] Documentation updated
- [ ] PR created
- [ ] CI passes

---

## Progress Summary

| Phase | Checkpoints | Status |
|-------|-------------|--------|
| Setup | 0/[N] | ⏳ |
| Implementation | 0/[N] | ⏳ |
| Testing | 0/[N] | ⏳ |
| Finalize | 0/[N] | ⏳ |
| **TOTAL** | **0/[TOTAL]** | **0%** |

---

## How to Run

```bash
# Recommended workflow:
/build brownfield --skip-discovery

# Or start specific phase:
# ... Phase 1: Setup
# ... Phase 2: kraken implementation
```

---

## Session Termination

**Stop when:**
- ✅ All checkpoints pass
- ⏰ Duration exceeds [max_duration]
- 💰 Cost exceeds [max_cost]
- 🛑 Blocker requires user input
```

---

### 5.3 CONTINUITY ledger update

```markdown
# thoughts/ledgers/CONTINUITY_session.md

# Continuity Ledger - [Nazwa Projektu]

## Active Session

**Type:** Session-init v3.0
**Started:** [timestamp]
**Goal:** [cel]
**Status:** IN_PROGRESS

---

## Session Plan Reference

📋 **Full plan:** `thoughts/shared/handoffs/session-[timestamp].yaml`
📖 **Readable:** `thoughts/shared/plans/session-plan.md`

---

## Quick Stats

| Metric | Original | Enhanced |
|--------|----------|----------|
| Features | [N] | [M] ([X]x) |
| Checkpoints | [N] | [M] ([X]x) |

---

## Current Phase

**Phase:** [current phase name]
**Agent:** [current agent or null]
**Progress:** [done]/[total] checkpoints

### Active Checkpoints
- [→] [current checkpoint]
- [ ] [next checkpoint]
- [ ] [next checkpoint]

---

## Blockers

- [ ] [blocker 1] - [status]

---

## Decisions Made

| Decision | Rationale | Timestamp |
|----------|-----------|-----------|
| [decision] | [why] | [when] |

---

## Notes

[runtime notes]
```

---

## FAZA 6: WALIDACJA I POTWIERDZENIE

### 6.1 Walidacja przed zakończeniem

Sprawdź:
- [ ] Features enhanced: minimum 2x original
- [ ] Checkpoints enhanced: minimum 5x original
- [ ] Każda faza ma checkpointy
- [ ] Wszystkie blockers mają akcje
- [ ] Wszystkie risks mają mitigation
- [ ] Session termination criteria zdefiniowane

**Jeśli checkpoints < 5x original → uruchom agentów ponownie**

### 6.2 Pokaż podsumowanie

```
✅ Session-init Complete (v3.0 Dual Enhancement)

📊 Enhancement Stats:
┌─────────────────────────────────────────┐
│  Features:    [3] → [18]    (6x)        │
│  Checkpoints: [5] → [58]    (11.6x)     │
│  Risks:       [0] → [8]     identified  │
│  Blockers:    [N] identified            │
└─────────────────────────────────────────┘

🤖 Agents Consulted:
- oracle (best practices)
- architect (structure)
- arbiter (testing)
- sleuth (risks)
- scout (codebase)

📋 Generated Files:
- thoughts/shared/handoffs/session-[timestamp].yaml
- thoughts/shared/plans/session-plan.md
- thoughts/ledgers/CONTINUITY_session.md

─────────────────────────────────────────

🎯 Goal: [cel z wywiadu]

📈 Phases:
1. [→] Setup (~[czas])
2. [ ] Core Implementation (~[czas])
3. [ ] [Phase 3] (~[czas])
4. [ ] Testing (~[czas])
5. [ ] Finalize (~[czas])

⏱️ Session limits:
- Max duration: [czas]
- Max cost: [budżet]
- Stop signal: [sygnał]

🛑 Blockers to resolve:
- [blocker 1] - action: [action]

─────────────────────────────────────────

🚀 Ready to start!

Say:
- "implement plan" - start with implement_plan skill (recommended)
- "/build brownfield --skip-discovery" - alternative: direct build workflow
- "show plan" - view full session plan
- "show checkpoints" - view all checkpoints
- "resolve [blocker]" - mark blocker as resolved

💡 Implementation modes (auto-selected based on complexity):
- Mode 1 (Direct): 1-3 tasks - you implement directly
- Mode 2 (Handoffs): 4-9 tasks - agents with rich context transfer
- Mode 3 (Tasks): 10+ tasks - parallel agents with dependency management
```

---

## FAZA 7: AUTONOMIA - DECISION POINTS, ROLLBACK, HEARTBEAT

### 7.1 DECISION POINTS

```yaml
# ════════════════════════════════════════════════════════════
# DECISION POINTS - Kiedy pytać usera, kiedy decydować samemu
# ════════════════════════════════════════════════════════════

decision_points:
  # ─── KATEGORIA: ZAWSZE PYTAJ (DESTRUCTIVE) ───
  always_ask:
    - trigger: "git push (any branch)"
      escalate_to_user: true
      default_action: null  # STOP - czekaj na usera
      timeout: null         # bez timeout
      reason: "Zmiany nieodwracalne na remote"

    - trigger: "rm -rf / delete directory"
      escalate_to_user: true
      default_action: null
      timeout: null
      reason: "Utrata danych nieodwracalna"

    - trigger: "git reset --hard / checkout --force"
      escalate_to_user: true
      default_action: null
      timeout: null
      reason: "Utrata lokalnych zmian"

    - trigger: "database migration (production)"
      escalate_to_user: true
      default_action: null
      timeout: null
      reason: "Zmiany schematu nieodwracalne"

    - trigger: "external API calls (paid/rate-limited)"
      escalate_to_user: true
      default_action: "skip_and_mock"
      timeout: "5min"
      reason: "Potencjalny koszt/blokada"

    - trigger: "credentials/secrets modification"
      escalate_to_user: true
      default_action: null
      timeout: null
      reason: "Security critical"

    - trigger: "architecture change (new pattern/tech)"
      escalate_to_user: true
      default_action: null
      timeout: "10min"
      reason: "Strategiczna decyzja"

    - trigger: "scope expansion (>20% more work)"
      escalate_to_user: true
      default_action: "defer_to_v2"
      timeout: "10min"
      reason: "Może przekroczyć budżet"

  # ─── KATEGORIA: PYTAJ JEŚLI CZAS POZWALA ───
  ask_if_available:
    - trigger: "test failure (>3 attempts to fix)"
      escalate_to_user: true
      default_action: "mark_as_known_issue_and_continue"
      timeout: "5min"
      reason: "Może być bug w spec lub edge case"

    - trigger: "dependency conflict"
      escalate_to_user: true
      default_action: "use_compatible_version"
      timeout: "3min"
      reason: "User może preferować inną wersję"

    - trigger: "ambiguous requirement"
      escalate_to_user: true
      default_action: "choose_safer_interpretation"
      timeout: "5min"
      reason: "Interpretacja może być błędna"

    - trigger: "performance tradeoff"
      escalate_to_user: true
      default_action: "choose_simpler_solution"
      timeout: "3min"
      reason: "User może preferować inny tradeoff"

    - trigger: "API design choice (multiple valid options)"
      escalate_to_user: true
      default_action: "follow_existing_patterns"
      timeout: "3min"
      reason: "Consistency preference"

    - trigger: "feature partially complete at time limit"
      escalate_to_user: true
      default_action: "commit_partial_with_TODO"
      timeout: "5min"
      reason: "User decyduje: kontynuować czy kończyć"

  # ─── KATEGORIA: NIGDY NIE PYTAJ (TRIVIAL) ───
  never_ask:
    - trigger: "code formatting"
      escalate_to_user: false
      action: "auto_format_on_save"
      reason: "Deterministic, reversible"

    - trigger: "import ordering"
      escalate_to_user: false
      action: "follow_project_convention"
      reason: "Trivial, deterministic"

    - trigger: "variable naming (within convention)"
      escalate_to_user: false
      action: "use_descriptive_name"
      reason: "Reversible, low impact"

    - trigger: "adding type hints"
      escalate_to_user: false
      action: "add_comprehensive_types"
      reason: "Improves quality, reversible"

    - trigger: "adding docstrings"
      escalate_to_user: false
      action: "add_comprehensive_docs"
      reason: "Improves quality, reversible"

    - trigger: "error message wording"
      escalate_to_user: false
      action: "use_descriptive_message"
      reason: "Reversible, low impact"

    - trigger: "test file location"
      escalate_to_user: false
      action: "follow_project_convention"
      reason: "Deterministic pattern"

    - trigger: "git commit (local)"
      escalate_to_user: false
      action: "commit_with_descriptive_message"
      reason: "Local, reversible, enables rollback"

    - trigger: "creating backup/snapshot"
      escalate_to_user: false
      action: "create_snapshot"
      reason: "Only adds safety"

    - trigger: "reading files"
      escalate_to_user: false
      action: "read"
      reason: "No side effects"

    - trigger: "running tests"
      escalate_to_user: false
      action: "run_tests"
      reason: "No side effects (usually)"

  # ─── KATEGORIA: AUTONOMICZNE DECYZJE (SAFE) ───
  autonomous_safe:
    - trigger: "refactoring (preserves behavior)"
      escalate_to_user: false
      action: "refactor_with_tests"
      guard: "tests must pass before and after"
      reason: "Behavior preserved, testable"

    - trigger: "adding logging"
      escalate_to_user: false
      action: "add_structured_logging"
      guard: "log levels appropriate"
      reason: "Observable improvement"

    - trigger: "adding error handling"
      escalate_to_user: false
      action: "add_defensive_code"
      guard: "don't swallow errors"
      reason: "Improves robustness"

    - trigger: "fixing lint warnings"
      escalate_to_user: false
      action: "fix_lints"
      guard: "no semantic changes"
      reason: "Code quality improvement"

    - trigger: "optimizing imports"
      escalate_to_user: false
      action: "optimize"
      guard: "no circular imports introduced"
      reason: "Deterministic improvement"
```

### 7.2 ROLLBACK STRATEGY

```yaml
# ════════════════════════════════════════════════════════════
# ROLLBACK STRATEGY - Bezpieczne punkty powrotu
# ════════════════════════════════════════════════════════════

rollback:
  # ─── SNAPSHOT POLICY ───
  snapshot:
    frequency: "per_phase"
    method: "git_tag"
    naming: "session-{session_id}-phase-{phase_num}-{timestamp}"
    additional_backups:
      - on: "before_risky_operation"
        method: "git_stash"
      - on: "before_migration"
        method: "database_dump"
      - on: "every_30min"
        method: "git_commit"
        message: "checkpoint: {current_task}"

  # ─── SNAPSHOT COMMANDS ───
  commands:
    create_phase_snapshot: |
      git add -A
      git commit -m "SNAPSHOT: Phase {phase} complete - {summary}"
      git tag -a "session-{id}-phase-{n}" -m "Rollback point: {description}"

    create_time_snapshot: |
      git add -A
      git commit -m "CHECKPOINT: {timestamp} - {current_task}"

    create_risky_snapshot: |
      git stash push -m "RISKY_OP_BACKUP: {operation} at {timestamp}"

  # ─── ROLLBACK TRIGGERS ───
  rollback_triggers:
    immediate:
      - trigger: "tests fail after >5 fix attempts"
        action: "rollback_to_last_green"
        target: "last passing test commit"
        notify: true

      - trigger: "critical error (crash, data loss)"
        action: "rollback_to_phase_start"
        target: "phase snapshot tag"
        notify: true

      - trigger: "user requests rollback"
        action: "rollback_to_specified"
        target: "user-specified point"
        notify: true

    conditional:
      - trigger: "feature breaks existing functionality"
        action: "isolate_and_flag"
        condition: "regression detected"
        target: "pre-feature commit"
        notify: true

      - trigger: "time/cost limit approaching (80%)"
        action: "consolidate_progress"
        condition: "incomplete feature"
        target: "create clean checkpoint"
        notify: true

      - trigger: "dependency installation fails"
        action: "restore_package_lock"
        target: "last working package-lock.json"
        notify: false

  # ─── ROLLBACK EXECUTION ───
  execution:
    rollback_to_tag: |
      # Save current state first
      git stash push -m "PRE_ROLLBACK: {reason}"
      # Rollback
      git checkout {tag}
      # Create new branch for recovery
      git checkout -b recovery-{timestamp}

    rollback_to_commit: |
      git stash push -m "PRE_ROLLBACK: {reason}"
      git reset --soft {commit}
      # Preserve changes in working directory

    rollback_from_stash: |
      git stash pop

  # ─── ROLLBACK VERIFICATION ───
  verification:
    after_rollback:
      - "run tests"
      - "verify app starts"
      - "check critical paths"
      - "update heartbeat with rollback info"

  # ─── RECOVERY FROM FAILED ROLLBACK ───
  recovery:
    if_rollback_fails:
      - "notify user immediately"
      - "preserve all stashes"
      - "document state in heartbeat"
      - "await user guidance"
```

### 7.3 PROGRESS PERSISTENCE (HEARTBEAT)

```yaml
# ════════════════════════════════════════════════════════════
# HEARTBEAT - Progress persistence dla resume
# ════════════════════════════════════════════════════════════

heartbeat:
  frequency: "5min"
  persist_to: "thoughts/ledgers/HEARTBEAT_session.yaml"
  backup_to: ".claude/session-heartbeat.yaml"

  # ─── HEARTBEAT CONTENT ───
  content:
    meta:
      session_id: "{session_id}"
      started: "{start_timestamp}"
      last_heartbeat: "{current_timestamp}"
      version: "3.0"

    progress:
      current_phase: "{phase_name}"
      current_phase_num: "{phase_num}/{total_phases}"
      current_checkpoint: "{checkpoint_id}"
      current_task: "{task_description}"

      completed:
        phases: ["{phase1}", "{phase2}"]
        checkpoints: ["{cp1}", "{cp2}", "..."]
        features: ["{F1}", "{F2}"]

      pending:
        phases: ["{phase_n}", "..."]
        checkpoints: ["{cp_x}", "..."]
        blockers: ["{blocker1}"]

    metrics:
      checkpoints_done: "{n}/{total}"
      checkpoints_percent: "{percent}%"
      features_done: "{n}/{total}"
      tests_passing: "{n}/{total}"
      estimated_remaining: "{time}"

    resources:
      tokens_used: "{tokens}"
      tokens_estimate_remaining: "{tokens}"
      cost_estimate: "${amount}"
      cost_remaining_budget: "${amount}"
      elapsed_time: "{duration}"
      remaining_time: "{duration}"

    state:
      last_successful_operation: "{operation}"
      last_git_commit: "{sha}"
      last_snapshot_tag: "{tag}"
      working_files: ["{file1}", "{file2}"]
      modified_since_snapshot: ["{file1}"]

    decisions:
      - timestamp: "{ts}"
        decision: "{what}"
        rationale: "{why}"
        autonomous: true|false

    errors:
      - timestamp: "{ts}"
        error: "{description}"
        resolution: "{how_fixed}"
        attempts: "{n}"

    notes:
      - "{runtime_observation}"

  # ─── HEARTBEAT UPDATE TEMPLATE ───
  update_template: |
    # thoughts/ledgers/HEARTBEAT_session.yaml
    # Auto-updated every 5 min by session-init v3.0

    meta:
      session_id: "{SESSION_ID}"
      started: "{START_TIME}"
      last_heartbeat: "{NOW}"
      version: "3.0"

    progress:
      current_phase: "{PHASE_NAME}"
      current_phase_num: {PHASE_NUM}/{TOTAL_PHASES}
      current_checkpoint: "{CHECKPOINT_ID}"
      current_task: "{TASK_DESC}"

      completed:
        phases: {COMPLETED_PHASES}
        checkpoints: {COMPLETED_CPS}

      pending:
        phases: {PENDING_PHASES}
        checkpoints: {PENDING_CPS}

    metrics:
      checkpoints_done: {CP_DONE}/{CP_TOTAL}
      checkpoints_percent: {CP_PERCENT}%
      elapsed_time: "{ELAPSED}"
      estimated_remaining: "{REMAINING}"

    resources:
      tokens_used: {TOKENS}
      cost_estimate: ${COST}

    state:
      last_successful_operation: "{LAST_OP}"
      last_git_commit: "{LAST_COMMIT}"
      last_snapshot_tag: "{LAST_TAG}"

  # ─── HEARTBEAT TRIGGERS ───
  triggers:
    update_on:
      - "every 5 minutes"
      - "phase completion"
      - "checkpoint completion"
      - "error occurrence"
      - "decision made"
      - "rollback performed"
      - "user interaction"

  # ─── RESUME FROM HEARTBEAT ───
  resume:
    on_session_start:
      - "check for existing heartbeat"
      - "if exists and recent (<1h): offer resume"
      - "if exists and old (>1h): offer fresh start or resume"
      - "if not exists: start fresh"

    resume_procedure: |
      1. Read heartbeat file
      2. Restore context from last state
      3. Checkout last_snapshot_tag or last_git_commit
      4. Review pending checkpoints
      5. Continue from current_checkpoint
      6. Update heartbeat with resume info

    resume_message: |
      Found session heartbeat from {last_heartbeat}.

      Progress: {checkpoints_done}/{checkpoints_total} ({percent}%)
      Phase: {current_phase} ({phase_num}/{total_phases})
      Last task: {current_task}

      Options:
      A) Resume from checkpoint {current_checkpoint}
      B) Resume from phase start (Phase {phase_num})
      C) Start fresh (archive current progress)
```

### 7.4 CONFLICT RESOLUTION (AUTONOMOUS)

```yaml
# ════════════════════════════════════════════════════════════
# CONFLICT RESOLUTION - Autonomiczne decyzje bez usera
# ════════════════════════════════════════════════════════════

conflict_resolution:
  # ─── AGENT VS AGENT CONFLICTS ───
  agent_priority:
    # Gdy agenci proponują sprzeczne rozwiązania
    priority_order:
      1: security    # Security zawsze wygrywa
      2: arbiter     # Test requirements second
      3: architect   # Architecture third
      4: oracle      # Best practices fourth
      5: sleuth      # Risks fifth
      6: scout       # Codebase analysis last

    resolution_rules:
      - conflict: "security vs performance"
        winner: "security"
        rationale: "Security first, optimize later"

      - conflict: "new pattern vs existing convention"
        winner: "existing convention"
        rationale: "Consistency over novelty"

      - conflict: "simple vs comprehensive"
        winner: "simple"
        condition: "if MVP, otherwise comprehensive"
        rationale: "MVP = minimum viable"

      - conflict: "speed vs quality"
        winner: "quality"
        condition: "unless user specified time priority"
        rationale: "Technical debt is expensive"

  # ─── AMBIGUOUS SITUATIONS ───
  ambiguous_handling:
    general_principle: "choose_safer_option"

    rules:
      - situation: "unclear if feature needed"
        action: "implement minimal version"
        rationale: "Can extend later, hard to remove"

      - situation: "unclear error handling"
        action: "fail loudly with good error message"
        rationale: "Silent failures are worse"

      - situation: "unclear data validation"
        action: "validate strictly"
        rationale: "Garbage in, garbage out"

      - situation: "unclear API response format"
        action: "follow existing patterns in codebase"
        rationale: "Consistency"

      - situation: "unclear test coverage needed"
        action: "err on side of more tests"
        rationale: "Tests are documentation"

      - situation: "unclear if refactor needed"
        action: "refactor if improves readability"
        condition: "and tests exist"
        rationale: "Readable code is maintainable"

  # ─── RESOURCE CONFLICTS ───
  resource_handling:
    time_pressure:
      - condition: "remaining_time < estimated_for_feature"
        action: "implement core, defer nice-to-have"
        notify: "add to heartbeat notes"

      - condition: "remaining_time < 30min"
        action: "stop new features, consolidate"
        notify: "update heartbeat, prepare handoff"

    cost_pressure:
      - condition: "cost > 80% budget"
        action: "notify user, await guidance"
        default_if_no_response: "consolidate and stop"

      - condition: "cost > 95% budget"
        action: "immediate graceful stop"
        notify: "create handoff document"

  # ─── MERGE STRATEGY ───
  merge_strategy:
    when_combining_agent_outputs:
      features:
        - "deduplicate by semantic similarity"
        - "keep highest priority version"
        - "preserve all unique rationales"

      checkpoints:
        - "union of all unique checkpoints"
        - "group by feature/phase"
        - "remove exact duplicates"

      risks:
        - "union of all identified risks"
        - "if same risk, keep higher severity"
        - "combine mitigations"

  # ─── ESCALATION MATRIX ───
  escalation:
    level_1_auto_resolve:
      - "formatting conflicts"
      - "naming conventions"
      - "import order"
      - "comment style"

    level_2_log_and_continue:
      - "minor test flakiness"
      - "non-critical warnings"
      - "optional dependencies missing"

    level_3_ask_if_time:
      - "design pattern choice"
      - "API naming"
      - "feature interpretation"
      timeout: "5min"
      default: "safer option"

    level_4_must_ask:
      - "architectural decisions"
      - "scope changes"
      - "external service integration"
      - "data model changes"
      timeout: null
      default: null  # wait
```

### 7.5 SESSION YAML EXTENSION

Dodaj do generowanego `session-YYYY-MM-DD-HHMM.yaml`:

```yaml
# ════════════════════════════════════════════════════════════
# AUTONOMY CONFIG (add to session yaml)
# ════════════════════════════════════════════════════════════

autonomy:
  decision_mode: "balanced"  # aggressive | balanced | conservative

  escalation:
    destructive_ops: "always_ask"
    architecture_changes: "always_ask"
    scope_expansion: "ask_with_timeout"
    ambiguous_requirements: "ask_with_timeout"
    trivial_decisions: "auto"

  rollback:
    enabled: true
    snapshot_frequency: "per_phase"
    auto_rollback_on:
      - "test_failure_threshold: 5"
      - "critical_error"
    preserve_stashes: true

  heartbeat:
    enabled: true
    frequency_minutes: 5
    persist_to: "thoughts/ledgers/HEARTBEAT_session.yaml"
    include:
      - progress
      - metrics
      - resources
      - decisions
      - errors

  termination:
    graceful_on:
      - "time_limit_reached"
      - "cost_limit_reached"
      - "user_signal"
    immediate_on:
      - "critical_error"
      - "security_issue"
    create_handoff: true

  conflict_resolution:
    agent_priority: [security, arbiter, architect, oracle, sleuth, scout]
    ambiguous_default: "safer_option"
    merge_strategy: "union_with_dedup"
```

---

## FAZA 8: SECURITY CONSTRAINTS

### 8.1 HARD LIMITS (nieprzekraczalne)

```yaml
security:
  hard_limits:
    max_duration_hours: 12       # absolutne maksimum
    max_cost_usd: 100            # absolutne maksimum
    max_file_operations: 500     # create + modify + delete
    max_files_per_commit: 50     # zabezpieczenie przed masowymi commitami
    max_agent_spawns: 100        # limit delegacji
```

### 8.2 PATH RESTRICTIONS

```yaml
path_restrictions:
  allowed_bases:
    - "${PROJECT_ROOT}"
    - "${PROJECT_ROOT}/thoughts"
    - "${PROJECT_ROOT}/.claude"

  blocked_patterns:
    - ".*\\.env$"                # pliki .env
    - ".*/\\.git/config$"        # git credentials
    - ".*\\.pem$"                # klucze prywatne
    - ".*\\.key$"
    - ".*id_rsa.*"
    - ".*/\\.npmrc$"             # npm tokens

  allowed_exceptions:
    - "${PROJECT_ROOT}/.env.example"
```

### 8.3 DANGEROUS OPERATIONS

```yaml
dangerous_operations:
  always_confirm:
    - action: "delete"
      patterns: ["rm", "rm -rf"]
    - action: "git push"
    - action: "git reset --hard"
    - action: "database migration"
    - action: "modify credentials"
    - action: "deploy"

  never_autonomous:
    - "Push to main/master"
    - "Force push"
    - "Delete remote branches"
    - "npm publish / pypi upload"
    - "Deploy to production"
    - "Modify system config"
    - "Operations requiring sudo"
```

### 8.4 AUDIT LOGGING

```yaml
audit:
  enabled: true
  location: "thoughts/audit/session-{SESSION_ID}.log"

  events:
    - session_start
    - session_end
    - agent_spawn
    - checkpoint_complete
    - file_modified
    - dangerous_operation
    - limit_warning
    - security_block
    - error

  format: "{timestamp} | {event_type} | {actor} | {action} | {result}"
```

### 8.5 GITIGNORE ADDITIONS

Automatycznie dodaj do `.gitignore`:
```
# Session-init security
thoughts/audit/*.log
.claude/session-*.yaml
.env
.env.local
*.pem
*.key
```

---

## FAZA 9: RECOVERY PROTOCOL

### 9.1 CHECKPOINT DEFINITION SCHEMA

Nowy format checkpointu (zastępuje `"[ ] text"`):

```yaml
checkpoint:
  id: "CP-{PHASE}-{NUM}"
  description: "Unit tests pass"

  verification:
    type: command          # command | assertion | file_check | manual
    command: "npm test"
    expected:
      exit_code: 0
      stdout_contains: "passing"

  on_failure:
    action: retry          # retry | skip | halt | fallback
    max_retries: 3
    fallback:
      action: "npm test -- --updateSnapshot"

  priority: must_pass      # must_pass | should_pass | nice_to_pass
  timeout: "60s"
  dependencies: ["CP-SETUP-01"]
```

### 9.2 ERROR CLASSIFICATION

```yaml
error_classification:
  fatal:
    - "Missing credentials"
    - "Security breach detected"
    - "Data corruption"
    action: HALT_IMMEDIATELY

  recoverable:
    - "Network timeout"
    - "Test flake"
    - "Rate limiting"
    action: RETRY_WITH_BACKOFF
    max_retries: 3

  skippable:
    - "Optional feature failed"
    - "Nice-to-have checkpoint"
    action: SKIP_WITH_WARNING
```

### 9.3 RECOVERY PROCEDURE

```yaml
recovery:
  on_checkpoint_failure:
    1: "Log failure with context"
    2: "Check if error is recoverable"
    3: "If recoverable: retry with backoff"
    4: "If retries exhausted: check fallback"
    5: "If no fallback: escalate or skip"
    6: "Update heartbeat with failure info"

  on_session_crash:
    resume_from: "last_completed_checkpoint"
    state_file: "thoughts/ledgers/HEARTBEAT_session.yaml"
    procedure:
      1: "Read heartbeat file"
      2: "Checkout last_snapshot_tag"
      3: "Continue from current_checkpoint"

  on_limit_reached:
    action: "graceful_shutdown"
    steps:
      - "Complete current atomic operation"
      - "Create checkpoint"
      - "Update heartbeat"
      - "Generate handoff"
```

### 9.4 CHECKPOINT EXAMPLES

```yaml
# Unit tests pass
- id: CP-TEST-01
  description: "All unit tests pass"
  verification:
    type: command
    command: "npm test -- --coverage"
    expected:
      exit_code: 0
      stdout_contains: "All tests passed"
  on_failure:
    action: retry
    max_retries: 2
  priority: must_pass

# Build succeeds
- id: CP-BUILD-01
  description: "Project builds without errors"
  verification:
    type: command
    command: "npm run build"
    expected:
      exit_code: 0
  on_failure:
    action: halt
  priority: must_pass

# API responds
- id: CP-API-01
  description: "Health endpoint responds"
  verification:
    type: command
    command: "curl -s http://localhost:3000/health"
    expected:
      stdout_contains: "ok"
  on_failure:
    action: retry
    max_retries: 5
  priority: must_pass

# File exists
- id: CP-FILE-01
  description: "Auth service file created"
  verification:
    type: file_check
    path: "src/services/auth.ts"
    checks:
      - exists: true
      - contains: "class AuthService"
  on_failure:
    action: halt
  priority: must_pass
```

---

## WSKAZÓWKI IMPLEMENTACYJNE

### Wywiad:
- **MINIMUM 10 rund** - nie kończ wcześniej
- **Pytaj o sesję** - czas, budżet, termination (nowe!)
- **Zapisuj WSZYSTKO** - kontekst dla agentów

### Delegacja (Wave-based v3.1):
- **Wave 1:** oracle, scout, sleuth (równolegle) - zbieranie danych
- **Wave 2:** architect, security (po Wave 1) - design z kontekstem
- **Wave 3:** arbiter (po Wave 2) - testing z architekturą
- **Timeout** - 3min per wave, kontynuuj z partial results
- **Merge** - agreguj wyniki, resolve conflicts według priority

### Enhancement targets:
- **Features:** minimum 2x, target 5-6x
- **Checkpoints:** minimum 5x, target 10-15x
- **Każda feature:** minimum 5 checkpointów

### Output:
- **YAML** - główny format (token-efficient, CCv3 compatible)
- **Markdown** - human-readable companion
- **Ledger** - dla CCv3 resume

### Priorytety:
- 🔴 **MUST HAVE** - blokuje release
- 🟡 **SHOULD HAVE** - ważne dla v1.0
- 🟢 **NICE TO HAVE** - może poczekać na v2

### Autonomia (v3.0+):
- **Heartbeat co 5 min** - persist progress do YAML
- **Rollback per-phase** - git tag jako snapshot
- **Decision matrix** - 4 kategorie (always_ask / ask_if_time / never_ask / auto_safe)
- **Conflict resolution** - agent priority + safer option default

### Quick Reference - Decision Points:

| Kategoria | Przykłady | Akcja |
|-----------|-----------|-------|
| ALWAYS_ASK | git push, rm -rf, migrations, credentials | STOP, czekaj |
| ASK_IF_TIME | test failures >3x, ambiguous req, scope creep | timeout 5min, default action |
| NEVER_ASK | formatting, imports, docstrings, local commits | auto |
| AUTO_SAFE | refactoring (with tests), logging, error handling | auto z guardem |

### Quick Reference - Rollback:

| Trigger | Target | Action |
|---------|--------|--------|
| Tests fail >5x | last green commit | auto rollback |
| Critical error | phase snapshot | auto rollback |
| 80% time/cost | current state | consolidate |
| User request | specified point | manual rollback |

---

## LEKCJE Z v4.0 → v4.1 (Krytyczne!)

### ⚠️ DLACZEGO FactoryMap (i podobne projekty) ZAWIODŁY

**Root cause:** Arbitralne wartości liczbowe bez specyfikacji.

```yaml
# CO POSZŁO ŹLE:
plan_v1:
  BUILDING_SPACING: 4.5   # ← SKĄD TA WARTOŚĆ?
  CAMERA_FRUSTUM: 30      # ← I TA?
  # Brak źródła → wartości były złe → elementy się nakładały

# CO POWINNO BYĆ:
plan_v4_1:
  BUILDING_SPACING:
    value: 60
    source: "user_provided"
    rationale: "User: elementy 20x dalej od siebie"
  CAMERA_FRUSTUM:
    value: 200
    source: "derived"
    rationale: "5x5 grid * 60 spacing = 300, frustum 200 z marginesem"
```

### Quick Reference - Design Values:

| Sytuacja | Akcja |
|----------|-------|
| User podał wartości | Użyj dokładnie |
| Jest mockup | Zmierz z mockupu |
| Jest istniejący kod | Zachowaj spójność |
| Brak specyfikacji | **ZAPYTAJ USERA** - nie zgaduj! |

### Quick Reference - Co AI może/nie może:

| AI MOŻE | AI NIE MOŻE |
|---------|-------------|
| Sprawdzić czy element istnieje | Ocenić czy "wygląda dobrze" |
| Zmierzyć pozycję/rozmiar | Wiedzieć czy jest "za blisko" (bez spec) |
| Porównać z mockupem | Wymyślić prawidłowy layout |
| Wykryć błędy konsoli | Zastąpić eye-test użytkownika |

### Quick Reference - Visual Validation Tiers:

| Tier | Co | AI może? | Przykład |
|------|-----|----------|----------|
| 1 | Health | ✅ TAK | "brak błędów konsoli" |
| 2 | Presence | ✅ TAK | "element z id='app' istnieje" |
| 3 | Measurable | ✅ TAK | "button.width >= 100px" |
| 4 | Comparison | ⚠️ PARTIAL | "screenshot vs mockup" (wymaga mockupu) |
| 5 | Aesthetic | ❌ NIE | "czy to wygląda profesjonalnie" |

### Checklist dla UI/Canvas projektów:

```markdown
PRZED IMPLEMENTACJĄ:
- [ ] Czy user dostarczył mockup/wireframe?
- [ ] Jeśli nie - czy user zatwierdził zaproponowane wartości?
- [ ] Czy wszystkie wartości liczbowe mają źródło?
- [ ] Czy Definition of Done zawiera MEASURABLE criteria?

PODCZAS IMPLEMENTACJI:
- [ ] Każda wartość layout ma komentarz ze źródłem
- [ ] Po każdej fazie - screenshot do review
- [ ] Sprawdzanie health (błędy, obecność) jest automatyczne
- [ ] Sprawdzanie estetyki wymaga human review

PO IMPLEMENTACJI:
- [ ] User potwierdził wizualnie że layout jest OK
- [ ] Wszystkie health checks przeszły
- [ ] Screenshoty zapisane dla dokumentacji
```
