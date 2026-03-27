# Global Session Rules

## Environment (Termux Android)
- /tmp is NOT writable. Use $TMPDIR or $PREFIX/tmp for temp files.
- Target: Android tablet in kiosk mode. No desktop APIs (Electron, system tray, native notifications).
- Stack: Google Apps Script + HTML frontends, Zoho CRM integration.
- Files regularly reach 4000-6000 lines. Use targeted reads (offset/limit), never read whole large files.

## Architecture Confirmation (prevents wrong-approach pivots)
Before implementing, state your chosen approach in ONE line and wait for approval:
- "Approach: [web app / GAS webapp / CLI tool / ...]"
If the user corrects you, pivot immediately -- do not defend the wrong choice.
Never pick desktop/Electron/native when the target is a tablet kiosk web app.

## Verification Gate (prevents premature "done" claims)
After any fix or feature, BEFORE reporting done:
1. Re-read the changed lines (not just trust your edit).
2. If tests exist, run them. If no tests, do a manual smoke-check (grep for regressions, check imports).
3. For Zoho fields: confirm exact API field name from existing code, never guess. Search codebase first.
Never say "fixed" without step 1-2 completed.

## Audit vs Fix Mode
When asked to audit/review: produce a findings list ONLY. Do not fix anything.
When asked to fix: fix ONE issue per commit, verify, then next.
Never mix modes unless explicitly told "audit and fix".

## Session Discipline
If a session has 4+ unrelated tasks, warn: "Consider splitting into focused sessions."
Do one task fully (implement + verify) before starting the next.

## Large File Edits (4000+ lines)
- Read only the relevant section (offset/limit or search first).
- Edit with surgical replacements, never rewrite large blocks.
- After editing, re-read the edited region to confirm correctness.

## Zoho CRM Fields
Field names in Zoho API differ from UI labels. Always grep existing code for the field name before using it. Never assume a field name from the UI label.
