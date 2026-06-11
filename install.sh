#!/bin/bash

# Target installation directory
TARGET_DIR="$HOME/.gemini/antigravity-cli"
SCRIPT_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Antigravity CLI Statusline Installer ==="

# 1. Ensure target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

# 2. Check dependencies
echo "Checking dependencies..."
DEPS_OK=1

if ! command -v jq &>/dev/null; then
    echo "⚠️ Warning: 'jq' is not installed. Please install 'jq' (e.g. 'brew install jq') for statusline parsing logic."
    DEPS_OK=0
fi

if [ $DEPS_OK -eq 1 ]; then
    echo "✅ All dependencies (jq) are satisfied."
fi

# 3. Copy or Download scripts to ~/.gemini/antigravity-cli/
if [ -f "$SCRIPT_SRC_DIR/statusline.sh" ] && [ -f "$SCRIPT_SRC_DIR/update_quota_cache.sh" ]; then
    echo "Copying local scripts to $TARGET_DIR..."
    cp "$SCRIPT_SRC_DIR/statusline.sh" "$TARGET_DIR/statusline.sh"
    cp "$SCRIPT_SRC_DIR/update_quota_cache.sh" "$TARGET_DIR/update_quota_cache.sh"
else
    echo "Downloading scripts from GitHub to $TARGET_DIR..."
    REPO_RAW_URL="https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main"
    curl -sL "$REPO_RAW_URL/statusline.sh" -o "$TARGET_DIR/statusline.sh"
    curl -sL "$REPO_RAW_URL/update_quota_cache.sh" -o "$TARGET_DIR/update_quota_cache.sh"
fi

chmod +x "$TARGET_DIR/statusline.sh"
chmod +x "$TARGET_DIR/update_quota_cache.sh"

echo "✅ Script copied and execution permissions granted."

# 4. Update ~/.gemini/antigravity-cli/settings.json
SETTINGS_FILE="$TARGET_DIR/settings.json"
echo "Updating settings.json..."

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Creating new settings.json with statusline configurations."
    echo '{
  "statusLine": {
    "type": "command",
    "command": "'"$TARGET_DIR/statusline.sh"'",
    "enabled": true
  }
}' > "$SETTINGS_FILE"
else
    # Python-based safe JSON injector
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os
path = os.path.expanduser('~/.gemini/antigravity-cli/settings.json')
with open(path, 'r') as f:
    try:
        data = json.load(f)
    except Exception:
        data = {}
if 'statusLine' not in data:
    data['statusLine'] = {}
data['statusLine']['type'] = 'command'
data['statusLine']['command'] = os.path.expanduser('~/.gemini/antigravity-cli/statusline.sh')
data['statusLine']['enabled'] = True
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "✅ statusLine configurations injected successfully into settings.json."
    else
        echo "⚠️ Python3 is not available. Please manually update your settings.json at $SETTINGS_FILE with:"
        echo '{'
        echo '  "statusLine": {'
        echo '    "type": "command",'
        echo '    "command": "'"$TARGET_DIR/statusline.sh"'",'
        echo '    "enabled": true'
        echo '  }'
        echo '}'
    fi
fi

# 5. Trigger first quota sync in background immediately
echo "Initializing first quota cache sync in background..."
echo '{}' | bash "$TARGET_DIR/statusline.sh" &>/dev/null &

echo "🎉 Installation completed successfully!"
echo "Please restart your Antigravity CLI session to see the new statusline."
