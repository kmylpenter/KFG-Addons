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
STAMP="$(date +%Y-%m-%d-%H%M%S)"   # M15: sekundowy — brak kolizji przy 2 instalach tego samego dnia

echo "== usage-pace: instalacja (proot) =="

command -v node >/dev/null || { echo "BLAD: brak node"; exit 1; }
command -v python3 >/dev/null || { echo "BLAD: brak python3"; exit 1; }
[ -f "$WRAPPER" ] || { echo "BLAD: brak $WRAPPER — ten addon patchuje istniejacy pasek KFG"; exit 1; }

mkdir -p "$USAGE_DIR/test" "$USAGE_DIR/backup"

# -- 1. backup pre-patch wrappera (ZAWSZE, do istniejacej sciezki) --
BAK="$CLAUDE_DIR/statusline-wrapper.mjs.bak-$STAMP"
cp "$WRAPPER" "$BAK"
ORIG="$USAGE_DIR/backup/statusline-wrapper.mjs.orig"
[ -f "$ORIG" ] || cp "$WRAPPER" "$ORIG"   # M15: pristine zapisany RAZ, nigdy nadpisany nie-oryginalem
cp "$CLAUDE_DIR/settings.json" "$USAGE_DIR/backup/settings.json.orig.$STAMP" 2>/dev/null || true

SAMPLE="$USAGE_DIR/test/golden-input-sample.json"
[ -f "$SAMPLE" ] || cat > "$SAMPLE" <<'EOF'
{"session_id":"golden-test-fixed","cwd":"/root/projekty/KFG-Addons","model":{"id":"claude-fable-5[1m]","display_name":"Fable 5"},"workspace":{"project_dir":"/root/projekty/KFG-Addons"},"transcript_path":"/root/.claude/usage/test/nonexistent.jsonl","context_window":{"context_window_size":1000000,"used_percentage":37}}
EOF

# -- golden z PRE-PATCH wrappera, REGENEROWANY co instalacje, z SANITY (M34) --
# (stara wersja pinowala golden raz na zawsze i maskowala blad node przez '|| true',
#  przez co zepsuty pasek przechodzil regresje "bajt w bajt")
GOLD="$USAGE_DIR/test/golden-output.txt"
if CLAUDE_USAGE_CACHE_FILE=/nonexistent-usage-cache.json CLAUDE_CODE_EFFORT_LEVEL=max \
     node "$WRAPPER" < "$SAMPLE" > "$GOLD.tmp" 2>"$GOLD.err" \
   && [ -s "$GOLD.tmp" ] \
   && ! grep -qiE 'syntaxerror|error:|err_|cannot find|throw ' "$GOLD.tmp"; then
  mv "$GOLD.tmp" "$GOLD"
else
  echo "BLAD: node nie potrafi uruchomic obecnego paska (golden niewiarygodny) — przerywam BEZ zmian."
  head -3 "$GOLD.err" 2>/dev/null
  rm -f "$GOLD.tmp" "$GOLD.err"
  exit 1
fi
rm -f "$GOLD.err"

# -- 2. pliki + podmiana paska --
cp "$ADDON_DIR"/files/usage/*.sh "$USAGE_DIR/"
cp "$NEW_WRAPPER" "$USAGE_DIR/statusline-wrapper.usage-pace.mjs"
chmod +x "$USAGE_DIR"/*.sh
cp "$NEW_WRAPPER" "$WRAPPER"
echo "OK: skrypty w $USAGE_DIR, pasek podmieniony"

# -- 3. regresja: bez danych usage NOWY pasek MUSI dac wyjscie == golden --
if CLAUDE_USAGE_CACHE_FILE=/nonexistent-usage-cache.json CLAUDE_CODE_EFFORT_LEVEL=max \
     node "$WRAPPER" < "$SAMPLE" > "$GOLD.po" 2>/dev/null && cmp -s "$GOLD" "$GOLD.po"; then
  echo "OK: regresja — stare wyjscie bajt w bajt"
  rm -f "$GOLD.po"
else
  echo "BLAD REGRESJI — przywracam pasek z backupu!"
  if   [ -f "$BAK" ];  then cp "$BAK"  "$WRAPPER"; echo "  przywrocono z $BAK"
  elif [ -f "$ORIG" ]; then cp "$ORIG" "$WRAPPER"; echo "  przywrocono z $ORIG"
  else echo "  UWAGA: brak backupu do przywrocenia — pasek pozostaje podmieniony!"; fi
  rm -f "$GOLD.po"
  exit 1
fi

# -- 4. testy progow pace.sh --
bash "$ADDON_DIR/files/usage/run-pace-tests.sh" >/dev/null 2>&1 \
  && echo "OK: testy progow pace.sh przeszly" \
  || echo "UWAGA: testy pace.sh nie przeszly — sprawdz run-pace-tests.sh"

# -- 5. C4: czy ~/.claude jest WSPOLDZIELONY z Termuksem? (krok reczny tego wymaga) --
TERMUX_HOME=/data/data/com.termux/files/home
if [ -d "$TERMUX_HOME" ]; then
  MARKER="$USAGE_DIR/.bind-check"
  echo "$STAMP" > "$MARKER" 2>/dev/null || true
  if [ "$(cat "$TERMUX_HOME/.claude/usage/.bind-check" 2>/dev/null)" != "$STAMP" ]; then
    echo ""
    echo "== UWAGA: ~/.claude w proot NIE jest wspoldzielony z Termuksem =="
    echo "   Krok w Termuksie nie zobaczy tych plikow, a wspolny cache rozjedzie sie na dwa."
    echo "   Wspoldziel katalog (przyklad — przy starcie proot dodaj bind):"
    echo "     proot-distro login <distro> --bind $CLAUDE_DIR:$TERMUX_HOME/.claude"
    echo "   albo skopiuj ~/.claude/usage/ na strone Termuksa recznie przed krokiem nizej."
  fi
  rm -f "$MARKER"
fi

echo ""
echo "== ZOSTAL JEDEN KROK RECZNY — wklej W TERMUKSIE (nie w proot): =="
echo "   bash ~/.claude/usage/install-termux.sh"
