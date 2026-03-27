# Follow Existing Plans

**LESSON LEARNED:** Claude repeatedly explored and re-planned instead of implementing existing plans.

## The Rule

Before starting implementation, check for existing plans:
1. Earlier in conversation - was a plan already discussed and approved?
2. Handoff files - `.claude/handoff-*.md`
3. Plan files - `plan.md`, `spec.md`, `TODO.md`, `PLAN.md`

## If a Plan Exists

**FOLLOW IT.** Do not:
- Re-analyze the problem from scratch
- Propose alternative approaches
- "Improve" the plan without asking
- Explore the codebase for 10 minutes before starting

**DO:**
- Read the plan
- Start implementing step 1
- If a step is unclear, ask about THAT STEP only
- If you disagree, say so BRIEFLY and ask - do not silently deviate

## The 3-File Rule

When a plan exists, read at most 3 files before coding:
1. The plan itself
2. The main file you will edit
3. One dependency you need to understand

If reading a 4th file, you are in exploration mode. Start coding.

## Anti-Pattern: The Exploration Loop

```
WRONG:
  User: "Implement the auth feature from the plan"
  Claude: "Let me first explore the codebase..."
  [reads 15 files, proposes new plan]

RIGHT:
  User: "Implement the auth feature from the plan"
  Claude: [reads the plan]
  "Following the plan. Step 1: create auth middleware..."
  [starts writing code]
```

## Exception

If the plan references code that no longer exists:
"The plan references [X] but the codebase changed: [brief]. Adapt the plan or proceed as written?"
