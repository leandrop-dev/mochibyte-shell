import json
import os
import sys
import time
import urllib.request

REPO = "leandrop-dev/mochibyte-shell"
BRANCH = "main"
UNKNOWN = "unknown"

state_dir = os.path.expanduser("~/.local/state/mochibyte")
if "--state-dir" in sys.argv:
    try:
        idx = sys.argv.index("--state-dir")
        if idx + 1 < len(sys.argv):
            state_dir = sys.argv[idx + 1]
    except Exception:
        pass

state_file = os.path.join(state_dir, "version")
last_check_file = os.path.join(state_dir, "last_check")
notified_file = os.path.join(state_dir, "last_notified")

if "--save-notified" in sys.argv:
    try:
        idx = sys.argv.index("--save-notified")
        if idx + 1 < len(sys.argv):
            commit_to_save = sys.argv[idx + 1]
            os.makedirs(state_dir, exist_ok=True)
            with open(notified_file, "w") as f:
                f.write(commit_to_save)
    except Exception:
        pass
    sys.exit(0)

if "--delay" in sys.argv:
    if os.path.isfile(last_check_file):
        try:
            with open(last_check_file, "r") as f:
                last_ts = float(f.read().strip())
            elapsed = time.time() - last_ts
            remaining = int(max(0, 3600 - elapsed) * 1000)
            print(remaining)
            sys.exit(0)
        except Exception:
            pass
    print(0)
    sys.exit(0)

def get_local_commit():
    if os.path.isfile(state_file):
        try:
            with open(state_file, "r") as f:
                for line in f:
                    if line.startswith("MOCHIBYTE_COMMIT="):
                        c = line.split("=", 1)[1].strip().strip('"').strip("'")
                        if c:
                            return c
        except Exception:
            pass
    return UNKNOWN

def get_last_notified():
    if os.path.isfile(notified_file):
        try:
            with open(notified_file, "r") as f:
                return f.read().strip()
        except Exception:
            pass
    return ""

try:
    os.makedirs(state_dir, exist_ok=True)
    with open(last_check_file, "w") as f:
        f.write(str(time.time()))
except Exception:
    pass

local_commit = get_local_commit()
remote_commit = local_commit

try:
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/commits/{BRANCH}",
        headers={"User-Agent": "updater-script", "Accept": "application/vnd.github+json"}
    )
    res = urllib.request.urlopen(req, timeout=5)
    sha = json.loads(res.read().decode("utf-8")).get("sha", "")
    if sha:
        remote_commit = sha[:len(local_commit)] if local_commit != UNKNOWN else sha[:7]
except Exception:
    remote_commit = local_commit

has_update = local_commit != UNKNOWN and remote_commit != local_commit

print(json.dumps({
    "local": local_commit,
    "remote": remote_commit,
    "has_update": has_update,
    "last_notified": get_last_notified()
}))
