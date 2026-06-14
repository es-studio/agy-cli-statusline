# Antigravity CLI Statusline Customization

A single-script installer package to customize the statusline of `antigravity-cli` (`agy`) with rich metadata and enable asynchronous API usage quota caching.

---

## 📸 Output Structure Example

> **Note**: Fully updated and compatible with **Antigravity CLI v1.0.8** (Supports new grouped `/usage` output format and 7d/5h limits).

```text
Gemini 3.1 Pro (High) · agy-cli-statusline · git:main · in:1.2k / out:150 · ctx:88.2% · 5h:98% (4h 53m) · 7d:97% (4d 20h) · Google AI Pro · v1.0.8
```

- **Model**: Active model name (Bold Cyan)
- **Directory**: Last directory name of current CWD (Bold Blue)
- **Git**: Current Git branch name if in a Git repository (Green)
- **Tokens**: Accumulated input/output tokens (Yellow, formatted in m/k unit for readability)
- **ctx**: Remaining context window percentage (Green if > 50%, Yellow if > 20%, Red otherwise)
- **5h**: Remaining 5-hour quota percentage with refresh time (Green if > 50%, Yellow if > 20%, Red otherwise)
- **7d**: Remaining 1-week (Weekly) quota percentage with refresh time (Green if > 50%, Yellow if > 20%, Red otherwise)
- **Plan**: Subscription tier (Cyan)
- **v**: Antigravity CLI version (Grey)

---

## 🛠️ Prerequisites

The following tool must be installed on your system:

1. **`jq`**: For parsing JSON metadata payload

For macOS, you can install it via Homebrew:
```bash
brew install jq
```

---

## 🚀 Installation & Setup

**One-Line Installation (Recommended)**:
```bash
curl -sL https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main/install.sh | bash
```

**Manual Installation**:
1. Clone this repository:
   ```bash
   git clone https://github.com/es-studio/agy-cli-statusline.git
   cd agy-cli-statusline
   ```

2. Run the installer script:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

3. Restart your `agy` session to see the new statusline in action.

---

## 🏗️ Architecture Overview

### `statusline.sh` (Lockless & Idempotent Architecture)
- It processes JSON metadata passed from the `agy` CLI via stdin, formats and colorizes it, and outputs the result to stdout.
- **Asynchronous Quota Caching**: To prevent rendering lag, the 5-hour quota (`/usage`) is read instantly from a local cache file (`quota_cache.txt`).
- **Self-Refreshing**: If the cache file does not exist or is older than 30 seconds, `statusline.sh` spawns an asynchronous subshell in the background. This subshell runs `agy -p "/usage"` to update the cache file. 
- **Lockless Idempotency**: Instead of using lock files/directories, the script checks if a sync process (`AGY_QUOTA_CHECK=1`) is already active using `pgrep`. If active, it skips launching another subshell. This completely eliminates stale lock issues and guarantees idempotent execution.
