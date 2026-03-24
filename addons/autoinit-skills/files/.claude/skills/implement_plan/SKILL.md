---
name: implement_plan
description: Implementacja planów technicznych z thoughts/shared/plans z śledzeniem postępu przez Tasks i weryfikacją
version: "2.2"
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion
---

# Implement Plan v2.2

## ⚠️ AUTONOMY RULES (COMPACTION-RESISTANT)

**Ta sekcja przetrwa kompakcję kontekstu - ZAWSZE jej przestrzegaj.**

| ❌ NIGDY nie pytaj | ✅ ZAMIAST tego |
|-------------------|-----------------|
| "Czy kontynuować?" | Kontynuuj automatycznie |
| "Pozostało X tasków, czy mam dalej?" | Implementuj wszystkie taski |
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
│  Po przeczytaniu planu, NATYCHMIAST uruchom TaskCreate      │
│  dla każdej fazy. DOPIERO POTEM zacznij implementację.      │
│                                                             │
│  ❌ ZABRONIONE: Implementacja bez utworzenia Tasks          │
│  ❌ ZABRONIONE: "Zrobię Tasks później"                      │
│  ❌ ZABRONIONE: "Plan ma tylko 3 fazy, nie potrzebuję"      │
│                                                             │
│  ✅ WYMAGANE: TaskCreate → TaskUpdate → implementacja       │
└─────────────────────────────────────────────────────────────┘
```

**Tasks przetrwają kompakcję kontekstu - bez nich zgubisz postęp.**

### Na starcie implement_plan (NATYCHMIAST):
```
1. Przeczytaj plan z thoughts/shared/plans/
2. TaskCreate dla KAŻDEJ fazy/tasku z planu:
   - subject: "Phase 1: [nazwa]"
   - description: [kryteria sukcesu z planu]
   - activeForm: "Implementing Phase 1"
