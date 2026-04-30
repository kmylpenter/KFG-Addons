#!/usr/bin/env bash
# ssot-dry-audit installer (Termux + generic Linux/macOS).
# Backups existing files, atomic writes via tmp+mv, legacy command cleanup.

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SKILL_DST="$CLAUDE_DIR/skills/ssot-dry-audit"
CMD_DST="$CLAUDE_DIR/commands"
TS=$(date +%Y%m%d-%H%M%S)

echo ""
echo "==> Instalacja addonu: ssot-dry-audit v2.0"
echo ""

if ! command -v python3 >/dev/null 2>&1; then
  echo "  [X] BRAK: python3 (wymagany)."
  echo "      Termux: pkg install python"
  echo "      Linux:  apt install python3"
  echo "      macOS:  brew install python3"
  exit 1
fi

PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "  [OK] python3: $PY_VER"

# Helper requires Python 3.10+ (uses `list[dict]` and `| None` syntax).
PY_OK=$(python3 -c 'import sys; print(int(sys.version_info >= (3, 10)))')
if [ "$PY_OK" != "1" ]; then
  echo "  [X] python3 $PY_VER za stary — wymagany 3.10+"
  exit 1
fi

mkdir -p "$SKILL_DST/scripts" "$CMD_DST"

# atomic_install <src> <dst>: backup existing, write to .tmp, mv into place.
atomic_install() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [ -f "$dst" ]; then
    cp -p "$dst" "$dst.bak.$TS"
    echo "  [--] backup: ${dst##*/} → ${dst##*/}.bak.$TS"
  fi
  cp "$src" "$dst.tmp"
  mv "$dst.tmp" "$dst"
  chmod 644 "$dst"
  echo "  [OK] $label"
}

atomic_install \
  "$ADDON_DIR/files/.claude/skills/ssot-dry-audit/SKILL.md" \
  "$SKILL_DST/SKILL.md" \
  "skills/ssot-dry-audit/SKILL.md"

atomic_install \
  "$ADDON_DIR/files/.claude/skills/ssot-dry-audit/scripts/detect_duplicates.py" \
  "$SKILL_DST/scripts/detect_duplicates.py" \
  "skills/ssot-dry-audit/scripts/detect_duplicates.py"
chmod 755 "$SKILL_DST/scripts/detect_duplicates.py"

atomic_install \
  "$ADDON_DIR/files/.claude/commands/audytssot.md" \
  "$CMD_DST/audytssot.md" \
  "commands/audytssot.md"

# Remove legacy command names from previous versions.
for legacy in "audyt-ssot.md" "naprawssot.md"; do
  if [ -f "$CMD_DST/$legacy" ]; then
    rm -f "$CMD_DST/$legacy"
    echo "  [--] usunieto stara nazwe commands/$legacy"
  fi
done

# Smoke test: helper parses + reports schema_version.
SCHEMA=$(python3 -c "
import json, subprocess, sys, tempfile, os
with tempfile.TemporaryDirectory() as td:
    os.chdir(td)
    r = subprocess.run(['python3', '$SKILL_DST/scripts/detect_duplicates.py', '.'],
                        capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        sys.exit(f'helper exit {r.returncode}: {r.stderr}')
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError as e:
        sys.exit(f'helper output not JSON: {e}')
    print(data.get('schema_version', 'MISSING'))
" 2>&1) || { echo "  [X] smoke test failed: $SCHEMA"; exit 1; }

if [ "$SCHEMA" = "2.0" ]; then
  echo "  [OK] helper smoke test: schema_version=$SCHEMA"
else
  echo "  [X] helper schema mismatch (got '$SCHEMA', expected '2.0')"
  exit 1
fi

echo ""
echo "==> Gotowe (v2.0 — pure audit)"
echo ""
echo "Uzycie:"
echo "  /audytssot              -> audyt cwd"
echo "  /audytssot src/         -> audyt zawezony"
echo "  'zrob audyt SSOT'       -> aktywacja po frazie"
echo ""
echo "Output:"
echo "  SSOT_DRY_AUDIT_REPORT.md (czytelny raport, auto-gitignored)"
echo "  .ssot-findings.yaml      (maszynowy handoff dla petla solve)"
echo ""
echo "Naprawa: /petla solve .ssot-findings.yaml"
