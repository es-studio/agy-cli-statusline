import sys
import json
import os
import time
import socket
import http.client
import ssl
import subprocess
import platform
from datetime import datetime, timezone

# ANSI Color Codes
RESET = "\033[0m"
GREY = "\033[90m"
CYAN = "\033[36m"
BOLD_CYAN = "\033[1;36m"
GREEN = "\033[32m"
BOLD_GREEN = "\033[1;32m"
YELLOW = "\033[33m"
BOLD_BLUE = "\033[1;34m"
RED = "\033[31m"
MAGENTA = "\033[35m"

SEP = f" {GREY}·{RESET} "

CACHE_FILE = os.path.join(os.path.expanduser("~"), ".gemini", "antigravity-cli", "scratch", "quota_cache.json")

def format_tokens(n):
    if n >= 1000000:
        return f"{n / 1000000:.1f}m"
    if n >= 1000:
        return f"{n / 1000:.1f}k"
    return str(n)

def get_git_branch(cwd):
    if not cwd or not os.path.exists(cwd):
        return ""
    try:
        # Run git command to get current branch
        res = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=1,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )
        return res.stdout.strip()
    except Exception:
        return ""

def find_active_ports():
    current_os = platform.system()
    ports = []
    
    # 1. Windows environment dynamic port discovery
    if current_os == "Windows":
        pids = []
        try:
            res = subprocess.run(
                ["tasklist", "/FI", "IMAGENAME eq agy.exe", "/FO", "CSV", "/NH"],
                capture_output=True,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            for line in res.stdout.splitlines():
                parts = line.split(",")
                if len(parts) > 1:
                    pid = parts[1].strip('"')
                    if pid.isdigit():
                        pids.append(int(pid))
        except Exception:
            pass

        if pids:
            try:
                res = subprocess.run(
                    ["netstat", "-ano"],
                    capture_output=True,
                    text=True,
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
                for line in res.stdout.splitlines():
                    if "LISTENING" in line:
                        parts = line.split()
                        if len(parts) >= 5:
                            local_addr = parts[1]
                            try:
                                pid = int(parts[4])
                            except ValueError:
                                continue
                            if pid in pids:
                                port_str = local_addr.split(":")[-1]
                                if port_str.isdigit():
                                    port = int(port_str)
                                    if port not in ports:
                                        ports.append(port)
            except Exception:
                pass

    # 2. macOS / Linux environment dynamic port discovery
    else:
        pids = []
        try:
            res = subprocess.run(["pgrep", "-f", "agy"], capture_output=True, text=True)
            pids = [int(p) for p in res.stdout.split() if p.isdigit()]
        except Exception:
            try:
                res = subprocess.run(["ps", "-A"], capture_output=True, text=True)
                for line in res.stdout.splitlines():
                    if "agy" in line.lower():
                        parts = line.strip().split()
                        if parts and parts[0].isdigit():
                            pids.append(int(parts[0]))
            except Exception:
                pass
                
        if pids:
            for pid in pids:
                try:
                    res = subprocess.run(
                        ["lsof", "-nP", "-a", "-p", str(pid), "-iTCP", "-sTCP:LISTEN"],
                        capture_output=True,
                        text=True
                    )
                    for line in res.stdout.splitlines():
                        import re
                        match = re.search(r":(\d+)\s+\(LISTEN\)", line)
                        if match:
                            port = int(match.group(1))
                            if port not in ports:
                                ports.append(port)
                except Exception:
                    pass

    # 3. Fallback default ports
    if not ports:
        ports = [2402, 1776, 2401, 1775]
    return ports

def query_quota_summary():
    body = json.dumps({})
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Connect-Protocol-Version": "1",
    }
    
    ports = find_active_ports()
    for port in ports:
        for use_https in (True, False):
            try:
                if use_https:
                    conn = http.client.HTTPSConnection(
                        "127.0.0.1",
                        port,
                        timeout=1.0,
                        context=ssl._create_unverified_context(),
                    )
                else:
                    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=1.0)
                
                conn.request("POST", "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary", body, headers)
                res = conn.getcall() if hasattr(conn, "getcall") else conn.getresponse()
                if res.status == 200:
                    raw = res.read().decode("utf-8", "replace")
                    return json.loads(raw)
            except Exception:
                continue
    return None