3. Ustaw zależności: TaskUpdate addBlockedBy dla sekwencyjnych faz
```

### Podczas implementacji:
```
1. TaskUpdate status="in_progress" - gdy zaczynasz fazę
2. Implementuj zmiany z planu
3. Sprawdź kryteria sukcesu
4. TaskUpdate status="completed" - gdy faza ukończona
5. Przejdź do następnego pending task
```

### Po kompakcji kontekstu:
```
Jeśli nie pamiętasz gdzie byłeś:
1. TaskList - zobacz które fazy są pending
2. Read plan file dla kontekstu
3. Kontynuuj od pierwszego pending task
```

### Przykład dla planu z 5 fazami:
```
TaskCreate: "Phase 1: Setup database schema"
TaskCreate: "Phase 2: Implement API endpoints" (blockedBy: Phase 1)
TaskCreate: "Phase 3: Add authentication" (blockedBy: Phase 2)
TaskCreate: "Phase 4: Write tests" (blockedBy: Phase 3)
TaskCreate: "Phase 5: Documentation" (blockedBy: Phase 4)
```

---

## 🚨 EXECUTION GATES (WYMUSZONE KROKI)

**Te kroki są OBOWIĄZKOWE. Nie możesz ich pominąć.**

### GATE 1: Przed jakąkolwiek implementacją

Po przeczytaniu planu, ZANIM zaczniesz cokolwiek implementować:

1. Wywołaj `TaskList()`
2. Sprawdź: czy są już utworzone taski dla tego planu?

**CHECK:**
- Brak tasków → STOP! Wróć do sekcji "Na starcie implement_plan" i utwórz taski.
- Taski istnieją → Przejdź do implementacji.

### GATE 2: Checkpoint co 3 fazy

Po ukończeniu każdych 3 faz:

1. Wywołaj `TaskList()`
2. Wyświetl: `"Progress: X/Y phases completed"`
3. Kontynuuj automatycznie (NIE PYTAJ usera!)

### GATE 3: Przed zakończeniem

**ZANIM napiszesz "implementacja zakończona" lub "wszystko gotowe":**

1. Wywołaj `TaskList()`
2. Sprawdź: `pending > 0`?

**CHECK:**
- pending > 0 → **NIE MOŻESZ ZAKOŃCZYĆ**. Wróć do pierwszego pending taska.
- pending == 0 → Możesz wyświetlić summary.

---

Twoim zadaniem jest implementacja zatwierdzonego planu technicznego z `thoughts/shared/plans/`. Plany zawierają fazy ze zmianami i kryteriami sukcesu.

## Tryby Wykonania

Masz trzy tryby wykonania:

### Tryb 1: Implementacja Bezpośrednia (domyślny dla małych planów)
Dla małych planów (3 lub mniej tasków) lub gdy user prosi o bezpośrednią implementację.
- Sam implementujesz każdą fazę
- Kontekst akumuluje się w głównej konwersacji
- Używaj dla szybkich, skupionych implementacji

### Tryb 2: Orkiestracja Agentów z Handoffami (architektura CCv3)
Dla planów z 4+ taskami lub gdy zachowanie kontekstu jest krytyczne.
- Działasz jako thin orchestrator
- Agenci wykonują każdy task i tworzą **handoffy** (szczegółowe pliki kontekstu)
- Odporne na kompakcję: handoffy przetrwają nawet jeśli kontekst się skompaktuje
- Używaj dla wielofazowych implementacji wymagających bogatego transferu kontekstu

### Tryb 3: Równoległa Orkiestracja z Tasks ⭐ NOWY
Dla dużych planów (10+ tasków) lub pracy wielodomenowej wymagającej równoległego wykonania.
- Używa CCv3 **Tasks** do zarządzania zależnościami
- **Owner-based discovery** - agenci sami znajdują swoje taski
- **Równoległe spawnowanie** - wielu agentów pracuje jednocześnie
- **Auto-unblock** - ukończone taski automatycznie odblokowują zależne
- Łączy się z handoffami dla bogatego kontekstu

**Rekomendacja:**
- Małe (1-3 tasków): Tryb 1
- Średnie (4-9 tasków): Tryb 2
- Duże (10+ tasków) lub praca równoległa: Tryb 3

---

## Getting Started

When given a plan path:
- Read the plan completely and check for any existing checkmarks (- [x])
- Read the original ticket and all files mentioned in the plan
- **Read files fully** - never use limit/offset parameters, you need complete context
- Think deeply about how the pieces fit together
- Create a todo list to track your progress

### Pre-Implementation Risk Check

Before starting implementation, run a deep pre-mortem:

```
/premortem deep <plan-path>
```

**Skip premortem if:**
- Plan already has a "## Risks (Pre-Mortem)" section with mitigations
- User explicitly requests to skip (`--skip-premortem`)

After premortem passes, start implementing if you understand what needs to be done.

If no plan path provided, ask for one.

---

## Implementation Philosophy

Plans are carefully designed, but reality can be messy. Your job is to:
- Follow the plan's intent while adapting to what you find
- Implement each phase fully before moving to the next
- Verify your work makes sense in the broader codebase context
- Update checkboxes in the plan as you complete sections

When things don't match the plan exactly, think about why and communicate clearly. The plan is your guide, but your judgment matters too.

If you encounter a mismatch:
- STOP and think deeply about why the plan can't be followed
- Present the issue clearly:
  ```
  Issue in Phase [N]:
  Expected: [what the plan says]
  Found: [actual situation]
  Why this matters: [explanation]

  How should I proceed?
  ```

---

## Verification Approach

After implementing a phase:
- Run the success criteria checks (usually `make check test` covers everything)
- Fix any issues before proceeding
- Update your progress in both the plan and your todos
- Check off completed items in the plan file itself using Edit
- **Pause for human verification**: After completing all automated verification for a phase:
  ```
  Phase [N] Complete - Ready for Manual Verification

  Automated verification passed:
  - [List automated checks that passed]

  Please perform the manual verification steps listed in the plan:
  - [List manual verification items from the plan]

  Let me know when manual testing is complete so I can proceed to Phase [N+1].
  ```

If instructed to execute multiple phases consecutively, skip the pause until the last phase.

---

## If You Get Stuck

When something isn't working as expected:
- First, make sure you've read and understood all the relevant code
- Consider if the codebase has evolved since the plan was written
- Present the mismatch clearly and ask for guidance

Use sub-tasks sparingly - mainly for targeted debugging or exploring unfamiliar territory.

---

## Resumable Agents

If the plan was created by `plan-agent`, you may be able to resume it for clarification:

1. Check `.claude/cache/agents/agent-log.jsonl` for the plan-agent entry
2. Look for the `agentId` field
3. To clarify or update the plan:
   ```
   Task(
     resume="<agentId>",
     prompt="Phase 2 isn't matching the codebase. Can you clarify..."
   )
   ```

The resumed agent retains its full prior context (research, codebase analysis).

Available agents to resume:
- `plan-agent` - Created the implementation plan
- `oracle` - Researched best practices
- `debug-agent` - Investigated issues

---

## Resuming Work

If the plan has existing checkmarks:
- Trust that completed work is done
- Pick up from the first unchecked item
- Verify previous work only if something seems off

Remember: You're implementing a solution, not just checking boxes. Keep the end goal in mind and maintain forward momentum.

---

# MODE 2: Agent Orchestration with Handoffs

When implementing larger plans (4+ tasks), use agent orchestration to stay compaction-resistant.

## Why Agent Orchestration?

**The Problem:** During long implementations, context accumulates. If auto-compact triggers mid-task, you lose implementation context. Handoffs created at 80% context become stale.

**The Solution:** Delegate implementation to agents. Each agent:
- Starts with fresh context
- Implements one task
- Creates a handoff on completion
- Returns to orchestrator

Handoffs persist on disk. If compaction happens, you re-read handoffs and continue.

## Setup

1. **Create handoff directory:**
   ```bash
   mkdir -p thoughts/handoffs/<session-name>
   ```
   Use the session name from your continuity ledger.

2. **Read the implementation agent skill:**
   ```bash
   cat .claude/skills/implement_task/SKILL.md
   ```
   This defines how agents should behave.

## Pre-Requisite: Plan Validation

> **Note:** `validate-agent` and `implement_task` are CCv3 external skills located in `~/.claude/skills/`.
> They are not part of this AutoInit repository but are expected to exist in the global CCv3 setup.

Before implementing, ensure the plan has been validated using the `validate-agent`. The validation step is separate and should have created a handoff with status VALIDATED.

**Check for validation handoff:**
```bash
ls thoughts/handoffs/<session>/validation-*.md
```

If no validation exists, suggest running validation first:
```
"This plan hasn't been validated yet. Would you like me to spawn validate-agent first?"
```

If validation exists but status is NEEDS REVIEW, present the issues before proceeding.

## Orchestration Loop

For each task in the plan:

1. **Prepare agent context:**
   - Read continuity ledger (current state)
   - Read the plan (overall context)
   - Read previous handoff if exists (from thoughts/handoffs/<session>/)
   - Identify the specific task

2. **Spawn implementation agent:**
   ```
   Task(
     subagent_type="general-purpose",
     model="sonnet",
     prompt="""
     [Paste contents of .claude/skills/implement_task/SKILL.md here]

     ---

     ## Your Context

     ### Continuity Ledger:
     [Paste ledger content]

     ### Plan:
     [Paste relevant plan section or full plan]

     ### Your Task:
     Task [N] of [Total]: [Task description from plan]

     ### Previous Handoff:
     [Paste previous task's handoff content, or "This is the first task - no previous handoff"]

     ### Handoff Directory:
     thoughts/handoffs/<session-name>/

     ### Handoff Filename:
     task-[NN]-[short-description].md

     ---

     Implement your task and create your handoff.
     """
   )
   ```

3. **Process agent result:**
   - Read the agent's handoff file
   - Update ledger checkbox: `[x] Task N`
   - Update plan checkbox if applicable
   - Continue to next task

4. **On agent failure/blocker:**
   - Read the handoff (status will be "blocked")
   - Present blocker to user
   - Decide: retry, skip, or ask user

## Recovery After Compaction

If auto-compact happens mid-orchestration:

1. Read continuity ledger (loaded by SessionStart hook)
2. List handoff directory:
   ```bash
   ls -la thoughts/handoffs/<session-name>/
   ```
3. Read the last handoff to understand where you were
4. Continue spawning agents from next uncompleted task

## Handoff Chain

Each agent reads previous handoff → does work → creates next handoff:

```
task-01-user-model.md
    ↓ (read by agent 2)
