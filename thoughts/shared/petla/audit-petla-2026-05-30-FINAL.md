# Petla Self-Audit for Opus 4.8 — FINAL REPORT

**Date:** 2026-05-30
**Target:** `~/.claude/skills/petla/SKILL.md` (installed v3.1, 2001 lines — the LIVE skill)
**Compared:** `addons/autoinit-skills/files/.claude/skills/petla/SKILL.md` (repo v3.0, 1594 lines — STALE)
**Model:** Opus 4.8 (1M context)
**Method:** /petla audit methodology, subagents-only (Termux-safe, zero panes).
- Iteration 1: 7 independent lens validators (model-4.8-leverage, tooling-currency, prompt-quality, consensus-and-termination, termux-safety-invariant, internal-consistency, quality-vs-context).
- Iteration 2: adversarial-verifier (refute the criticals) + completeness-critic (read the referenced lib files: smoke-launcher.js, gas-server.py, README.md, package.json).
- Orchestrator independently re-verified every CRITICAL by reading the cited lines + grep.
**Convergence:** CONVERGED (completeness critic; diminishing returns on text; only open item is empirical execution of smoke-launcher, a separate test task).
**Mode:** PURE AUDIT — findings only. No code changed in this phase.

---

## KEY META-INSIGHT (the headline)

The petla consensus engine is, at the **pseudocode** level, genuinely broken (see C1, C2, C3). **Yet this very audit ran flawlessly** — because the orchestrator (Opus 4.8) interpreted the *intent* of the skill (spawn lenses → read verdicts → judge convergence) rather than literally executing `check_consensus()`/`evaluate_stop_conditions()`.

This empirically proves the single most important 4.8-readiness finding: **the skill's correctness today rests entirely on the model treating its Python blocks as illustrative intent.** A more literal executor (the direction 4.8 trends) that ran the pseudocode verbatim would declare false consensus at iteration 0. The fix is therefore twofold everywhere: (a) make the logic *correct* so a literal executor is also correct, and (b) frame it explicitly as "LOGIC SPEC — enact via tools, do not run literally."

---

## CRITICAL (consensus-engine correctness + runtime accounting)

### C1 — `check_consensus` is broken (signature + truthiness). KEYSTONE BUG.
- **Where:** def `check_consensus(verdicts, agents_count)` @976; sole call `if check_consensus(verdicts, mode): return success(iteration)` @1792.
- **Evidence (verified by orchestrator + adversarial verifier):** (a) call passes string `mode` where int `agents_count` is expected → the `len(valid) < agents_count` missing-verdict guard (@978) is meaningless. (b) Every branch returns a non-empty 3-tuple → always truthy → `'dirty'`/`'inconclusive'` are treated as success; the tuple `[0]` is never destructured. → **declares consensus at iteration 0 even when issues_found.**
- **Fix:** `status, reason, _ = check_consensus(verdicts, agents_count)`; branch only on `status == 'clean'`; route `inconclusive`→re-spawn, `dirty`→next iter. Pass `agents_count` (int), not `mode`.

### C2 / V2-1 — The entire v3.1 stop-conditions subsystem is UNWIRED, and the coverage gate is a permanent no-op.
- **Where:** `evaluate_stop_conditions` @1213 has **zero callers** (grep). `coverage_complete` @1257 is called only from the (uncalled) `evaluate_stop_conditions` @1228. Additionally `target_files` is **read** @1259/1266 but **never written** anywhere → `if not target_files: return True` (@1260) always fires.
- **Impact:** The headline v3.1 "multi-criteria stop conditions / coverage proof / confidence levels (converged/unbounded/stuck)" — the fix that the 2026-05-01 audit added — is **dead code**. The reachable loop relies only on broken `check_consensus` + broken stuck-detection + `max_iter`.
- **Fix:** Wire `evaluate_stop_conditions` into the loop (or fold its logic into the consensus decision); populate `meta.target_files` at init (Glob the scope) and treat empty as INCONCLUSIVE, never `True`; have `success()`/report carry the confidence level (V2-2).

### C3 — Coverage-proof threshold contradiction (≥5 vs ≥3 vs 0.95).
- **Where:** validator prompt @747-748 says no_issues INVALID without FILES_EXAMINED ≥5 AND PATTERNS_CHECKED ≥5; binding gate `verify_coverage_proof` @990-991 accepts ≥3/≥3 (called from check_consensus @983); `coverage_complete` @1267 uses 0.95.
- **Found by 5 lenses independently + verified.** The orchestrator enforces a *looser* bar (≥3) than the subagent is told (≥5); also it checks list *length* only (an UNABLE entry counts).
- **Fix:** one constant `MIN_FILES=MIN_PATTERNS=5` (raise, per quality-over-tokens), require each counted pattern result ∈ {CHECKED+0, CHECKED+N} (reject UNABLE), and make the "<5 files in scope → all files" carve-out explicit in the gate, not just the prompt.

