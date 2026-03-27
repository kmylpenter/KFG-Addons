# Minimal Change Principle

**LESSON LEARNED:** 9 friction events from excessive changes. Claude over-engineers and rewrites working code.

## The Rule

Make the SMALLEST change that correctly solves the problem.

## Decision Ladder

Pick the FIRST option that works:

1. **Change a config/constant** (1 line)
2. **Fix the bug in-place** (1-5 lines)
3. **Add a small function** (10-20 lines)
4. **Modify an existing module** (20-50 lines)
5. **Add a new file** (50+ lines) -- ONLY if 1-4 genuinely cannot work

## Red Flags: Over-Engineering

Stop and simplify if you notice:

- Creating an abstract base class for one implementation
- Adding a config file for something that could be a constant
- Building a plugin system when there is one plugin
- Creating a new directory for a 20-line feature
- Refactoring existing working code to "prepare" for your change
- Adding generic type parameters with one concrete type

## Scope Lock

Once you start implementing, do NOT expand scope:

```
Requested: "Fix the date formatting bug"

IN SCOPE: Fix the date formatting
OUT OF SCOPE (even if you notice them):
- Refactoring the date utility
- Adding date validation
- Improving date picker UX
- "While I'm here" improvements

If you notice other issues, MENTION them. Do NOT fix them unless asked.
```

## File Count Check

| Files Changed | Action |
|---------------|--------|
| 1-2 | Normal - proceed |
| 3-5 | Pause - is each change necessary? |
| 6+ | Stop - re-read the original request |