task-02-auth-middleware.md
    ↓ (read by agent 3)
task-03-login-endpoint.md
    ↓ (read by agent 4)
...
```

The chain preserves context even across compactions.

---

# MODE 3: Task-Tracked Parallel Orchestration

For large plans (10+ tasks) or multi-domain work, use CCv3 Tasks for dependency management and parallel execution.

## Why Tasks + Handoffs?

| Mechanism | Purpose |
|-----------|---------|
| **Tasks** | Progress tracking, dependencies, parallel coordination |
| **Handoffs** | Rich context transfer between agents |
| **Ledger** | Global project state |

**Tasks alone** = know WHAT was done
**Handoffs alone** = know HOW it was done
**Both** = complete picture that survives any compaction

## The Four Task Tools

```
TaskCreate   → Create new task with subject, description, activeForm, metadata
TaskUpdate   → Modify: status, owner, addBlockedBy, addBlocks
TaskGet      → Get full details of specific task
TaskList     → See all tasks with status, owner, dependencies
```

## Setup

### 1. Enable Task Persistence (Recommended)

```json
// .claude/settings.json
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "my-project-impl"
  }
}
```

Or per-session:
```bash
CLAUDE_CODE_TASK_LIST_ID="auth-impl-2025" claude
```

### 2. Create Directories

```bash
mkdir -p thoughts/handoffs/<session-name>
```

## Task Creation Strategy

### Step 1: Parse Plan Into Task Graph

```
Plan: "Add Authentication System"