### C4 — `--smoke` default is triple-contradictory.
- **Where:** @1399 "bez --smoke = legacy (no runtime phase)"; @1401 "--smoke=auto … (default M2)"; @1406 "no schema_version → --smoke=never default".
- **Fix:** one precedence rule, e.g. "no flag ⇒ `--smoke=never`; `auto` is recommended-explicit, not implicit." Remove the "(default M2)" label.

### C5 (CC2-1) — Launcher exit codes 2 & 4 are DEAD on the documented CLI path.
- **Where:** `smoke-launcher.js` `runTest()` returns only `{exit:0|1|3}` (INCONCLUSIVE→exit 3 @137/144/155; all test-body throws→exit 1 @237). SKILL.md @1480-1488/1657-1666 + README promise exit 2 (INCONCLUSIVE) / exit 4 (crash).
- **Impact:** the solve runtime-lens PASS/FAIL/INCONCLUSIVE retry accounting can **never observe exit 2/4** from the single-test runner → a flaky/inconclusive runtime test is miscounted as a hard FAIL (wrong retry budget + wrong needs_human_review reason).
- **Fix:** either map status→exit faithfully in the launcher (INCONCLUSIVE→2, crash→4), OR document that the orchestrator MUST parse the END-marker `status` field (not the process exit code) and that CLI exit is a coarse 0/1/3 signal.

---

## MAJOR (grouped)

### A. Consensus / termination
- **M-A1 — "X/5 → DONE" vote-counting examples** (@1061,1068,1123,1197,1202; YAML samples @537,578) contradict the three-state+coverage algorithm → re-teach false consensus. (NB: the ASCII box @440 "ALL no_issues? YES→DONE" is *consistent*; only the numeric X/5 examples conflict.) Fix: rewrite examples to three-state language.
- **M-A2 — 7 undefined helpers + 2 orphan defs.** `build_validator_prompt, format_existing_issues, find_independent_issues, spawn_final_verification, update_state_file, parse_yaml_from_tool_results, aggregate` (defs=0). `get_lens_instructions` (@890) + `compress_existing_summary` (@904) defined but never called; the spawn template uses raw `LENS_INSTRUCTIONS[lens][mode]` @739 → **KeyError on a custom lens** (the graceful fallback is dead). Fix: call `get_lens_instructions(lens,mode)` in the template; add a global note that italicized helper names are conceptual / enacted via tools.
- **M-A3 — Live stuck-detection** uses `set(v.issues for v in verdicts)` @1785 (unhashable/never-equal with fresh agents) not the documented `issue_key()` → never fires; only real stop is `max_iter`. Fix: route through wired-in `evaluate_stop_conditions`.
- **M-A4 — Subagent-failure handling** only reports when `len(failed) > 2` @1781, never re-spawns, ignores 1-2 failures → contradicts spec @955-961 ("≥1 failed → block consensus"). Fix: any failed verdict → re-spawn once → else INCONCLUSIVE (blocks consensus).

### B. Tooling currency / 4.8 leverage
- **M-B1 — Pseudocode literal-execution risk:** one "illustrative" note @1711, after 8 of 11 code blocks. Fix: global note near top + a per-fence "LOGIC SPEC — enact via tools" marker.
- **M-B2 — No subagent model guidance.** 28 spawns, all `subagent_type="general-purpose"`, zero `model=` and no "inherit Opus / never haiku" note. One config drift away from silent quality regression. Fix: state subagents inherit Opus; never haiku for lens/verify/final-sweep; mention in Safety table.
- **M-B3 — Workflow tool unused.** The orchestration (parallel spawn, consensus, loop, dedup, stop) is hand-rolled prose. Recommend an **opt-in workflow fast-path** (parallel() fan-out, loop-until-dry, budget) while keeping the prose path as default (Workflow needs explicit opt-in; skill must stay invocable without it). Couple with:
- **M-B4 — Schema-forced output unused.** The whole "RESPOND ONLY IN YAML" + malformed/empty/INCONCLUSIVE machinery is a workaround for fragile free-text YAML. `Workflow agent({schema})` forces a validated object (coverage proof becomes a schema constraint). Plain Agent **cannot** — so document the dependency: schema-forced verdicts only on the workflow opt-in path.

