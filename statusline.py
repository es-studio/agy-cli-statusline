"""
Antigravity CLI Statusline
GitHub: https://github.com/es-studio/agy-cli-statusline
"""
import sys
import json
import os
import time
import re
import urllib.request
import ssl
import subprocess
from datetime import datetime, timezone

__version__ = "2.1.0"

# Auto-update configuration
UPDATE_URL = os.environ.get(
    "AGY_STATUSLINE_URL",
    "https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main/statusline.py"
)
CHECK_INTERVAL_SECONDS = int(os.environ.get("AGY_STATUSLINE_CHECK_INTERVAL", 12 * 3600))
AUTO_UPDATE_ENABLED = os.environ.get("AGY_STATUSLINE_AUTO_UPDATE", "1").lower() not in ("0", "false", "no", "off")

# ANSI Color Codes
RESET = "\033[0m"
GREY = "\033[90m"
BOLD_BLUE = "\033[1;34m"
BOLD_WHITE = "\033[1;37m"
BRIGHT_CYAN = "\033[96m"
BRIGHT_GREEN = "\033[92m"
BRIGHT_MAGENTA = "\033[95m"
BRIGHT_YELLOW = "\033[93m"
ORANGE = "\033[38;5;208m"

SEP = f" {GREY}·{RESET} "

# --- Auto-update helper functions ---

def parse_version(v_str):
    """Parses a version string like 'v2.1.0' into a tuple of ints: (2, 1, 0)."""
    if not v_str:
        return (0, 0, 0)
    cleaned = re.sub(r'^[^\d]*', '', str(v_str).strip())
    parts = []
    for p in re.split(r'[-.+_]', cleaned):
        if p.isdigit():
            parts.append(int(p))
        else:
            break
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])

def get_meta_file_path():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(script_dir, ".statusline_update.json")

def load_update_meta():
    try:
        path = get_meta_file_path()
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception:
        pass
    return {}

def save_update_meta(meta):
    try:
        path = get_meta_file_path()
        tmp_path = path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, path)
    except Exception:
        pass

def fetch_remote_script(timeout=8):
    try:
        ctx = ssl.create_default_context()
    except Exception:
        ctx = None

    req = urllib.request.Request(
        UPDATE_URL,
        headers={"User-Agent": f"agy-cli-statusline/{__version__}"}
    )
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as res:
        if res.status != 200:
            raise RuntimeError(f"HTTP {res.status}")
        return res.read().decode("utf-8")

def check_update_status():
    try:
        content = fetch_remote_script(timeout=5)
        m = re.search(r'__version__\s*=\s*["\']([^"\']+)["\']', content)
        remote_version = m.group(1) if m else None
        if not remote_version:
            return False, None, "Remote script has no version defined (legacy format)."
        is_newer = parse_version(remote_version) > parse_version(__version__)
        return is_newer, remote_version, "Update available" if is_newer else "Already up to date"
    except Exception as e:
        return False, None, str(e)

def perform_update(force=False, verbose=False):
    """
    Downloads remote script from UPDATE_URL, checks version and syntax integrity,
    and atomically replaces current script file if valid and newer.
    """
    if verbose:
        print(f"Checking for updates from: {UPDATE_URL}")
        print(f"Current version: v{__version__}")

    try:
        content = fetch_remote_script(timeout=10)
    except Exception as e:
        msg = f"Failed to download update: {e}"
        if verbose:
            print(f"❌ {msg}")
        return False, msg

    if len(content) < 500:
        msg = "Downloaded content is unexpectedly small, aborting update."
        if verbose:
            print(f"❌ {msg}")
        return False, msg

    try:
        compile(content, "statusline_remote.py", "exec")
    except Exception as e:
        msg = f"Downloaded content failed Python syntax verification: {e}"
        if verbose:
            print(f"❌ {msg}")
        return False, msg

    m = re.search(r'__version__\s*=\s*["\']([^"\']+)["\']', content)
    remote_version = m.group(1) if m else None

    if not force:
        if not remote_version:
            msg = "Remote script has no version metadata; skipped update to prevent downgrading."
            if verbose:
                print(f"ℹ️  {msg}")
            return False, msg
        if parse_version(remote_version) <= parse_version(__version__):
            msg = f"Already up-to-date (Current: v{__version__}, Remote: v{remote_version})."
            if verbose:
                print(f"✅ {msg}")
            return False, msg

    # Atomic replace
    script_path = os.path.abspath(__file__)
    tmp_path = script_path + ".new"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_path, script_path)
    except Exception as e:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
        msg = f"Failed to replace script: {e}"
        if verbose:
            print(f"❌ {msg}")
        return False, msg

    # Save metadata
    now = time.time()
    meta = load_update_meta()
    meta["last_check"] = now
    meta["last_update"] = now
    meta["previous_version"] = __version__
    meta["current_version"] = remote_version or "latest"
    meta["last_status"] = f"Successfully updated to v{remote_version or 'latest'}"
    save_update_meta(meta)

    success_msg = f"Successfully updated from v{__version__} to v{remote_version or 'latest'}!"
    if verbose:
        print(f"🎉 {success_msg}")
    return True, success_msg

