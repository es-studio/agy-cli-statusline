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

for model in "${MODELS[@]}"; do
    found_pct=""
    has_quota_available=0
    for ((i=0; i<num_lines; i++)); do
        line="${lines[$i]}"
        if [[ "$line" == "  $model"* ]]; then
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
    mkdir -p "$CACHE_DIR"
    mv "$TEMP_CACHE" "$CACHE_FILE"
    chmod 600 "$CACHE_FILE" 2>/dev/null || true
else
    rm -f "$TEMP_CACHE"
fi

rm -f /tmp/agy_quota_output.txt
