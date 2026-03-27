#!/bin/bash
# large-file-read-guard.sh - PreToolUse hook for Read
# Warns when reading files >2000 lines without offset/limit
# Prevents truncated reads on 4000-6000 line project files

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE_PATH" ] && echo '{}' && exit 0
[ ! -f "$FILE_PATH" ] && echo '{}' && exit 0

# If user already specified offset/limit, don't interfere
HAS_LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty' 2>/dev/null)
HAS_OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty' 2>/dev/null)
[ -n "$HAS_LIMIT" ] && echo '{}' && exit 0
[ -n "$HAS_OFFSET" ] && echo '{}' && exit 0

# Skip non-text files
case "$FILE_PATH" in
  *.png|*.jpg|*.gif|*.pdf|*.zip|*.tar*|*.gz|*.bin) echo '{}' && exit 0 ;;
esac

LINES=$(wc -l < "$FILE_PATH" 2>/dev/null)
[ -z "$LINES" ] && echo '{}' && exit 0

THRESHOLD=2000

if [ "$LINES" -gt "$THRESHOLD" ]; then
  CHUNKS=$(( (LINES + THRESHOLD - 1) / THRESHOLD ))
  echo "{\"decision\":\"report\",\"reason\":\"LARGE FILE: $FILE_PATH has $LINES lines. Read shows only first $THRESHOLD. Use offset/limit for $CHUNKS chunks of ~$THRESHOLD lines each.\"}"
else
  echo '{}'
fi
