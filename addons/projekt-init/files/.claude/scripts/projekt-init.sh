#!/usr/bin/env bash
# projekt-init: szkielet zgodnosci NOWEGO projektu z globalnym CLAUDE.md (bramki od dnia zero).
# Uzycie: projekt-init.sh <katalog-projektu> [nazwa]
# Idempotentny ADD-IF-ABSENT: niczego nie nadpisuje; bezpieczny takze na istniejacym projekcie.
# Dziala po obu stronach granicy Termux/PRoot (uzywa tylko mkdir/cp/chmod/sed/grep/basename).
set -euo pipefail
T="${1:?Uzycie: projekt-init.sh <katalog-projektu> [nazwa]}"
N="${2:-$(basename "$T")}"
TPL="$HOME/.claude/scripts/projekt-init-templates"
[ -d "$TPL" ] || { echo "projekt-init: brak szablonow ($TPL) — pomijam."; exit 0; }
[ -d "$T" ] || { echo "projekt-init: katalog $T nie istnieje — pomijam."; exit 0; }

mkdir -p "$T/.claude/hooks"
for f in mark-dirty.sh stop-test-gate.sh; do
  [ -f "$T/.claude/hooks/$f" ] || cp "$TPL/$f" "$T/.claude/hooks/$f"
done
chmod +x "$T/.claude/hooks/mark-dirty.sh" "$T/.claude/hooks/stop-test-gate.sh"

[ -f "$T/.claude/settings.json" ] || cp "$TPL/settings.json" "$T/.claude/settings.json"

if [ ! -f "$T/CLAUDE.md" ]; then
  sed "s|{{NAZWA}}|$N|g" "$TPL/CLAUDE.md.template" > "$T/CLAUDE.md"
fi

grep -q '^\.claude/\.runtime/$' "$T/.gitignore" 2>/dev/null || echo '.claude/.runtime/' >> "$T/.gitignore"

echo "projekt-init: szkielet bramek gotowy w $T (Stop-gate cichy do czasu pojawienia sie testow; runner-override: .claude/test-command)."
