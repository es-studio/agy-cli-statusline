# Antigravity CLI Statusline (agy-cli-statusline)

A lightweight, zero-dependency, and cross-platform statusline customization for **Google Antigravity CLI (`agy`)**.

Featuring real-time token counts, context window tracking, git status, multi-tier quotas (5-hour & 7-day limits), background task counts, and seamless **non-blocking automatic updates**.

---

## 📸 Output Structure Example

Compatible with **Antigravity CLI v1.2+** and modern stdin payload schema.

```text
Gemini 3.8 Flash (High) · my-project · git:main* · in:12.5k / out:3.2k · ctx:97.4% · sub:1 · 5h:85% (4h 15m) · 7d:92% (5d) · Google AI Pro · v1.2.17
```

- **Model**: Active model display name (Bold White)
- **Directory**: Current working directory basename (Bold Blue)
- **Git**: Branch name and dirty indicator `*` directly from `agy` native VCS detection (Green)
- **Tokens**: Accumulated input and output tokens formatted in `m` / `k` units (Yellow)
- **ctx**: Remaining context window percentage (Orange)
- **Tasks / Subagents**: Real-time count of background tasks and running subagents (Magenta)
- **5h**: Remaining 5-hour quota percentage and reset countdown (Bright Cyan)
- **7d**: Remaining weekly quota percentage and reset countdown (Bright Cyan)
- **Plan**: Subscription tier (Grey)
- **v**: Antigravity CLI version (Grey)

---

## 🛠️ Prerequisites

- **Python 3.8+** (Standard library only; zero external dependencies or `pip` packages required)

---

## 🚀 Installation & Setup

### Windows (PowerShell)
Run the following one-liner in PowerShell:
```powershell
irm https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main/install.ps1 | iex
```

### macOS & Linux (Bash)
Run the following one-liner in your terminal:
```bash
curl -sL https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main/install.sh | bash
```

### Manual Installation
1. Clone this repository:
   ```bash
   git clone https://github.com/es-studio/agy-cli-statusline.git
   cd agy-cli-statusline
   ```
2. Copy `statusline.py` into your Antigravity scratch directory:
   - **Windows**: `~/.gemini/antigravity-cli/scratch/statusline.py`
   - **Linux / macOS**: `~/.gemini/antigravity-cli/scratch/statusline.py`
3. Configure `~/.gemini/antigravity-cli/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "python ~/.gemini/antigravity-cli/scratch/statusline.py",
       "enabled": true
     }
   }
   ```
4. Restart your `agy` session to see your new statusline.

---

## 🔄 Automatic & Manual Updates

### Seamless Background Auto-Update
- **Zero Terminal Latency**: Statusline rendering is never blocked by network calls. Update checks run in a detached background process with zero window popup (`DETACHED_PROCESS`).
- **Throttled Checks**: By default, checks run once every 12 hours.
- **Safety Checks**: Downloads are validated for Python syntax integrity (`compile()`) and compared using semantic versioning to prevent accidental downgrades or corrupted files.
- **Atomic Replace**: Files are replaced atomically (`os.replace`) to ensure crash resistance.

### Manual CLI Commands
You can also inspect and trigger updates directly:

```bash
# Check installed statusline version
python statusline.py --version

# Check if a new version is available on GitHub
python statusline.py --check-update

# Manually trigger immediate update
python statusline.py --update

# Show CLI options and environment variable configuration
python statusline.py --help
```

### Environment Configuration
| Environment Variable | Default | Description |
| :--- | :--- | :--- |
| `AGY_STATUSLINE_AUTO_UPDATE` | `1` | Set to `0` to disable background auto-updates |
| `AGY_STATUSLINE_CHECK_INTERVAL` | `43200` (12h) | Interval in seconds between auto-update checks |
| `AGY_STATUSLINE_URL` | *main branch raw URL* | Custom source URL for updates |

---

## 🏗️ Architecture & Philosophy

1. **Native Ingestion over Port Probing**:
   Previous approaches scanned local TCP ports to query internal RPC endpoints, which could trigger Go TLS handshake errors. `agy-cli-statusline v2.1+` reads quota, token metrics, and VCS states directly from `agy`'s native stdin JSON payload.
2. **Sub-50ms Execution**:
   Zero child process spawning (`git`, `curl`, `jq`) during statusline rendering. All parsing is done in-memory in pure Python.
3. **Resilient Self-Management**:
   Self-contained update management without external package managers or daemons.
