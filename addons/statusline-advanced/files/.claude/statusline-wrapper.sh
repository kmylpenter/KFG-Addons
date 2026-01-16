#!/bin/bash
# KFG Statusline Wrapper v5.4 (Android/Bash)
# Linia 1: ccstatusline (via npx)
# Linia 2: Cross-device Totals (z stats/user-{name}.json)

# === LINIA 1: ccstatusline ===
if command -v npx &> /dev/null; then
    npx -y ccstatusline@latest 2>/dev/null
else
    echo "ccstatusline: npx not found"
fi

# === LINIA 2: User Stats ===
STATS_DIR="$HOME/.claude-history/stats"
CONFIG_PATH="$HOME/.config/kfg-stats/users.json"

# Get defaultUser from config
USER_NAME="$USER"
if [ -f "$CONFIG_PATH" ] && command -v jq &> /dev/null; then
    DEFAULT_USER=$(jq -r '.defaultUser // empty' "$CONFIG_PATH" 2>/dev/null)
    [ -n "$DEFAULT_USER" ] && USER_NAME="$DEFAULT_USER"
fi

USER_STATS_FILE="$STATS_DIR/user-$USER_NAME.json"

if [ -f "$USER_STATS_FILE" ] && command -v jq &> /dev/null; then
    COST=$(jq -r '.cost // 0' "$USER_STATS_FILE" 2>/dev/null)
    TOKS=$(jq -r '.tokens_main // 0' "$USER_STATS_FILE" 2>/dev/null)
    DUR=$(jq -r '.duration_ms // 0' "$USER_STATS_FILE" 2>/dev/null)
    SESSIONS=$(jq -r '.sessions // 0' "$USER_STATS_FILE" 2>/dev/null)
    CHARS_USER=$(jq -r '.chars_user // 0' "$USER_STATS_FILE" 2>/dev/null)

    # Format tokens
    if [ "$TOKS" -gt 0 ]; then
        TOKS_M=$(echo "scale=2; $TOKS/1000000" | bc 2>/dev/null || echo "0")
    else
        TOKS_M="0"
    fi

    # Format typing time (chars_user / 285 char/min)
    if [ "$CHARS_USER" -gt 0 ]; then
        TYPING_MINS=$(echo "scale=0; $CHARS_USER/285" | bc 2>/dev/null || echo "0")
        TYPING_HOURS=$((TYPING_MINS / 60))
        TYPING_MINS_REM=$((TYPING_MINS % 60))
        TYPING_TIME="${TYPING_HOURS}h${TYPING_MINS_REM}m"
    else
        TYPING_TIME="0m"
    fi

    # Format cost
    if [ "$(echo "$COST >= 1000" | bc 2>/dev/null)" = "1" ]; then
        COST_FMT="\$$(echo "scale=1; $COST/1000" | bc 2>/dev/null)k"
    else
        COST_FMT="\$$(printf "%.2f" "$COST" 2>/dev/null || echo "0.00")"
    fi

    CYAN='\033[36m'
    PURPLE='\033[35m'
    YELLOW='\033[33m'
    RESET='\033[0m'
    echo -e "${CYAN}$USER_NAME${RESET} | ${YELLOW}${TYPING_TIME}${RESET} | ${PURPLE}${COST_FMT}${RESET} | ${SESSIONS} sess"
fi
