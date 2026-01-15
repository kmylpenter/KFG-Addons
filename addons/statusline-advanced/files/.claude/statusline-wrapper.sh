#!/bin/bash
# KFG Statusline Wrapper v2.0 (Android/Bash)
# Linia 1: ccstatusline (via npx)
# Linia 2: Cross-device Totals (z stats/device-*.json)

# === LINIA 1: ccstatusline ===
if command -v npx &> /dev/null; then
    npx -y ccstatusline@latest 2>/dev/null
else
    echo "ccstatusline: npx not found"
fi

# === LINIA 2: Cross-device Totals ===
STATS_DIRS=(
    "$HOME/.claude/stats"
    "$HOME/projekty/KFG/stats"
)

TOTAL_COST=0
TOTAL_TOKENS=0
TOTAL_DURATION=0
DEVICE_COUNT=0

for STATS_DIR in "${STATS_DIRS[@]}"; do
    [ -d "$STATS_DIR" ] || continue

    for f in "$STATS_DIR"/device-*.json; do
        [ -f "$f" ] || continue

        if command -v jq &> /dev/null; then
            COST=$(jq -r '.cost // 0' "$f" 2>/dev/null)
            TOKS=$(jq -r '.tokens_main // 0' "$f" 2>/dev/null)
            DUR=$(jq -r '.duration_ms // 0' "$f" 2>/dev/null)

            TOTAL_COST=$(echo "$TOTAL_COST + $COST" | bc 2>/dev/null || echo "$TOTAL_COST")
            TOTAL_TOKENS=$((TOTAL_TOKENS + TOKS))
            TOTAL_DURATION=$((TOTAL_DURATION + DUR))
            DEVICE_COUNT=$((DEVICE_COUNT + 1))
        fi
    done
done

if [ "$DEVICE_COUNT" -gt 0 ]; then
    if [ "$TOTAL_TOKENS" -gt 0 ]; then
        TOKS_M=$(echo "scale=2; $TOTAL_TOKENS/1000000" | bc 2>/dev/null || echo "0")
    else
        TOKS_M="0"
    fi
    HOURS=$(echo "scale=1; $TOTAL_DURATION/3600000" | bc 2>/dev/null || echo "0")
    COST_FMT=$(printf "%.2f" "$TOTAL_COST" 2>/dev/null || echo "0.00")

    CYAN='\033[36m'
    RESET='\033[0m'
    echo -e "${CYAN}Totals: ${TOKS_M}M tok | ${HOURS}h | \$${COST_FMT} | ${DEVICE_COUNT} dev${RESET}"
fi
