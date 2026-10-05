import sys
import json
import os
from datetime import datetime, timezone

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
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

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

if __name__ == "__main__":
    main()
