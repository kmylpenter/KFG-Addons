# Pętla Manual Audit - 2026-04-18

Manualny audyt skilla `/petla` bez odpalania samego skilla (uniknięcie
wieszania Termux). Cel: znaleźć regresję + zaproponować usprawnienia
pod Opus 4.7 i background-mode default.

---

## FINDINGS

### F1 (CRITICAL): Regresja Termux hang — źródło zidentyfikowane

**Gdzie:** `addons/autoinit-skills/files/.claude/skills/petla/SKILL.md`
**Kiedy:** commit `a0c2741` (2026-03-24) - "rename /loop to /petla, upgrade to v2.0"

**Co się zmieniło:**
- v1.3: `allowed-tools: ..., Task, ...` → używa prostych `Task()` calls
  (subproces, BRAK panelu w Termux)
- v2.0: `allowed-tools: ..., Agent, SendMessage, TeamCreate, ...` → używa
  Agent Teams, każdy validator to persistent teammate z WIDOCZNYM PANELEM

**Skutek na Termux:**
1. `TeamCreate()` + 5× `Agent(name=..., team_name=...)` → 5 paneli po prawej
2. Główny panel staje się bardzo wąski (~20 kolumn)
3. Długi wydruk (np. lens prompts, YAML state, verdicts) wymaga
   wielominutowego scrollowania
4. Termux hang podczas scrollowania

**Potwierdzenie:** user wspomniał że kiedyś `/loop` audit z 10 teammates
działał płynnie. To był v1.3 z `Task()` (bez paneli). v2.0 z `Agent()`
zawiesza przy 5.

### F2 (CRITICAL): `--background` istnieje w docs ale nie w implementacji

**Gdzie:** SKILL.md:635 i :966-967

**Problem:**
- Linia 635 mówi: `--background - Walidatory jako background agents (duże audyty)`
- Linia 967 komentarz: `# Validators as background agents (run_in_background: true)`
- ALE spawn template (linie 541-579) NIE ma `run_in_background`
- ALE `Krok 3: Main loop` pseudocode NIE wspomina `--background` ani branch dla Termux
- Flag jest udokumentowany ale nie użyty — martwa opcja

### F3 (MAJOR): Brak platform-aware defaults

**Gdzie:** SKILL.md:954 (Options section)

**Problem:**
- Default `--agents 5` na każdej platformie
- Termux ma mały ekran → 5 paneli = katastrofa
- Windows Terminal z multi-tab tolerate 5, macOS split - OK
- Brak auto-detect `$TERMUX_VERSION` / `$PREFIX=/data/data/com.termux/...`

### F4 (MAJOR): Brak specyfikacji modeli

**Gdzie:** Agent spawn template SKILL.md:541-579

**Problem:**
- Validators NIE mają `model:` param → dziedziczą po parent (Opus)
- 5× Opus validators = drogo + wolno
- Po wyjściu Opus 4.7 (1M ctx) warto: orchestrator Opus 4.7, validators Sonnet 4.6
- `Agent()` tool wspiera `model: "sonnet" | "opus" | "haiku"` (z `no-haiku.md` reguły — haiku zakazane)

### F5 (MINOR): Brak wzmianki o Opus 4.7 / 1M context

**Gdzie:** całość SKILL.md + backup-originals

**Problem:**
- Skill napisany pod Opus 4.5 (marzec 2026)
- Opus 4.6 (1M ctx) wyszedł kilka dni temu
- Opus 4.7 wyszedł wczoraj (2026-04-17)
- SKILL.md nie wspomina jaki model jest optymalny dla orchestratora vs validators
- 1M context znacząco zmienia dynamikę (mniej kompakcji → mniej resume logic)

### F6 (MAJOR): Task() vs Agent() — utrata prostszej alternatywy

**Problem:**
- v1.3 z `Task()` miał sens: light-weight, stateless, brak paneli
- v2.0 porzucił Task() całkowicie
- Dla małych audytów (<5 issues) Agent Teams to overkill
- Task() nadal istnieje w CC — skill mógłby mieć `--simple` mode

### F7 (MINOR): Hard limit agents=10 bez platform awareness

**Gdzie:** SKILL.md:141 `MAX_AGENTS = min(options.agents, 10)`

**Problem:**
- Cap=10 uniwersalny dla wszystkich platform
- Na Termux realny limit to ~3 (żeby ekran był używalny)
- Brak warning jeśli user poda `--agents 10` na Termux

---

## FIX PLAN

Priorytet: stabilność na Termux > optymalizacja > features.

### Phase 1: Termux unfreeze (CRITICAL — zrobić NAJPIERW)

**Fix 1.1: Default background mode na Termux**

W spawn template dodać:
```python
import os
is_termux = os.environ.get('TERMUX_VERSION') or '/data/data/com.termux' in os.environ.get('PREFIX', '')
default_background = is_termux  # True na Termux

Agent(
    name="validator-{lens}",
    team_name="petla-{mode}",
    subagent_type="general-purpose",
    mode="auto",
    run_in_background=options.background if options.background is not None else default_background,
    ...
)
```