Phase 1: Setup (no dependencies)
  ├── P1.1: Install packages
  └── P1.2: Configure env vars

Phase 2: Implementation (blocked by Phase 1)
  ├── P2.1: Create User model      [blocked by P1.1, P1.2]
  ├── P2.2: Password hashing       [blocked by P2.1]
  ├── P2.3: Auth middleware        [blocked by P2.1]
  └── P2.4: Login endpoint         [blocked by P2.2, P2.3]

Phase 3: Testing (blocked by Phase 2)
  └── P3.1: Integration tests      [blocked by P2.4]
```

### Step 2: Create Tasks with Metadata

```javascript
TaskCreate({
  subject: "P2.1: Create User model",
  description: `
    Create User model in src/models/User.ts
    Success criteria: Model exists, migration runs, can create user

    Handoff: thoughts/handoffs/auth/task-03-user-model.md
  `,
  activeForm: "Creating User model",
  metadata: {
    priority: "high",
    estimate: "20min",
    phase: "2",
    domain: "backend"
  }
})
```

### Step 3: Set Dependencies

```javascript
TaskUpdate({ taskId: "3", addBlockedBy: ["1", "2"] })  // P2.1 blocked by P1.*
TaskUpdate({ taskId: "4", addBlockedBy: ["3"] })       // P2.2 blocked by P2.1
TaskUpdate({ taskId: "5", addBlockedBy: ["3"] })       // P2.3 blocked by P2.1
TaskUpdate({ taskId: "6", addBlockedBy: ["4", "5"] })  // P2.4 blocked by P2.2, P2.3
```

**Key:** When task #4 completes, any task blocked ONLY by #4 auto-unblocks!

### Step 4: Assign Owners by Domain

```javascript
TaskUpdate({ taskId: "1", owner: "setup-agent" })
TaskUpdate({ taskId: "2", owner: "setup-agent" })
TaskUpdate({ taskId: "3", owner: "backend-dev" })
TaskUpdate({ taskId: "4", owner: "backend-dev" })
TaskUpdate({ taskId: "5", owner: "backend-dev" })
TaskUpdate({ taskId: "6", owner: "backend-dev" })
TaskUpdate({ taskId: "7", owner: "test-runner" })
```

## Parallel Agent Spawning

### The Pattern: Agents Discover Their Own Tasks

Agents don't receive task assignments directly. They **discover their tasks** via TaskList + owner filtering:

```javascript
Task({
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: `
    You are backend-dev agent.

    1. Call TaskList() to see all tasks
    2. Find tasks where owner = "backend-dev" AND status = "pending" AND not blocked
    3. For each unblocked task:
       a. TaskUpdate(taskId, status: "in_progress")
       b. Read task description for details
       c. Implement the task
       d. Create handoff: thoughts/handoffs/<session>/task-NN-<name>.md
       e. TaskUpdate(taskId, status: "completed")
    4. Repeat until no more tasks for you

    If blocked, report what you're waiting for.
  `,
  description: "Backend implementation agent"
})
```

### Spawning Multiple Agents in Parallel

**Critical:** Multiple Task() calls in ONE message = parallel execution!

```javascript
// ONE message with THREE Task() calls = 3 parallel agents