### C. Smoke / runtime (M1/M2)
- **M-C1 (CC2-2) — KROK 0 GATE `basename()` corrupts solve's path-bearing audit-file arg** (`/petla solve --issues thoughts/shared/petla/audit-*.yaml` → basename strips the dir). Fix: apply basename() only to the audit/create/verify TARGET; validate the solve AUDIT-FILE with a confined-path check that preserves the directory.
- **M-C2 (CC2-3) — `.smoke-config.yaml` is inert on the documented `node smoke-launcher.js <test>` invocation** (`init_wait_for_function`, `gas_url`, etc. never read; only programmatic `consoleFilterRegex`). Fix: document M1 ignores the YAML and the orchestrator must pass options via the programmatic API + start/wire gas-server port, OR add a YAML loader to the CLI entrypoint.
- **M-C3 (CC2-4) — Truncation labeled 3 contradictory ways** (SETUP_ERROR @1478 vs INCONCLUSIVE @1632 vs SETUP_ERROR-budget-exempt @1487). Fix: one rule (missing/!END marker = INCONCLUSIVE-infrastructure, budget-exempt, re-run once; orchestrator-detected).
- **M-C4 (CC2-5) — Runtime-lens FAIL has no rollback** (@1481-1488) unlike static FAIL (@671 `git checkout`); leaves a committed regression. Fix: revert the just-committed fix on runtime FAIL before re-queue.
- **M-C5 (CC2-6) — Fix-status taxonomy fragmented:** `fixed`/`verified`/`blocked`/`[BLOCKED]`/`needs_human_review`/`rejected`. The CONSENSUS RULE termination gate checks `status=fixed` (@357) which solve never sets (it sets `verified`); schema enum @568 lacks several. Fix: one canonical enum `proposed|applied|verified|blocked|needs_human_review|rejected`; update gates + schema.

### D. Termux safety (USER'S EXPLICIT PRIORITY)
- **M-D1 (TMX-1) — The Termux-safety property is NOT a single hardened invariant** — scattered across ~9 paragraphs; grep for "INVARIANT/NEVER VIOLATE" = 0 hits. A careless future edit (re-adding teammates) trips no guard. **Fix (user asked for this): add `## INVARIANTS — NEVER VIOLATE (Termux)` near the top:** (1) never TeamCreate/team_name/SendMessage/teammates; (2) all validators = `Agent(subagent_type=...)` only, invisible by design; (3) never rely on run_in_background to hide a pane; (4) smoke/worktree are opt-in and must clean up. Reference #23615/#34468. Keep <12 lines (survives compaction).
- **M-D2 (TMX-2) — Smoke launches real headless chromium on Termux with no OOM/serialization/parallel-fan-out caveat.** A runaway browser can freeze the kiosk — the same *spirit* as the old 5-pane freeze. Fix: state browser runs strictly one-at-a-time; recommend `enabled:false` default on low-RAM tablets; never auto-enable smoke during a 10-agent fan-out; OOM → INCONCLUSIVE not silent pass.

### E. Quality-vs-context (user prefers thoroughness > tokens, 1M ctx)
- **M-E1 (CON-6/QVC-1) — exclude-list compression breaks dedup + corrupts `new_issues_found`.** `compress_existing_summary` emits only per-file counts, but the dedup rule needs file:line+root-cause → agents re-report (inflate discovery → false "unbounded") or skip (premature converge). Misaligned with quality-over-tokens. Fix: pass FULL uncompressed prior findings (id+location+one-line) in `<state-data>`; keep compression only as an optional huge-audit fallback.
- **M-E2 (QVC-5) — Quality-limiting caps:** default agents=5; HARD CAP 10 agents/10 iters; `lenses[:agents_count]` **silently drops** user-supplied lenses. The 10-agent cap was originally a Termux-*pane* safety limit — now moot (subagents invisible) → it's pure frugality. Fix: auto-expand `agents_count = len(lenses)` (never drop a lens); raise defaults for the quality-first profile; lift the cap far higher (keep a sane runaway ceiling).
- **M-E3 (QVC-3) — 95% coverage = HIGH "trustworthy"** leaves up to 5% of files unread. Fix: HIGH requires 100% scope examined; any unexamined file caps confidence at MEDIUM + lists the gap.
- **M-E4 (QVC-4/M48-6) — "top 3 risks" timeout retry** narrows coverage. Fix: re-spawn full scope with longer budget (or partition), reserve "top 3" for last resort.

