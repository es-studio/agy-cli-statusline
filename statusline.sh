#!/bin/bash

# ANSI Color Codes
RESET="\033[0m"
GREY="\033[90m"
CYAN="\033[36m"
BOLD_CYAN="\033[1;36m"
GREEN="\033[32m"
BOLD_GREEN="\033[1;32m"
YELLOW="\033[33m"
BOLD_BLUE="\033[1;34m"
RED="\033[31m"
MAGENTA="\033[35m"

# Separator
SEP=" ${GREY}·${RESET} "

# 0. Quota check bypass to prevent infinite loop / fork bomb
if [ "$AGY_QUOTA_CHECK" = "1" ]; then
    echo ""
    exit 0
fi

# 1. Input JSON from Antigravity CLI
INPUT_JSON=$(cat)

# 2. Parse values using jq if available
if command -v jq &>/dev/null; then
    # Get model display name or ID
    MODEL=$(echo "$INPUT_JSON" | jq -r '.model | if type == "object" then .display_name // .id else . // "Unknown" end')
    
    # Remaining context percentage (ctx)
    REMAINING=$(echo "$INPUT_JSON" | jq -r '((.context_window.remaining_percentage // 100) * 10 | round) / 10')
    
    # Format token counts
    IN_TOKENS=$(echo "$INPUT_JSON" | jq -r '
      def format_num:
        if . >= 1000000 then
          ((. / 100000) | round / 10 | tostring) + "m"
        elif . >= 1000 then
          ((. / 100) | round / 10 | tostring) + "k"
        else
          tostring
        end;
      .context_window.total_input_tokens // 0 | format_num
    ')
    
    OUT_TOKENS=$(echo "$INPUT_JSON" | jq -r '
      def format_num:
        if . >= 1000000 then
          ((. / 100000) | round / 10 | tostring) + "m"
        elif . >= 1000 then
          ((. / 100) | round / 10 | tostring) + "k"
        else
          tostring
        end;
      .context_window.total_output_tokens // 0 | format_num
    ')
    
    # Format in / out tokens
    TOKENS="in:${IN_TOKENS} / out:${OUT_TOKENS}"
    
    # Current directory
    CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // ""')
    
    # Additional requested fields
    STATE=$(echo "$INPUT_JSON" | jq -r '.agent_state // "idle"')
    ARTIFACTS=$(echo "$INPUT_JSON" | jq -r '.artifact_count // 0')
    VERSION=$(echo "$INPUT_JSON" | jq -r '.version // "unknown"')
    PLAN=$(echo "$INPUT_JSON" | jq -r '.plan_tier // "unknown"')
else
    MODEL="Antigravity"
    REMAINING="100"
    TOKENS="in:0 / out:0"
    CWD=""
    STATE="idle"
    ARTIFACTS="0"
    VERSION="unknown"
    PLAN="unknown"
fi

# 3. Read Usage Quota from Cache (5h:X%) & Trigger Async Refresh
CACHE_DIR="$HOME/.gemini/antigravity-cli"
CACHE_FILE="$CACHE_DIR/quota_cache.txt"
QUOTA_VAL=""

# Determine if cache needs updating (e.g. older than 30 seconds or doesn't exist)
TRIGGER_REFRESH=0
CURRENT_TIME=$(date +%s)

if [ -f "$CACHE_FILE" ]; then
    # Use -F (Fixed strings) to prevent regex evaluation of parenthesis or dots in model name
    QUOTA_VAL=$(grep -F "${MODEL}:" "$CACHE_FILE" | cut -d':' -f2- | tr -d '\r' | xargs)
    
    CACHE_MOD_TIME=$(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((CURRENT_TIME - CACHE_MOD_TIME))
    if [ $AGE -gt 30 ]; then
        TRIGGER_REFRESH=1
    fi
else
    TRIGGER_REFRESH=1
fi

# Default fallback if cache doesn't have the value
if [ -z "$QUOTA_VAL" ]; then
    QUOTA_VAL="N/A"
fi

# Run background update using the tmux scraper if needed.
# Instead of file/directory locking, we check if the scraper is already running.
if [ $TRIGGER_REFRESH -eq 1 ]; then
    if ! pgrep -f "update_quota_cache.sh" &>/dev/null; then
        bash "$CACHE_DIR/update_quota_cache.sh" &>/dev/null &
    fi
fi

# 4. Format directory suffix (basename of CWD)
if [ -n "$CWD" ]; then
    DIR_SUFFIX=$(basename "$CWD")
    MODEL_DIR_INFO="${BOLD_CYAN}${MODEL}${RESET}${SEP}${BOLD_BLUE}${DIR_SUFFIX}${RESET}"
else
    MODEL_DIR_INFO="${BOLD_CYAN}${MODEL}${RESET}"
fi

# 5. Get current Git branch name if inside a git repository
GIT_BRANCH=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
    GIT_BRANCH=$(cd "$CWD" && git branch --show-current 2>/dev/null)
fi
if [ -n "$GIT_BRANCH" ]; then
    GIT_INFO="${SEP}${GREEN}git:$GIT_BRANCH${RESET}"
else
    GIT_INFO=""
fi

# 6. Format colors based on values
# Context remaining percentage color
REMAINING_INT=${REMAINING%.*}
if [ -z "$REMAINING_INT" ]; then REMAINING_INT=100; fi
if [ "$REMAINING_INT" -gt 50 ]; then
    COLOR_REM=$BOLD_GREEN
elif [ "$REMAINING_INT" -gt 20 ]; then
    COLOR_REM=$YELLOW
else
    COLOR_REM=$RED
fi
REM_INFO="${COLOR_REM}ctx:${REMAINING}%${RESET}"

# Split QUOTA_VAL into 5h and 7d using the pipe delimiter
QUOTA_5H="${QUOTA_VAL%%|*}"
QUOTA_7D="${QUOTA_VAL#*|}"
if [ "$QUOTA_5H" = "$QUOTA_7D" ]; then
    QUOTA_7D="N/A"
fi

format_quota() {
    local val="$1"
    local prefix="$2"
    
    if [ -z "$val" ] || [ "$val" = "N/A" ]; then
        echo -n "${GREY}${prefix}:N/A${RESET}"
        return
    fi
    
    local q_int=$(echo "$val" | grep -oE "^[0-9]+")
    local color=$GREY
    if [[ "$q_int" =~ ^[0-9]+$ ]]; then
        if [ "$q_int" -gt 50 ]; then
            color=$BOLD_GREEN
        elif [ "$q_int" -gt 20 ]; then
            color=$YELLOW
        else
            color=$RED
        fi
    fi
    
    local display="$val"
    if [[ "$val" == *":"* ]]; then
        local pct_part="${val%%:*}"
        local time_part="${val#*:}"
        
        if [ "$prefix" = "7d" ] && [[ "$time_part" == *"h "* ]]; then
            local hours=$(echo "$time_part" | grep -oE "^[0-9]+")
            if [ -n "$hours" ] && [ "$hours" -ge 24 ]; then
                local days=$((hours / 24))
                local rem_hours=$((hours % 24))
                time_part="${days}d ${rem_hours}h"
            fi
        fi
        
        display="${pct_part} (${time_part})"
    fi
    echo -n "${color}${prefix}:${display}${RESET}"
}

USED_INFO_7D=$(format_quota "$QUOTA_7D" "7d")
USED_INFO_5H=$(format_quota "$QUOTA_5H" "5h")

USED_INFO="${USED_INFO_5H}${SEP}${USED_INFO_7D}"

# Format others
TOKENS_INFO="${YELLOW}${TOKENS}${RESET}"
PLAN_INFO="${CYAN}${PLAN}${RESET}"
VERSION_INFO="${GREY}v$VERSION${RESET}"

# 7. Output the formatted string to stdout
echo -e "${MODEL_DIR_INFO}${GIT_INFO}${SEP}${TOKENS_INFO}${SEP}${REM_INFO}${SEP}${USED_INFO}${SEP}${PLAN_INFO}${SEP}${VERSION_INFO}"
