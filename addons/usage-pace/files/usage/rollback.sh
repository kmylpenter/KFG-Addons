#!/usr/bin/env bash
# ============================================================================
# rollback.sh — JEDNA komenda przywracajaca stan sprzed usage-pace:
#     bash ~/.claude/usage/rollback.sh
#
# 1. Przywraca oryginalny pasek statusu z backupu (.bak-2026-06-10).
# 2. Odwoluje job harmonogramu (gdy uruchomione w Termuksie; w proot
#    wypisze komende do wklejenia).
# 3. NIE kasuje danych (cache/historia/skrypty) — sa nieszkodliwe bez paska.
#    Pelne czyszczenie: bash rollback.sh --purge (zapyta o potwierdzenie).
#
# Ponowne wlaczenie po rollbacku:
#     cp ~/.claude/usage/statusline-wrapper.usage-pace.mjs ~/.claude/statusline-wrapper.mjs
# ============================================================================
set -u
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
[ -d "$CLAUDE_DIR" ] || CLAUDE_DIR=/data/data/com.termux/files/home/.claude
[ -d "$CLAUDE_DIR" ] || CLAUDE_DIR=/root/.claude
WRAPPER="$CLAUDE_DIR/statusline-wrapper.mjs"
BAK="$CLAUDE_DIR/statusline-wrapper.mjs.bak-2026-06-10"
BAK2="$CLAUDE_DIR/usage/backup-2026-06-10/statusline-wrapper.mjs.orig"
JOB_ID=7301

echo "== usage-pace: rollback =="

# -- 1. pasek statusu --
if [ ! -f "$BAK" ] && [ -f "$BAK2" ]; then BAK="$BAK2"; fi
if [ -f "$BAK" ]; then
  if [ -f "$BAK2" ] && ! cmp -s "$BAK" "$BAK2"; then
    echo "UWAGA: dwa backupy roznia sie — uzywam $BAK"
  fi
  cp "$WRAPPER" "$WRAPPER.przed-rollbackiem.$(date +%s)" 2>/dev/null
  cp "$BAK" "$WRAPPER" && echo "OK: pasek statusu przywrocony z $BAK"
  cmp -s "$WRAPPER" "$BAK" && echo "OK: weryfikacja — plik identyczny z backupem" \
    || { echo "BLAD: weryfikacja nie przeszla!"; exit 1; }
else
  echo "BLAD: brak backupu ($BAK)"; exit 1
fi

# -- 2. harmonogram --
case "$HOME" in
  /data/data/com.termux/files/home*)
    if command -v termux-job-scheduler >/dev/null 2>&1; then
      termux-job-scheduler --cancel --job-id "$JOB_ID" 2>&1 | grep -v "^WARNING: linker"
      echo "OK: job $JOB_ID odwolany"
    fi ;;
  *)
    echo "INFO: jestes w proot — job odwolasz wklejajac W TERMUKSIE:"
    echo "  termux-job-scheduler --cancel --job-id $JOB_ID" ;;
esac

# -- 3. opcjonalne czyszczenie danych --
if [ "${1:-}" = "--purge" ]; then
  echo "Do skasowania:"
  ls -la "$CLAUDE_DIR/usage-cache.json" "$CLAUDE_DIR/usage-history.csv" 2>/dev/null
  echo "oraz caly katalog $CLAUDE_DIR/usage/ (skrypty, logi, backupy!)"
  printf "Na pewno? [y/N] "
  read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    rm -f "$CLAUDE_DIR/usage-cache.json" "$CLAUDE_DIR/usage-history.csv"
    rm -rf "$CLAUDE_DIR/usage"
    echo "OK: dane usuniete"
  else
    echo "Pominieto czyszczenie"
  fi
else
  echo "INFO: cache/historia/skrypty zostaja (nieszkodliwe). Pelne czyszczenie: rollback.sh --purge"
fi

echo "== rollback zakonczony — pasek wroci przy nastepnym odswiezeniu =="
