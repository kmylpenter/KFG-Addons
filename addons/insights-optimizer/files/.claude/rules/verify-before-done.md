# Verify Before Declaring Done

**LESSON LEARNED:** 26 friction events from Claude declaring fixes complete when bugs remained. Prediction-overwrite bug was re-raised 5 times.

## The Rule

Before saying "done", "fixed", "implemented", or "complete", you MUST:

### For Bug Fixes

1. **Re-read the changed code** - actually Read the file after editing, do not rely on memory
2. **Trace the logic path** - mentally execute the fix with the failing input
3. **Check for regressions** - did your fix break adjacent code?
4. **Run tests if they exist** - `npm test`, `pytest`, etc.

### For New Features

1. **Re-read all changed files**
2. **Check imports** - did you import everything you used?
3. **Check types** - do function signatures match their callers?
4. **Run the build** - does it compile?

## Bug Patterns to Watch

| Pattern | Check |
|---------|-------|
| Cache key mismatch | Key used for write == key used for read? |
| Stats/counter logic | Increment and read use the same variable? |
| Premature save/write | Data is fully computed BEFORE writing? |
| Overwrite bug | Read-modify-write, not read-write (losing other fields)? |
| Off-by-one | Loop boundaries, array indices, string slicing |
| Async ordering | Await in correct order? Race conditions? |

## The "5th Time" Rule

If the user reports the same bug again:
1. STOP implementing immediately
2. Read the ENTIRE file, not just the function
3. Search for ALL places the buggy pattern exists
4. Fix ALL instances, not just the one reported

## Forbidden Phrases (until verification)

```
NEVER SAY without verifying first:
- "This should fix it"
- "The issue was X, I've corrected it"
- "Done! The fix..."
```

INSTEAD:
```
"I've made the edit. Let me verify..."
[Read the file]
[Trace the logic]
"Verified - the fix correctly handles [case] because [reason]."
```
