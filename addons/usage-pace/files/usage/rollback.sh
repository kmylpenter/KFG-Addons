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
JOB_ID=7301

echo "== usage-pace: rollback =="

# -- 1. pasek statusu: znajdz backup BEZ sztywnej daty --
# Priorytet: pristine .orig (zapisany raz) -> najnowszy bak-* -> legacy backup-*/orig
BAK=""
if [ -f "$CLAUDE_DIR/usage/backup/statusline-wrapper.mjs.orig" ]; then
  BAK="$CLAUDE_DIR/usage/backup/statusline-wrapper.mjs.orig"
else
  # najnowszy plik bak-* (sortowanie po nazwie = po czasie, bo stempel ISO/sekundowy)
  newest="$(ls -1t "$CLAUDE_DIR"/statusline-wrapper.mjs.bak-* 2>/dev/null | head -1)"
  [ -n "$newest" ] && BAK="$newest"
  # legacy: dawne backup-DATA/orig
  [ -z "$BAK" ] && BAK="$(ls -1t "$CLAUDE_DIR"/usage/backup-*/statusline-wrapper.mjs.orig 2>/dev/null | head -1)"
fi

if [ -n "$BAK" ] && [ -f "$BAK" ]; then
  cp "$WRAPPER" "$WRAPPER.przed-rollbackiem.$(date +%s)" 2>/dev/null || true
  cp "$BAK" "$WRAPPER" && echo "OK: pasek statusu przywrocony z $BAK"
  cmp -s "$WRAPPER" "$BAK" && echo "OK: weryfikacja — plik identyczny z backupem" \
    || { echo "BLAD: weryfikacja nie przeszla!"; exit 1; }
else
  echo "BLAD: brak jakiegokolwiek backupu paska w $CLAUDE_DIR (.orig / bak-*)"; exit 1
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
