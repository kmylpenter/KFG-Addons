#!/bin/bash
# Infra self-test — liveness check narzedzi, ktore reklamuja reguly w ~/.claude/rules/.
# Czesc addonu env-doctor (KFG-Addons). Przenosny: Linux / macOS / Termux / PRoot / Git Bash.
# Uzycie: bash ~/.claude/scripts/infra-selftest.sh
# Wyjscie: PASS/FAIL/INFO per check; exit 0 = zero FAIL. Read-only poza 1 query testowym.

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
pass=0; fail=0
ok()   { echo "PASS  $1"; pass=$((pass+1)); }
bad()  { echo "FAIL  $1 — $2"; fail=$((fail+1)); }
note() { echo "INFO  $1"; }

# wybor pythona (python3 -> python -> py) — konwencja KFG-Addons
PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -z "$PY" ] && { bad "python" "brak python3/python/py na PATH"; echo "----"; echo "PASS=$pass FAIL=$fail"; exit 1; }

# tryb postgres? (desktop z continuous-claude) — wtedy sqlite checki sa nie na temat
PGMODE=0
[ -n "$DATABASE_URL$CONTINUOUS_CLAUDE_DB_URL" ] && PGMODE=1

# 1. recall_learnings.py
if [ -f "$CLAUDE_DIR/scripts/core/recall_learnings.py" ]; then
  if (cd "$CLAUDE_DIR" && PYTHONPATH="$CLAUDE_DIR" timeout 60 "$PY" scripts/core/recall_learnings.py \
      --query "selftest" --k 1 --text-only >/dev/null 2>&1); then
    ok "recall_learnings.py (text-only)"
  elif [ "$PGMODE" -eq 1 ] && command -v uv >/dev/null 2>&1 && \
       (cd "${CLAUDE_OPC_DIR:-$CLAUDE_DIR}" && PYTHONPATH=. timeout 60 uv run python scripts/core/recall_learnings.py \
        --query "selftest" --k 1 --text-only >/dev/null 2>&1); then
    ok "recall_learnings.py (uv/postgres)"
  else
    bad "recall_learnings.py" "padl w obu wariantach; debug: cd $CLAUDE_DIR && PYTHONPATH=$CLAUDE_DIR $PY scripts/core/recall_learnings.py --query test --text-only"
  fi
else
  note "recall_learnings.py nieobecny ($CLAUDE_DIR/scripts/core/) — pomijam recall/learnings"
fi

# 2. learnings db (sqlite; w trybie postgres pomijane)
if [ "$PGMODE" -eq 1 ]; then
  note "DATABASE_URL ustawiony — backend postgres, pomijam check memory.db"
elif [ -f "$CLAUDE_DIR/cache/memory.db" ]; then
  n=$("$PY" -c "import sqlite3;print(sqlite3.connect('$CLAUDE_DIR/cache/memory.db').execute('SELECT count(*) FROM archival_memory').fetchone()[0])" 2>/dev/null)
  if [ -n "$n" ]; then ok "memory.db ($n wpisow)"; else bad "memory.db" "plik jest, ale query padl (schemat?)"; fi
else
  note "memory.db jeszcze nie istnieje — powstanie przy pierwszym store_learning"
fi

# 3. tldr CLI (jesli zainstalowany — regula tldr-cli.md)
if command -v tldr >/dev/null 2>&1; then
  if timeout 60 tldr tree "$CLAUDE_DIR/scripts" >/dev/null 2>&1; then
    ok "tldr ($(command -v tldr))"
  else
    bad "tldr" "jest na PATH, ale nie dziala (martwy shebang po upgrade pythona? pathspec>=1.0? patrz skill env-doctor)"
  fi
else
  note "tldr nieobecny — jesli reguly go reklamuja: uv tool install llm-tldr + pin 'pathspec<1.0'"
fi

# 4. hooki skompilowane + node
if command -v node >/dev/null 2>&1 && [ -f "$CLAUDE_DIR/hooks/dist/memory-awareness.mjs" ]; then
  ok "hooks dist/ + node"
else
  note "brak node lub hooks/dist/memory-awareness.mjs — hooki memory nieaktywne na tym urzadzeniu"
fi

# 5. memory-awareness hook end-to-end
if [ -f "$CLAUDE_DIR/hooks/memory-awareness.sh" ]; then
  out=$(echo '{"prompt":"selftest recall sqlite proot","cwd":"'"$HOME"'"}' | timeout 60 bash "$CLAUDE_DIR/hooks/memory-awareness.sh" 2>/dev/null)
  if echo "$out" | grep -q "MEMORY MATCH"; then
    ok "memory-awareness hook (MEMORY MATCH)"
  elif [ -n "$out" ] && echo "$out" | head -c1 | grep -q "{"; then
    ok "memory-awareness hook (dziala, brak matcha dla query selftest)"
  elif ! command -v uv >/dev/null 2>&1; then
    note "memory-awareness hook wymaga uv — brak uv na PATH"
  else
    bad "memory-awareness hook" "niepoprawny output: ${out:0:80}"
  fi
else
  note "memory-awareness.sh nieobecny — pomijam"
fi

# 6. epistemic-reminder hook (format wyjscia PostToolUse)
if command -v node >/dev/null 2>&1 && [ -f "$CLAUDE_DIR/hooks/dist/epistemic-reminder.mjs" ]; then
  eo=$(echo '{"tool_name":"Grep","tool_input":{"pattern":"x"}}' | timeout 30 node "$CLAUDE_DIR/hooks/dist/epistemic-reminder.mjs" 2>/dev/null)
  if echo "$eo" | grep -q "hookSpecificOutput"; then
    ok "epistemic-reminder hook (schemat hookSpecificOutput)"
  else
    bad "epistemic-reminder hook" "zly schemat wyjscia (stara wersja? zainstaluj z addonu env-doctor)"
  fi
else
  note "epistemic-reminder.mjs nieobecny lub brak node — pomijam"
fi

# 7. agentica (opcjonalna; INFO gdy nie chodzi)
if command -v agentica >/dev/null 2>&1; then
  # klasa znakow w pgrep: komenda zawierajaca slowo bez niej matchowalaby sama siebie
  if pgrep -f "[a]gentica" >/dev/null 2>&1; then ok "agentica (proces)"; else note "agentica zainstalowana, ale nie dziala (opcjonalna)"; fi
fi

# 8. dysk (>5GB wolne na partycji $HOME)
free_gb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')
if [ -n "$free_gb" ]; then
  if [ "$free_gb" -ge 5 ] 2>/dev/null; then ok "dysk (${free_gb}G wolne)"; else bad "dysk" "malo miejsca: ${free_gb}G"; fi
else
  note "df nieczytelny na tym hoscie — pomijam check dysku"
fi

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
