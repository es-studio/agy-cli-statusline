#!/bin/bash

# Target installation directory
TARGET_DIR="$HOME/.gemini/antigravity-cli"
SCRIPT_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Antigravity CLI Statusline Installer (Python Cross-Platform) ==="

# 1. Ensure target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

# 2. Check dependencies
echo "Checking python3..."
PYTHON_BIN="python3"
if ! command -v python3 &>/dev/null; then
    if command -v python &>/dev/null; then
        PYTHON_BIN="python"
    else
        echo "❌ Error: 'python3' or 'python' is not installed. Please install Python to run the statusline."
        exit 1
    fi
fi
echo "✅ Python is available: ($PYTHON_BIN)"

# 3. Copy or Download statusline.py to ~/.gemini/antigravity-cli/scratch/
SCRATCH_DIR="$TARGET_DIR/scratch"
mkdir -p "$SCRATCH_DIR"

if [ -f "$SCRIPT_SRC_DIR/statusline.py" ]; then
    echo "Copying statusline.py to $SCRATCH_DIR..."
    cp "$SCRIPT_SRC_DIR/statusline.py" "$SCRATCH_DIR/statusline.py"
else
    echo "Downloading statusline.py from GitHub..."
    REPO_RAW_URL="https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main"
    curl -sL "$REPO_RAW_URL/statusline.py" -o "$SCRATCH_DIR/statusline.py"
fi

echo "✅ Script copied."

# 4. Update settings.json
SETTINGS_FILE="$TARGET_DIR/settings.json"
echo "Updating settings.json..."

# Resolve python execution command
RESOLVED_PYTHON=$(command -v $PYTHON_BIN)
# On Windows/Git Bash, translate path style if needed, but python absolute path is best.
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # Translate path to Windows style for Windows Python
    RESOLVED_PYTHON=$(cygpath -w "$RESOLVED_PYTHON" 2>/dev/null || echo "python")
fi

PYTHON_CMD="$RESOLVED_PYTHON"
STATUSLINE_PATH="$SCRATCH_DIR/statusline.py"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    STATUSLINE_PATH=$(cygpath -w "$STATUSLINE_PATH" 2>/dev/null || echo "$STATUSLINE_PATH")
    # Convert double backslashes for json escaping
    STATUSLINE_PATH="${STATUSLINE_PATH//\\//}"
    PYTHON_CMD="${PYTHON_CMD//\\//}"
fi

# Run python helper to safely inject config into settings.json
$PYTHON_BIN -c "
import json, os
path = os.path.expanduser('~/.gemini/antigravity-cli/settings.json')
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        try: data = json.load(f)
        except Exception: data = {}
else:
    data = {}
if 'statusLine' not in data: data['statusLine'] = {}
data['statusLine']['type'] = 'command'
data['statusLine']['command'] = '$PYTHON_CMD $STATUSLINE_PATH'
data['statusLine']['enabled'] = True
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"

echo "✅ statusLine configurations injected successfully into settings.json."
echo "🎉 Installation completed successfully!"
echo "Please restart your Antigravity CLI session to see the new statusline."
