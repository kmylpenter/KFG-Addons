#!/usr/bin/env bash
# usage-pace — installer (strona proot/Ubuntu).
# Kopiuje skrypty do ~/.claude/usage/, robi backup + golden test paska,
# podmienia statusline-wrapper.mjs na wersje z segmentem usage-pace,
# weryfikuje regresje (stare wyjscie bajt w bajt). settings.json NIE jest ruszany.
set -eu

ADDON_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
USAGE_DIR="$CLAUDE_DIR/usage"
WRAPPER="$CLAUDE_DIR/statusline-wrapper.mjs"
NEW_WRAPPER="$ADDON_DIR/files/statusline-wrapper.usage-pace.mjs"
STAMP="$(date +%Y-%m-%d)"

echo "== usage-pace: instalacja (proot) =="

command -v node >/dev/null || { echo "BLAD: brak node"; exit 1; }
command -v python3 >/dev/null || { echo "BLAD: brak python3"; exit 1; }
[ -f "$WRAPPER" ] || { echo "BLAD: brak $WRAPPER — ten addon patchuje istniejacy pasek KFG"; exit 1; }

mkdir -p "$USAGE_DIR/test" "$USAGE_DIR/backup-$STAMP"

# -- 1. backup + golden (przed jakakolwiek zmiana) --
if ! cmp -s "$WRAPPER" "$NEW_WRAPPER"; then
  cp "$WRAPPER" "$CLAUDE_DIR/statusline-wrapper.mjs.bak-$STAMP"
  cp "$WRAPPER" "$USAGE_DIR/backup-$STAMP/statusline-wrapper.mjs.orig"
  cp "$CLAUDE_DIR/settings.json" "$USAGE_DIR/backup-$STAMP/settings.json.orig" 2>/dev/null || true
  echo "OK: backup -> statusline-wrapper.mjs.bak-$STAMP"
fi
SAMPLE="$USAGE_DIR/test/golden-input-sample.json"
[ -f "$SAMPLE" ] || cat > "$SAMPLE" <<'EOF'
{"session_id":"golden-test-fixed","cwd":"/root/projekty/KFG-Addons","model":{"id":"claude-fable-5[1m]","display_name":"Fable 5"},"workspace":{"project_dir":"/root/projekty/KFG-Addons"},"transcript_path":"/root/.claude/usage/test/nonexistent.jsonl","context_window":{"context_window_size":1000000,"used_percentage":37}}
EOF
GOLD="$USAGE_DIR/test/golden-output.txt"
CLAUDE_CODE_EFFORT_LEVEL=max node "$WRAPPER" < "$SAMPLE" > "$GOLD.now" 2>&1 || true
[ -f "$GOLD" ] || cp "$GOLD.now" "$GOLD"

# -- 2. pliki --
cp "$ADDON_DIR"/files/usage/*.sh "$USAGE_DIR/"
cp "$NEW_WRAPPER" "$USAGE_DIR/statusline-wrapper.usage-pace.mjs"
chmod +x "$USAGE_DIR"/*.sh
cp "$NEW_WRAPPER" "$WRAPPER"
echo "OK: skrypty w $USAGE_DIR, pasek podmieniony"

# -- 3. regresja: bez danych usage wyjscie MUSI byc identyczne z goldenem --
CLAUDE_USAGE_CACHE_FILE=/nonexistent-usage-cache.json CLAUDE_CODE_EFFORT_LEVEL=max \
  node "$WRAPPER" < "$SAMPLE" > "$GOLD.po" 2>&1 || true
if cmp -s "$GOLD" "$GOLD.po"; then
  echo "OK: regresja — stare wyjscie bajt w bajt"
else
  echo "BLAD REGRESJI — przywracam backup!"
  cp "$CLAUDE_DIR/statusline-wrapper.mjs.bak-$STAMP" "$WRAPPER"
  exit 1
fi

# -- 4. testy progow pace.sh --
bash "$ADDON_DIR/files/usage/run-pace-tests.sh" >/dev/null 2>&1 \
  && echo "OK: testy progow pace.sh przeszly" \
  || echo "UWAGA: testy pace.sh nie przeszly — sprawdz run-pace-tests.sh"

echo ""
echo "== ZOSTAL JEDEN KROK RECZNY — wklej W TERMUKSIE (nie w proot): =="
echo "   bash ~/.claude/usage/install-termux.sh"