Task({
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: "You are backend-dev. TaskList() → find owner='backend-dev'...",
  description: "Backend agent"
})

Task({
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: "You are frontend-dev. TaskList() → find owner='frontend-dev'...",
  description: "Frontend agent"
})

Task({
  subagent_type: "Bash",
  model: "haiku",
  prompt: "You are test-runner. Run test suite, report results...",
  description: "Test runner agent"
})
```

All three run simultaneously, updating the same TaskList without conflicts!

## Agent Types & Model Selection

| Type | Can Do | Use For |
|------|--------|---------|
| `general-purpose` | Read, write, edit, bash, search | Implementation work |
| `Bash` | Only terminal commands | Git, tests, builds |
| `Explore` | Read-only, search | Codebase investigation |
| `Plan` | Read-only, architectural | Design decisions |

| Model | Use For |
|-------|---------|
| `haiku` | Simple tasks, commands, searches |
| `sonnet` | Most implementation work |
| `opus` | Complex reasoning, architecture |

## Visual Progress Tracking

Press `ctrl+t` to toggle task view in terminal:

```
Tasks (2 done, 1 in progress, 6 pending) · ctrl+t to hide

✓ #1 P1.1: Install auth packages (setup-agent)
✓ #2 P1.2: Configure JWT secret (setup-agent)
■ #3 P2.1: Create User model (backend-dev)
□ #4 P2.2: Add password hashing (backend-dev) ⚠ blocked by #3
□ #5 P2.3: Create auth middleware (backend-dev) ⚠ blocked by #3
□ #6 P2.4: Implement login endpoint (backend-dev) ⚠ blocked by #4, #5
□ #7 P3.1: Integration tests (test-runner) ⚠ blocked by #6
```

When #3 completes → #4 and #5 auto-unblock → both can run in parallel!

## Combined Recovery (Tasks + Handoffs)

After compaction, you have TWO recovery mechanisms:

### 1. TaskList (quick status)
```javascript
TaskList()
// Shows: #1-3 completed, #4 in_progress, #5-7 pending
```

### 2. Handoffs (rich context)
```bash
ls thoughts/handoffs/<session>/
# task-01-install-packages.md
# task-02-configure-jwt.md
# task-03-user-model.md  ← last completed, read for context
```

**Recovery pattern:**
1. `TaskList()` → see what's done/pending
2. Read last handoff → understand where you were
3. Respawn agents for remaining tasks

---

# Mode Selection Guide

| Scenario | Mode | Why |
|----------|------|-----|
| 1-3 simple tasks | Mode 1 (Direct) | No overhead needed |
| 4-9 tasks, sequential | Mode 2 (Handoffs) | Rich context transfer |
| 10+ tasks | Mode 3 (Tasks + Handoffs) | Dependency management |
| Multi-domain work | Mode 3 | Parallel agents |
| Context preservation critical | Mode 2 or 3 | Handoffs survive compaction |
| Quick bug fix | Mode 1 | Speed over structure |
| User explicitly requests | Respect preference | |

---

# Integration with session-init

Plans from `/session-init` include:
- `phases:` with steps → convert to Tasks with dependencies
- `checkpoints:` → add to Task descriptions as success criteria
- `agents_sequence:` → use as owner assignments
- `blockers_required:` → use for addBlockedBy

### Auto-Detection

If plan contains:
```yaml
execution:
  tasks_enabled: true
  task_list_id: "session-xxx"
