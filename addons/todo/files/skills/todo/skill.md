# TODO Skill

Persistent TODO tracking across sessions. Tasks stored in `thoughts/shared/todo.yaml`.

## Usage

```
/todo <tekst>           - Add new task
/todo                   - List pending tasks
/todo done <nr|tekst>   - Mark task as done
```

## Instructions

### When called with text argument: ADD TASK

1. Read `thoughts/shared/todo.yaml` (create if missing)
2. Parse existing YAML (list of items with `text`, `added`, optional `done`)
3. Append new item:
   ```yaml
   - text: <argument text>
     added: <today YYYY-MM-DD>
   ```
4. Write back to file
5. Respond: `Zapisano: <text>`

### When called without argument: LIST TASKS

1. Read `thoughts/shared/todo.yaml`
2. Filter items WITHOUT `done:` field
3. Display as numbered list:
   ```
   TODO (X pending):
   1. Task text (added: YYYY-MM-DD)
   2. Another task (added: YYYY-MM-DD)
   ```
4. If empty: `Brak pending tasków.`

### When called with "done <nr|text>": MARK DONE

1. Read `thoughts/shared/todo.yaml`
2. Find matching task:
   - If number: match by position in pending list (1-indexed)
   - If text: match by substring in `text` field
3. Add `done: <today YYYY-MM-DD>` to that item
4. Write back to file
5. Respond: `Done: <task text>`

## File Format

```yaml
# Claude TODO - auto-managed
- text: Dodać obsługę WebSocket
  added: 2026-01-16

- text: Naprawić bug w auth
  added: 2026-01-15
  done: 2026-01-16
```

## Implementation Notes

- File path is ALWAYS `thoughts/shared/todo.yaml` relative to project root
- Create `thoughts/shared/` directory if missing
- Preserve existing items when adding/updating
- Keep YAML human-readable (proper indentation, blank lines between items)
- Use Read tool to check file, Write tool to save
- Date format: YYYY-MM-DD (e.g., 2026-01-16)

## Examples

**Add task:**
```
User: /todo Dodać testy dla auth modułu
Claude: Zapisano: Dodać testy dla auth modułu
```

**List tasks:**
```
User: /todo
Claude: TODO (2 pending):
1. Dodać testy dla auth modułu (added: 2026-01-16)
2. Refactor payment service (added: 2026-01-15)
```

**Mark done by number:**
```
User: /todo done 1
Claude: Done: Dodać testy dla auth modułu
```

**Mark done by text:**
```
User: /todo done payment
Claude: Done: Refactor payment service
```