### F. Drift / consistency / dispatch
- **M-F1 (IC-1) — repo v3.0 ↔ installed v3.1 drift; the `browser-smoke` lib is ENTIRELY ABSENT from the repo** → a clean autoinit install gets a skill referencing `~/.claude/lib/browser-smoke/*` that won't exist, plus no smoke/runtime/sprint/fixes. Fix: sync repo from installed (after fixes), bump version, and add a parity note/check; ship or vendor the browser-smoke lib (or gate smoke behind a presence check).
- **M-F2 (PQ-3) — Solve Extended Flow step-letter collision** (duplicate `f`, ambiguous nesting) @1451-1494 → wrong control flow. Fix: renumber (e.1/e.2… for nested).
- **M-F3 (PQ-2) — `--smoke=interactive` two contracts** (ask path @188 vs yes/skip @1473). Fix: one contract (recommend yes/skip), reference verbatim.

---

## MINOR (fix opportunistically)
- Token-frugality framing ("re-read is a cost" @928) misaligned with 1M/quality → reframe as a benefit. [QVC-6/M48-5]
- Redundant compaction scaffolding / autonomy stated 3× → consolidate to one canonical block + pointers. [M48-5]
- "30-60s" self-check time-box (meaningless to an LLM) → reframe as effort/coverage. [M48-6]
- Usage `Modes:` omits smoke; parser comment omits smoke; `DEFAULT_LENSES` has no smoke key → smoke un-routable by the dispatcher. [IC-6/CC2-8]
- `issues[].item` vs `.description` field drift → `issue_key` desc half empties on 3.1 audit files. [IC-7] Fix: `issue.get('item') or issue.get('description')`.
- Worktree: no Termux disk/inode caveat. [TOOL-3/TMX-4]
- `--agents` min contradiction (`min:2` @1690 vs no floor @252). [PQ-5]
- `should_run_runtime` double-gating / undefined helper, two arg signatures. [PQ-6]
- solve arg binding: 3 forms (`<audit-file>` / `--issues` / bare `audit.yaml`), parser supports none. [PQ-7/CC2-9]
- `unbounded` check only at iter≥3 (could be iter≥2). [CON-9]
- final sweep hardcoded "3/3" vote + uses 3 not 5 lenses; `success()` carries no confidence level. [V2-2/V2-3/QVC-7]
- create/verify `completed`/`incomplete` verdicts unmapped in `check_consensus`. [CC2-10]
- H1 says "v3.0" while frontmatter is "3.1"; `TaskGet` allowed-but-unused. [IC-5/CC2-11]
- 2001-line monolith → progressive disclosure (`references/*.md`); smoke section duplicates README. [CC2-12]
- README `require('~/.claude/...')` won't tilde-expand (JS). [CC2-7]
- `ScheduleWakeup`/`/loop` unused for very long solve runs (optional). [TOOL-5]

---

## REFUTED — DO NOT "FIX" (false positives caught in iteration 2)
- **TMX-3 "gas-server.py has no trap/finally cleanup" → FALSE.** `gas-server.py` installs SIGTERM/SIGINT handlers with finally-cleanup (lines 230-239, 251). The only residual is the Android SIGKILL/low-memory caveat, already documented in README:75. Not a finding.

---

## HARD INVARIANTS TO PRESERVE DURING FIXES
1. **TERMUX-SAFETY** — subagents-only; NEVER teammates/TeamCreate/SendMessage-to-validators; zero tmux panes; no Termux hang. (v3.0 dropped Agent Teams precisely because run_in_background does not hide Agent panes — #23615.) **Harden this into an explicit INVARIANTS block (M-D1).**
2. **QUALITY OVER TOKENS** — 1M context; prefer thoroughness over token savings; remove frugality that reduces quality.
3. **Must remain a user-invocable markdown skill** — Workflow adoption only as an opt-in fast-path, never a hard dependency.

---

## PHASE-2 FIX PRIORITY (recommended order)
1. **Add the INVARIANTS block** (M-D1) — first, so the rest is edited under its protection.
2. **Fix the consensus engine pseudocode** correct + clearly labeled "LOGIC SPEC": C1, C2/V2-1 (wire stop-conditions + populate target_files), C3 (unify thresholds), M-A1 (examples), M-A2 (helpers/fallback), M-A3 (stuck), M-A4 (failure).
3. **4.8 leverage:** M-B1 (pseudocode framing), M-B2 (model guidance), M-B3/M-B4 (document the optional Workflow + schema fast-path).
4. **Quality-vs-tokens:** M-E1 (full exclude list), M-E2 (no lens drop, raise caps), M-E3 (100% coverage for HIGH), M-E4.
5. **Smoke/runtime + dispatch:** C4, C5, M-C1..M-C5, smoke dispatch minors.
6. **Version/title/consistency minors.**
7. **Sync repo ↔ installed** (M-F1) + bump version.
8. **Re-audit** (phase 3).

Counts: ~5 critical, ~23 major, ~18 minor, 1 refuted. Confidence: HIGH (cross-validated by independent lenses + adversarial verification + orchestrator line-level re-check).
