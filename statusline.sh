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

# Run background update in a subshell if needed.
# Instead of file/directory locking, we check if a sync process with "AGY_QUOTA_CHECK=1" is already running.
# This makes the refresh trigger idempotent and completely avoids lock cleanup problems.
if [ $TRIGGER_REFRESH -eq 1 ]; then
    if ! pgrep -f "AGY_QUOTA_CHECK=1" &>/dev/null; then
        (
            # Detect agy binary path
            if command -v agy &>/dev/null; then
                AGY_BIN=$(command -v agy)
            elif [ -f "$HOME/.local/bin/agy" ]; then
                AGY_BIN="$HOME/.local/bin/agy"
            else
                AGY_BIN="agy"
            fi
            
            # Fetch usage non-interactively
            usage_output=$(env AGY_QUOTA_CHECK=1 "$AGY_BIN" -p "/usage" 2>/dev/null)
            
            if [ -n "$usage_output" ]; then
                TEMP_CACHE=$(mktemp)
                
                MODELS=(
                  "Gemini 3.5 Flash (Medium)"
                  "Gemini 3.5 Flash (High)"
                  "Gemini 3.5 Flash (Low)"
                  "Gemini 3.1 Pro (Low)"
                  "Gemini 3.1 Pro (High)"
                  "Claude Sonnet 4.6 (Thinking)"
                  "Claude Opus 4.6 (Thinking)"
                  "GPT-OSS 120B (Medium)"
                )
                
                IFS=$'\n'
                lines=($(echo -e "$usage_output"))
                num_lines=${#lines[@]}

                for model in "${MODELS[@]}"; do
                    found_pct=""
                    has_quota_available=0
                    for ((i=0; i<num_lines; i++)); do
                        line="${lines[$i]}"
                        if [[ "$line" == "- $model"* ]]; then
                            for ((j=1; j<=5; j++)); do
                                if (( i+j < num_lines )); then
                                    next_line="${lines[$((i+j))]}"
                                    if [[ "$next_line" == "- "* ]]; then
                                        break
                                    fi
                                    if [[ "$next_line" == *"Quota available"* ]]; then
                                        has_quota_available=1
                                        break
                                    fi
                                    if [[ "$next_line" == *"remaining"* ]] && [[ "$next_line" == *"Refreshes in"* ]]; then
                                        pct=$(echo "$next_line" | grep -oE "[0-9]+%" | head -n 1)
                                        ref_time=$(echo "$next_line" | sed -n 's/.*Refreshes in //p' | xargs)
                                        if [ -n "$pct" ] && [ -n "$ref_time" ]; then
                                            found_pct="${pct}:${ref_time}"
                                            break
                                        fi
                                    fi
                                    if [[ "$next_line" == *"%"* ]]; then
                                        pct=$(echo "$next_line" | grep -oE "[0-9]+%" | head -n 1)
                                        if [ -n "$pct" ] && [ -z "$found_pct" ]; then
                                            found_pct="$pct"
                                        fi
                                    fi
                                fi
                            done
                            break
                        fi
                    done
                    
                    quota="N/A"
                    if [ $has_quota_available -eq 1 ]; then
                        quota="100%"
                    elif [ -n "$found_pct" ]; then
                        quota="$found_pct"
                    fi

                    echo "${model}:${quota}" >> "$TEMP_CACHE"
                done
                
                if [ -s "$TEMP_CACHE" ]; then
                    mv "$TEMP_CACHE" "$CACHE_FILE"
                    chmod 600 "$CACHE_FILE" 2>/dev/null || true
                else
                    rm -f "$TEMP_CACHE"
                fi
            fi
        ) &>/dev/null &
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

# Quota remaining percentage color (5h)
QUOTA_INT=$(echo "$QUOTA_VAL" | grep -oE "^[0-9]+")
if [ -z "$QUOTA_INT" ] || ! [[ "$QUOTA_INT" =~ ^[0-9]+$ ]]; then
    COLOR_QUOTA=$GREY
else
    if [ "$QUOTA_INT" -gt 50 ]; then
        COLOR_QUOTA=$BOLD_GREEN
    elif [ "$QUOTA_INT" -gt 20 ]; then
        COLOR_QUOTA=$YELLOW
    else
        COLOR_QUOTA=$RED
    fi
fi

# Format display quota nicely (e.g., 60%:50m -> 60% (50m))
if [[ "$QUOTA_VAL" == *":"* ]]; then
    pct_part=${QUOTA_VAL%%:*}
    time_part=${QUOTA_VAL#*:}
    DISPLAY_QUOTA="${pct_part} (${time_part})"
else
    DISPLAY_QUOTA="$QUOTA_VAL"
fi
USED_INFO="${COLOR_QUOTA}5h:${DISPLAY_QUOTA}${RESET}"

# Agent State color
if [ "$STATE" = "working" ]; then
    STATE_INFO="${RED}${STATE}${RESET}"
else
    STATE_INFO="${GREEN}${STATE}${RESET}"
fi

# Format others
TOKENS_INFO="${YELLOW}${TOKENS}${RESET}"
ARTS_INFO="${MAGENTA}arts:$ARTIFACTS${RESET}"
PLAN_INFO="${CYAN}${PLAN}${RESET}"
VERSION_INFO="${GREY}v$VERSION${RESET}"

# 7. Output the formatted string to stdout
echo -e "${MODEL_DIR_INFO}${GIT_INFO}${SEP}${TOKENS_INFO}${SEP}${REM_INFO}${SEP}${USED_INFO}${SEP}${STATE_INFO}${SEP}${ARTS_INFO}${SEP}${PLAN_INFO}${SEP}${VERSION_INFO}"
