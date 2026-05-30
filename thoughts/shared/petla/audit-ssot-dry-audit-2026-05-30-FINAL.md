# SSOT-DRY-Audit Skill — Audit for Opus 4.8 (FINAL)

**Date:** 2026-05-30
**Target:** `~/.claude/skills/ssot-dry-audit/SKILL.md` (400 lines) + `scripts/detect_duplicates.py` (572 lines)
**Drift:** installed == repo, IDENTICAL (no drift, unlike petla).
**Method:** 2 targeted lenses (4.8-integration, doc↔helper-consistency) — deliberately leaner than petla's 7 (token-conscious, per user). Orchestrator independently verified the petla-integration claim + ran the helper empirically (python 3.14, real fixture).
**Mode:** PURE AUDIT → then applied the small fixes (all doc/comment level; no engine bugs like petla had).

## Verdict: the skill is fundamentally CLEAN
Both lenses returned mostly clean bills. `DOC_HELPER_CONTRACT: consistent` — the highest-value check (helper JSON field names vs SKILL.md schema doc) matched field-for-field across all 6 finding categories. Pure-audit boundary strongly fenced (no Agent tool in allowed-tools → structurally cannot fix code). PII redaction airtight (verified at runtime: `value_redacted` is always the constant `[REDACTED:kind]`, never the raw match). No 4.7/2024-era assumptions, no model-version coupling.

## Empirically verified
- `detect_duplicates.py` runs under python 3.14.4, emits `schema_version: "2.0"`, 6 finding categories, `notes` array. Path-traversal guard works (rejects outside-cwd without `--allow-outside-cwd`).
- **petla integration contract INTACT (data-flow):** petla/SKILL.md:686-687 reads `confidence` value (LOW→SKIP); SSOT emits `confidence` per finding → works today. My petla changes did NOT break the handoff.

## Findings applied (1 major + 4 minor — all doc/comment)
- **S1 (major) — doc described the WRONG skip mechanism.** SSOT doc claimed petla solve skips LOW by ABSENCE of the `refactor` field; petla actually gates on the `confidence` VALUE. Works today (confidence IS emitted) but the doc misdescribed *why* → future-edit/4.8-literalism risk. **Fix:** reworded SKILL.md:296 + Zasada #3 to state `confidence` is the load-bearing field; refactor-absence is defense-in-depth, not the mechanism.
- **S2 (minor) — advisory yaml keys.** `petla_solve_rules` emits `on_test_or_build_failure`, `max_consecutive_blocked`, `require_passing_*` that petla never reads (it reads only `preflight.require_clean_tree` + `branch`). **Fix:** annotated each key READ-by-petla vs advisory.
- **S3 (minor) — template example-value bleed risk.** TAX_RATE/SSOT-001/PESEL/'admin' examples sat unguarded in the md+yaml template fences. **Fix:** added `<<< SZABLON — replace with real data >>>` markers above both templates.
- **C1 (minor) — undocumented `notes` field.** Helper emits a top-level `notes[]` the schema doc omitted. **Fix:** added `notes` to the documented schema (non-load-bearing).
- **C2 (minor) — stale code comment.** `detect_duplicates.py:137` said "REGON 14 (handled separately)" but no 14-digit pattern exists. **Fix:** corrected comment (regex unchanged — 14-digit REGON intentionally out of scope).

## Clean dimensions (no action)
schema_version gate (2.0), helper args (path/--max-file-size/--allow-outside-cwd), thresholds (≥3x/≥2 files), LOW-no-code-block rule (consistent across 7 mentions), secret/PII kind labels (match code), confidence rubric (table default + Faza 3.5 downgrade = not a contradiction), error→ABORT contract, no orphan refs.

## Sync
- `~/.claude/skills/ssot-dry-audit/SKILL.md` + `scripts/detect_duplicates.py` == repo copies (SYNCED ✓).
- This is a much smaller intervention than petla — the skill was already in good shape.
