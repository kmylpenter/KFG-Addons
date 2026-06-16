#!/usr/bin/env bash
# Atomic deploy of the czytaj audit-2026-06-16 fixes: repo -> live runtime (~/.claude/hooks/czytaj).
# NEVER runs install.sh (it kills the warm daemon — regression 2026-06-15). Files only.
#
# The hook-path files take effect on the NEXT hook invocation (stop/pre-tool-use/UPS re-import
# fresh each time). The running volume_watcher keeps its OLD code in memory until a watcher restart
# — do that ONLY WHEN PARKED so hands-free read-back isn't interrupted mid-drive:
#     pkill -f '[v]olume_watcher\.py'      # the next UserPromptSubmit hook respawns it with new code
#     # (or simply: /czytaj off then /czytaj on)
set -u
SRC="/root/projekty/KFG-Addons/addons/czytaj/files/hooks/czytaj"
DST="$HOME/.claude/hooks/czytaj"
FILES=(_speak.py czytaj-env.sh czytaj_paths.py czytaj_selftest.py piper_stream.py
       pre-tool-use.sh stop.py toggle.sh user-prompt-submit.sh volume_watcher.py)
ok=0; fail=0
for f in "${FILES[@]}"; do
  if cp "$SRC/$f" "$DST/$f.deploytmp" 2>/dev/null && mv -f "$DST/$f.deploytmp" "$DST/$f" 2>/dev/null; then
    echo "  deployed $f"; ok=$((ok+1))
  else
    echo "  FAILED   $f"; fail=$((fail+1)); rm -f "$DST/$f.deploytmp" 2>/dev/null
  fi
done
echo "deployed=$ok failed=$fail"
echo "=== runtime selftest (live copy) ==="
python3 "$DST/czytaj_selftest.py" 2>&1 | tail -3
echo "NOTE: volume_watcher M1/M2/M3/M4/M14 need a watcher restart (see header) — do it WHEN PARKED."