Efekt: na Termux validatory startują w tle, bez paneli. Główny ekran
pozostaje szeroki. Żadnego scrollowania = żadnego hangu.

**Fix 1.2: Auto-cap agents na Termux**

```python
MAX_AGENTS = min(options.agents, 3 if is_termux else 10)
```

Efekt: nawet jeśli user poda `--agents 10`, Termux dostanie 3.

**Fix 1.3: Dokumentacja Termux-specific**

Dodać sekcję "Termux Users" w SKILL.md:
```markdown
## Termux (Android)

Na Termux małe ekrany i ograniczone IPC. /petla automatycznie:
- Uruchamia validatorów z `run_in_background: true` (brak paneli)
- Ogranicza `--agents` do max 3 (override: `--agents N --force`)
- Używa `SendMessage` bez display (tylko state file)

Override: `/petla audit . --panels` jeśli chcesz widzieć panels mimo Termux.
```

### Phase 2: Model optimization

**Fix 2.1: Model spec per-role**

Spawn template:
```python
Agent(
    name="validator-{lens}",
    team_name="petla-{mode}",
    subagent_type="general-purpose",
    model="sonnet",  # ← validators na Sonnet 4.6 (szybko, tanio, jakość OK)
    mode="auto",
    run_in_background=True,
    ...
)
```

Orchestrator (main context): Opus 4.7 (1M) — ustawia user globalnie, nie
per-skill. Ale w docs można zalecić.

**Fix 2.2: Dodać sekcję Model Recommendations**

```markdown
## Model Recommendations (2026-04)

| Rola | Model | Powód |
|------|-------|-------|
| Orchestrator | Opus 4.7 (1M ctx) | Złożona koordynacja, 1M kontekst = mniej kompakcji |
| Validators | Sonnet 4.6 | Wzorcowy validator task: read + YAML verdict, Sonnet radzi |
| Solve fixes | Opus 4.7 | Skomplikowane fixy wymagają reasoning |
```

### Phase 3: Quality improvements

**Fix 3.1: `--simple` mode (Task-based fallback)**

Dla małych audytów (<5 lenses lub `--simple` flag):
- Użyj `Task()` zamiast `Agent()` + `TeamCreate()`
- Brak paneli, brak zombie, brak Agent Teams env var
- Kompatybilne z pre-v2.0 behavior (jak `/loop` v1.3)

**Fix 3.2: Warning na Termux przy `--agents >3`**

```python
if is_termux and options.agents > 3:
    print(f"WARNING: --agents {options.agents} na Termux może zawiesić ekran.")
    print(f"Zalecane: --agents 3 lub użyj --background (default na Termux).")
```

**Fix 3.3: Update cross-refs dla Opus 4.7**

Sprawdzić czy inne skille (session-init, implement_plan) mają aktualne
model references. Jeśli wspominają "4.5" lub "4.6" — zaktualizować do 4.7.

### Phase 4: Documentation

**Fix 4.1: Dodać changelog w SKILL.md**

```markdown
## Changelog

- v2.1 (2026-04-18): Termux background default, Sonnet validators, Opus 4.7 ready
- v2.0 (2026-03-24): Agent Teams upgrade, consensus protocol
- v1.3 (wcześniej): Task-based loop
```

**Fix 4.2: Zaktualizować "Safety" tabelkę**

Dodać wiersz:
```
| Termux detect | Auto-background + agent cap 3 |
```

---

## IMPLEMENTATION ORDER

Wszystkie fixy trzymają się zasady "minimal change":

1. **Fix 1.1** (1 edit) — dodać `run_in_background` auto-detection w spawn template
2. **Fix 1.2** (1 edit) — auto-cap `MAX_AGENTS` dla Termux
3. **Fix 1.3** (1 edit) — dodać sekcję Termux Users
4. **Fix 2.1** (1 edit) — dodać `model="sonnet"` w validator spawn
5. **Fix 2.2** (1 edit) — dodać sekcję Model Recommendations
6. **Fix 3.1** (larger) — `--simple` mode (opcjonalne, na później)
7. **Fix 3.2** (1 edit) — warning na Termux przy wielu agentach
8. **Fix 4.1, 4.2** (2 edits) — changelog i safety update

Pierwsze 5 fiksów (Phase 1+2) to ~5 targeted edits w SKILL.md.
Nie ruszamy logiki — tylko dodajemy platform awareness i model specs.

---

## ZAPROPONOWANE NEXT STEPS

1. User potwierdza plan (czy Phase 1 wystarczy, czy robimy wszystko)
2. Implementacja Phase 1+2 (5 edits, ~15 minut)
3. Test: uruchomić `/petla audit .` na małym targecie i zweryfikować
   że panele się NIE pojawiają
4. Jeśli stabilnie — zamknąć issue, zrobić commit
5. Opcjonalnie: Phase 3+4 w osobnym commit