```

Use that ID and enable Mode 3.

---

# Quick Reference

```javascript
// Tasks
TaskCreate({ subject, description, activeForm, metadata })
TaskUpdate({ taskId, status: "in_progress" | "completed" })
TaskUpdate({ taskId, owner: "backend-dev" })
TaskUpdate({ taskId, addBlockedBy: ["1", "2"] })
TaskList()
TaskGet({ taskId })

// Handoffs
// Create: thoughts/handoffs/<session>/task-NN-<name>.md
// Read previous handoff before starting task
// Write handoff after completing task

// Ledger
// Read: thoughts/ledgers/CONTINUITY_<session>.md
// Update checkbox after task completion
```

---

# Tips

- **Keep orchestrator thin:** Don't do implementation work yourself. Just manage agents.
- **Trust the handoffs:** Agents create detailed handoffs. Use them for context.
- **One agent per task:** Don't batch multiple tasks into one agent.
- **Dependencies matter:** They prevent out-of-order execution.
- **Owner names:** Use meaningful names (`backend-dev` not `agent1`).
- **Monitor with `ctrl+t`:** See live progress.
- **Task granularity:** Target 15-45 minutes per task.

---

# Troubleshooting

**Tasks not persisting?**
→ Set `CLAUDE_CODE_TASK_LIST_ID` in `.claude/settings.json`

**Agent not finding tasks?**
→ Check owner field matches exactly (case-sensitive)

**Task stuck as blocked?**
→ Run `TaskList`, find blockers, complete them first

**Lost context after compaction?**
→ Read handoffs from `thoughts/handoffs/<session>/`

**Progress not showing?**
→ Press `ctrl+t` to toggle task view

---

## 🚀 QUICK START GUIDE

### Minimal Implementation (3 tasks or less)

```
User: /implement_plan thoughts/shared/plans/my-plan.md

1. Read plan → understand phases
2. TaskCreate for each phase
3. For each phase:
   a. TaskUpdate(in_progress)
   b. Implement changes
   c. Verify success criteria
   d. TaskUpdate(completed)
4. When all tasks done → summary
```

### Standard Implementation (4-9 tasks)

```
User: /implement_plan thoughts/shared/plans/feature.md

1. Read plan → identify phases
2. TaskCreate for each phase with dependencies
3. Create session handoff dir: thoughts/handoffs/session-YYYY-MM-DD/
4. For each phase:
   a. Read previous handoff for context
   b. TaskUpdate(in_progress)
   c. Spawn agent for implementation
   d. Agent writes handoff on completion
   e. TaskUpdate(completed)
5. Final: /petla verify --against plan
```

### Large Implementation (10+ tasks)

```
User: /implement_plan thoughts/shared/plans/big-feature.md