def trigger_background_update_if_needed():
    if not AUTO_UPDATE_ENABLED:
        return
    now = time.time()
    meta = load_update_meta()
    last_check = meta.get("last_check", 0)
    if now - last_check < CHECK_INTERVAL_SECONDS:
        return

    # Set last_check immediately to prevent concurrent worker launches
    meta["last_check"] = now
    save_update_meta(meta)

    try:
        script_path = os.path.abspath(__file__)
        flags = 0
        if sys.platform == "win32":
            flags = getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000) | getattr(subprocess, "DETACHED_PROCESS", 0x00000008)

        subprocess.Popen(
            [sys.executable, script_path, "--bg-check"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=(sys.platform != "win32"),
            creationflags=flags,
            start_new_session=(sys.platform != "win32"),
        )
    except Exception:
        pass

def handle_cli_args():
    if len(sys.argv) <= 1:
        return False  # Normal stdin mode

    arg = sys.argv[1].lower()

    if arg == "--bg-check":
        try:
            perform_update(force=False, verbose=False)
        except Exception:
            pass
        return True

    if arg in ("--update", "-u"):
        force = "--force" in sys.argv or "-f" in sys.argv
        perform_update(force=force, verbose=True)
        return True

    if arg in ("--check-update", "--check"):
        print(f"Checking updates for agy-cli-statusline (Current: v{__version__})...")
        is_newer, r_ver, msg = check_update_status()
        if is_newer:
            print(f"🔔 New version available: v{r_ver} (Current: v{__version__})")
            print("Run with `--update` to install the update.")
        else:
            print(f"✅ {msg} (Current: v{__version__}, Remote: v{r_ver or 'legacy'})")
        return True

    if arg in ("--version", "-v"):
        print(f"agy-cli-statusline v{__version__}")
        return True

    if arg in ("--help", "-h"):
        print(f"Antigravity CLI Statusline v{__version__}")
        print("Usage:")
        print("  statusline.py                 Read JSON payload from stdin and format statusline")
        print("  statusline.py --update        Check for updates and install if available")
        print("  statusline.py --check-update  Check if an update is available without applying")
        print("  statusline.py --version       Show statusline version")
        print("  statusline.py --help          Show this help message")
        print("\nEnvironment Variables:")
        print("  AGY_STATUSLINE_AUTO_UPDATE=0       Disable background auto-updates")
        print("  AGY_STATUSLINE_CHECK_INTERVAL=43200 Set check interval in seconds (default: 12h)")
        print("  AGY_STATUSLINE_URL=<url>           Custom raw statusline script URL")
        return True

    return False


# --- Statusline Rendering ---

def format_tokens(n):
    if n >= 1000000:
        return f"{n / 1000000:.1f}m"
    if n >= 1000:
        return f"{n / 1000:.1f}k"
    return str(n)

def format_reset(bucket):
    if not bucket or not isinstance(bucket, dict):
        return ""
    sec = bucket.get("reset_in_seconds")
    if sec is not None:
        try:
            diff = int(sec)
        except Exception:
            diff = 0
    else:
        rt = bucket.get("reset_time")
        if not rt:
            return ""
        try:
            reset_dt = datetime.fromisoformat(str(rt).replace("Z", "+00:00"))
            diff = int((reset_dt - datetime.now(timezone.utc)).total_seconds())
        except Exception:
            return ""

    if diff <= 0:
        return ""
    minutes = (diff + 59) // 60
    if minutes < 60:
        return f"{minutes}m"
    hours, mins = divmod(minutes, 60)
    if hours >= 24:
        days = hours // 24
        rem_h = hours % 24
        return f"{days}d {rem_h}h" if rem_h else f"{days}d"
    return f"{hours}h {mins}m" if mins else f"{hours}h"

def get_quota_bucket(quota, window_type, is_gemini):
    if not quota or not isinstance(quota, dict):
        return None
    primary_key = f"{'gemini' if is_gemini else '3p'}-{window_type}"
    if primary_key in quota:
        return quota[primary_key]
    fallback_key = f"{'3p' if is_gemini else 'gemini'}-{window_type}"
    if fallback_key in quota:
        return quota[fallback_key]
    for k, v in quota.items():
        if k.endswith(f"-{window_type}") or k == window_type:
            return v
    return None

def format_quota_display(bucket, label):
    if not bucket or not isinstance(bucket, dict):
        return f"{GREY}{label}:N/A{RESET}"
    frac = bucket.get("remaining_fraction")
    if frac is None:
        return f"{GREY}{label}:N/A{RESET}"
    pct = int(frac * 100)
    reset_str = format_reset(bucket)
    if reset_str:
        return f"{BRIGHT_CYAN}{label}:{pct}% ({reset_str}){RESET}"
    return f"{BRIGHT_CYAN}{label}:{pct}%{RESET}"

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    if handle_cli_args():
        return

    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            return
        data = json.loads(raw_input)
    except Exception:
        return

    # 1. Model Name
    model_obj = data.get("model", {})
    if isinstance(model_obj, dict):
        model_name = model_obj.get("display_name") or model_obj.get("id") or "Unknown"
    else:
        model_name = str(model_obj) or "Unknown"
    model_display = f"{BOLD_WHITE}{model_name}{RESET}"

    # 2. Directory Name
    cwd = data.get("cwd", "")
    dir_display = ""
    if cwd:
        base = os.path.basename(cwd.rstrip("/\\"))
        if not base:
            base = cwd
        if base:
            dir_display = f"{BOLD_BLUE}{base}{RESET}"

    # 3. VCS (Git Branch & Status from agy native detection)
    git_display = ""
    vcs = data.get("vcs") or {}
    if isinstance(vcs, dict):
        branch = vcs.get("branch", "")
        if branch:
            if vcs.get("dirty"):
                branch = f"{branch}*"
            git_display = f"{BRIGHT_GREEN}git:{branch}{RESET}"

    # 4. Context Window & Tokens
    cw = data.get("context_window") or {}
    in_tokens = int(cw.get("total_input_tokens", 0))
    out_tokens = int(cw.get("total_output_tokens", 0))
    rem_pct = float(cw.get("remaining_percentage", 100.0))
    tokens_display = f"{BRIGHT_YELLOW}in:{format_tokens(in_tokens)} / out:{format_tokens(out_tokens)}{RESET}"
    ctx_display = f"{ORANGE}ctx:{rem_pct:.1f}%{RESET}"

    # 5. Background Tasks & Subagents
    task_count = int(data.get("task_count", 0))
    subagents = data.get("subagents") or []
    running_subs = sum(1 for s in subagents if isinstance(s, dict) and s.get("status") == "running")

    if task_count > 0 or running_subs > 0:
        task_parts = []
        if task_count > 0:
            task_parts.append(f"tasks:{task_count}")
        if running_subs > 0:
            task_parts.append(f"sub:{running_subs}")
        tasks_display = f"{BRIGHT_MAGENTA}{'/'.join(task_parts)}{RESET}"
    else:
        tasks_display = f"{GREY}tasks:0{RESET}"

    # 6. Real-time Quota (directly from agy native stdin payload)
    quota = data.get("quota") or {}
    is_gemini = "gemini" in model_name.lower()
    b5 = get_quota_bucket(quota, "5h", is_gemini)
    b7 = get_quota_bucket(quota, "weekly", is_gemini)
    q5_display = format_quota_display(b5, "5h")
    q7_display = format_quota_display(b7, "7d")

    # 7. Plan Tier & Version
    plan = data.get("plan_tier") or "unknown"
    version = data.get("version") or ""
    plan_display = f"{GREY}{plan}{RESET}"
    ver_display = f"{GREY}v{version}{RESET}" if version else ""

    # Assemble line
    parts = [model_display]
    if dir_display:
        parts.append(dir_display)
    if git_display:
        parts.append(git_display)
    parts.append(tokens_display)
    parts.append(ctx_display)
    parts.append(tasks_display)
    parts.append(q5_display)
    parts.append(q7_display)
    parts.append(plan_display)
    if ver_display:
        parts.append(ver_display)

    print(SEP.join(parts), flush=True)

    # Check for background auto-update without blocking terminal
    trigger_background_update_if_needed()

if __name__ == "__main__":
    main()
