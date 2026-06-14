#!/bin/bash

# Ensure tmux is available
if ! command -v tmux &>/dev/null; then
    exit 1
fi

CACHE_DIR="$HOME/.gemini/antigravity-cli"
CACHE_FILE="$CACHE_DIR/quota_cache.txt"
TEMP_CACHE=$(mktemp)

# Detect agy binary path
if command -v agy &>/dev/null; then
    AGY_BIN=$(command -v agy)
elif [ -f "$HOME/.local/bin/agy" ]; then
    AGY_BIN="$HOME/.local/bin/agy"
else
    AGY_BIN="agy"
fi

SESSION="agy_quota_$$"

# Start tmux session
tmux new-session -d -s "$SESSION" -x 200 -y 60
tmux send-keys -t "$SESSION" "$AGY_BIN" C-m
sleep 6

# Send /usage
tmux send-keys -t "$SESSION" "/usage" C-m
sleep 3

# Capture output
tmux capture-pane -p -t "$SESSION" -S - > /tmp/agy_quota_output.txt

# Scroll down once to get the rest
tmux send-keys -t "$SESSION" Space
sleep 1
tmux capture-pane -p -t "$SESSION" -S - >> /tmp/agy_quota_output.txt

# Kill session
tmux kill-session -t "$SESSION"

# Parse output
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
lines=($(cat /tmp/agy_quota_output.txt))
num_lines=${#lines[@]}

parse_group_quota() {
    local group_name="$1"
    local quota_5h="N/A"
    local quota_7d="N/A"
    local in_group=0
    local current_limit=""
    
    for ((i=0; i<num_lines; i++)); do
        local line="${lines[$i]}"
        local trimmed=$(echo "$line" | xargs)
        
        if [[ "$trimmed" == "$group_name"* ]]; then
            in_group=1
            continue
        fi
        
        if [ $in_group -eq 1 ]; then
            # Stop if we hit another top-level group or end
            if [[ "$trimmed" == "GEMINI MODELS" ]] || [[ "$trimmed" == "CLAUDE AND GPT MODELS" ]]; then
                if [[ "$trimmed" != "$group_name"* ]]; then
                    break
                fi
            fi

            if [[ "$trimmed" == "Weekly Limit" ]]; then
                current_limit="7d"
                continue
            elif [[ "$trimmed" == "Five Hour Limit" ]]; then
                current_limit="5h"
                continue
            fi
            
            if [ -n "$current_limit" ]; then
                local quota_val=""
                if [[ "$trimmed" == *"Quota available"* ]]; then
                    quota_val="100%"
                elif [[ "$trimmed" == *"remaining"* ]] && [[ "$trimmed" == *"Refreshes in"* ]]; then
                    local pct=$(echo "$trimmed" | grep -oE "[0-9]+%" | head -n 1)
                    local ref_time=$(echo "$trimmed" | sed -n 's/.*Refreshes in //p' | xargs)
                    if [ -n "$pct" ] && [ -n "$ref_time" ]; then
                        quota_val="${pct}:${ref_time}"
                    elif [ -n "$pct" ]; then
                        quota_val="$pct"
                    fi
                fi
                
                if [ -n "$quota_val" ]; then
                    if [ "$current_limit" = "7d" ]; then
                        quota_7d="$quota_val"
                    elif [ "$current_limit" = "5h" ]; then
                        quota_5h="$quota_val"
                    fi
                    current_limit=""
                fi
            fi
        fi
    done
    echo "${quota_5h}|${quota_7d}"
}

GEMINI_QUOTAS=$(parse_group_quota "GEMINI MODELS")
CLAUDE_GPT_QUOTAS=$(parse_group_quota "CLAUDE AND GPT MODELS")

for model in "${MODELS[@]}"; do
    if [[ "$model" == Gemini* ]]; then
        echo "${model}:${GEMINI_QUOTAS}" >> "$TEMP_CACHE"
    else
        echo "${model}:${CLAUDE_GPT_QUOTAS}" >> "$TEMP_CACHE"
    fi
done

if [ -s "$TEMP_CACHE" ]; then
    mkdir -p "$CACHE_DIR"
    mv "$TEMP_CACHE" "$CACHE_FILE"
    chmod 600 "$CACHE_FILE" 2>/dev/null || true
else
    rm -f "$TEMP_CACHE"
fi

rm -f /tmp/agy_quota_output.txt