1. Read plan → convert to Tasks with owners
2. Setup parallel agent pools by domain
3. Spawn agents with owner discovery:
   "Find tasks where owner=backend-dev, implement next pending"
4. Agents auto-coordinate via TaskList
5. Monitor with ctrl+t
6. Final verification: /petla verify
```

---

## 🔄 COMPACTION RECOVERY PROTOCOL

**Jeśli sesja została przerwana przez kompakcję kontekstu:**

### Step 1: Quick Status

```
TaskList()

Output:
#1 [completed] Phase 1: Setup
#2 [completed] Phase 2: Database
#3 [in_progress] Phase 3: API endpoints  ← YOU ARE HERE
#4 [pending] Phase 4: Tests
#5 [pending] Phase 5: Docs
```

### Step 2: Rich Context Recovery

```
# Find last completed handoff
ls thoughts/handoffs/session-*/

# Read last handoff for context
Read("thoughts/handoffs/session-2026-01-28/task-02-database.md")

# Read current task details
TaskGet("3")
```

### Step 3: Continue Implementation

```
# Current task already in_progress - continue work
# OR if status was lost:
TaskUpdate("3", status="in_progress")

# Complete the work
... implement Phase 3 ...

# Mark done and move on
TaskUpdate("3", status="completed")

# Write handoff for next agent/session
Write handoff for Phase 3
```

### Step 4: Process Remaining

```
WHILE TaskList() has pending:
    next = first unblocked pending task
    TaskUpdate(next.id, status="in_progress")
    implement(next)
    TaskUpdate(next.id, status="completed")
    write_handoff(next)
```

---

## 📊 PROGRESS REPORTING FORMAT

Use consistent format for progress updates:

```
═══════════════════════════════════════════════════════
  /implement_plan - Progress Report
═══════════════════════════════════════════════════════
  Plan: thoughts/shared/plans/auth-feature.md
  Mode: Mode 2 (Handoffs)
  Session: session-2026-01-28-1430
───────────────────────────────────────────────────────
  Phases: 5 total
    ✅ Completed:  2 (40%)
    🔄 Current:    1 (Phase 3: API endpoints)
    ⏳ Pending:    2
    🔒 Blocked:    0
───────────────────────────────────────────────────────
  Handoffs: thoughts/handoffs/session-2026-01-28-1430/
    task-01-setup.md ✅
    task-02-database.md ✅
═══════════════════════════════════════════════════════
```

---

## 🔗 POST-IMPLEMENTATION VERIFICATION

After completing all phases, verify implementation:

```
# Verify implementation matches plan
/petla verify src/ --against thoughts/shared/plans/auth-feature.md

# If issues found:
/petla solve --issues thoughts/shared/petla/verify-*.yaml

# Final audit for quality
/petla audit src/ --lenses "bugs,tests,security"
```

**Integration chain:**
```
session-init → plan
           ↓
implement_plan → implementation
           ↓
/petla verify → verify vs plan
           ↓
/petla audit → find new issues
           ↓
/petla solve → fix issues
```

---

## ⚠️ COMMON MISTAKES

### ❌ Don't start without Tasks

```
# WRONG
Read plan
Start implementing Phase 1...

# RIGHT
Read plan
TaskCreate("Phase 1")
TaskCreate("Phase 2")
...
TaskUpdate("Phase 1", status="in_progress")
Start implementing Phase 1...
```

### ❌ Don't forget handoffs

```
# WRONG
Complete Phase 2
Move to Phase 3...

# RIGHT
Complete Phase 2
Write handoff: task-02-database.md
TaskUpdate("Phase 2", status="completed")
Read previous handoff
Move to Phase 3...
```

### ❌ Don't skip verification

```
# WRONG
All tasks completed
"Implementation done!"

# RIGHT
All tasks completed
/petla verify --against plan
Fix any gaps
"Implementation verified ✅"
```