def get_quota_info(model_name):
    now = time.time()
    cache = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                cache = json.load(f)
        except Exception:
            pass
    
    cache_age = now - cache.get("timestamp", 0)
    if cache_age > 15 or not cache.get("quotaSummary"):
        summary_data = query_quota_summary()
        if summary_data:
            cache = {
                "timestamp": now,
                "quotaSummary": summary_data
            }
            try:
                os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
                with open(CACHE_FILE, "w", encoding="utf-8") as f:
                    json.dump(cache, f, ensure_ascii=False)
            except Exception:
                pass
                
    if not cache.get("quotaSummary"):
        return None, None, None, None
        
    response = cache["quotaSummary"].get("response", {})
    groups = response.get("groups", [])
    
    model_name_lower = model_name.lower()
    is_gemini = "gemini" in model_name_lower
    
    target_group = None
    for group in groups:
        display_name = group.get("displayName", "").lower()
        if is_gemini and "gemini" in display_name:
            target_group = group
            break
        elif not is_gemini and ("claude" in display_name or "gpt" in display_name or "3p" in display_name):
            target_group = group
            break
            
    if not target_group and groups:
        target_group = groups[0]
        
    quota_5h_frac = None
    quota_5h_reset = None
    quota_7d_frac = None
    quota_7d_reset = None
    
    if target_group:
        for bucket in target_group.get("buckets", []):
            window = bucket.get("window", "").lower()
            rem_frac = bucket.get("remainingFraction")
            reset_time = bucket.get("resetTime")
            
            if window == "5h":
                quota_5h_frac = rem_frac
                quota_5h_reset = reset_time
            elif window == "weekly":
                quota_7d_frac = rem_frac
                quota_7d_reset = reset_time
                
    return quota_5h_frac, quota_5h_reset, quota_7d_frac, quota_7d_reset

def format_reset_time(reset_time_str):
    if not reset_time_str:
        return ""
    try:
        reset = datetime.fromisoformat(reset_time_str.replace("Z", "+00:00"))
        diff = int((reset - datetime.now(timezone.utc)).total_seconds())
        if diff <= 0:
            return "now"
        minutes = (diff + 59) // 60
        if minutes < 60:
            return f"{minutes}m"
        hours, mins = divmod(minutes, 60)
        if hours >= 24:
            days = hours // 24
            rem_hours = hours % 24
            return f"{days}d {rem_hours}h" if rem_hours else f"{days}d"
        return f"{hours}h {mins}m" if mins else f"{hours}h"
    except Exception:
        return ""

def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
        
    try:
        input_data = sys.stdin.read()
        if not input_data.strip():
            return
        data = json.loads(input_data)
    except Exception:
        return

    model_data = data.get("model", {})
    if isinstance(model_data, dict):
        model_name = model_data.get("display_name") or model_data.get("id") or "Unknown"
    else:
        model_name = str(model_data) or "Unknown"
        
    cw = data.get("context_window", {})
    remaining_pct = float(cw.get("remaining_percentage", 100.0))
    in_tokens = int(cw.get("total_input_tokens", 0))
    out_tokens = int(cw.get("total_output_tokens", 0))
    cwd = data.get("cwd", "")
    plan = data.get("plan_tier") or "unknown"
    version = data.get("version") or "unknown"
    
    model_display = f"{BOLD_CYAN}{model_name}{RESET}"
    
    dir_display = ""
    if cwd:
        basename = os.path.basename(cwd.rstrip("/\\"))
        if not basename:
            basename = cwd
        if basename:
            dir_display = f"{BOLD_BLUE}{basename}{RESET}"
        
    git_display = ""
    git_branch = get_git_branch(cwd)
    if git_branch:
        git_display = f"{GREEN}git:{git_branch}{RESET}"
        
    tokens_display = f"{YELLOW}in:{format_tokens(in_tokens)} / out:{format_tokens(out_tokens)}{RESET}"
    
    rem_int = int(remaining_pct)
    if rem_int > 50:
        color_rem = BOLD_GREEN
    elif rem_int > 20:
        color_rem = YELLOW
    else:
        color_rem = RED
    ctx_display = f"{color_rem}ctx:{remaining_pct:.1f}%{RESET}"
    
    q5_frac, q5_reset, q7_frac, q7_reset = get_quota_info(model_name)
    
    if q5_frac is not None:
        q5_pct = int(q5_frac * 100)
        q5_reset_in = format_reset_time(q5_reset)
        quota_5h = f"{q5_pct}%"
        if q5_reset_in:
            quota_5h += f" ({q5_reset_in})"
            
        if q5_pct > 50: qc_5h = BOLD_GREEN
        elif q5_pct > 20: qc_5h = YELLOW
        else: qc_5h = RED
        quota_5h_display = f"{qc_5h}5h:{quota_5h}{RESET}"
    else:
        quota_5h_display = f"{GREY}5h:N/A{RESET}"
        
    if q7_frac is not None:
        q7_pct = int(q7_frac * 100)
        q7_reset_in = format_reset_time(q7_reset)
        quota_7d = f"{q7_pct}%"
        if q7_reset_in:
            quota_7d += f" ({q7_reset_in})"
            
        if q7_pct > 50: qc_7d = BOLD_GREEN
        elif q7_pct > 20: qc_7d = YELLOW
        else: qc_7d = RED
        quota_7d_display = f"{qc_7d}7d:{quota_7d}{RESET}"
    else:
        quota_7d_display = f"{GREY}7d:N/A{RESET}"
        
    parts = []
    parts.append(model_display)
    if dir_display:
        parts.append(dir_display)
    if git_display:
        parts.append(git_display)
    parts.append(tokens_display)
    parts.append(ctx_display)
    parts.append(quota_5h_display)
    parts.append(quota_7d_display)
    parts.append(f"{CYAN}{plan}{RESET}")
    parts.append(f"{GREY}v{version}{RESET}")
    
    print(SEP.join(parts), flush=True)

if __name__ == "__main__":
    main()
