#!/usr/bin/env python3
"""Deterministic (no-AI) operations tick: health, stop checks, status snapshot. Runs every 15 min + @reboot."""
import subprocess, os, sys, datetime, json, glob, fcntl
D = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(D)
HOOK_TIMEOUT = int(os.environ.get("HOOK_TIMEOUT", "300"))
ts = datetime.datetime.now().isoformat(timespec="seconds")
# Slow hooks can outlast the 15-min interval (or collide with @reboot): never run two ticks at once.
lock = open("state/ops.lock", "w")  # held until this process exits
try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    with open("logs/ops.log", "a") as f: f.write(f"{ts} SKIP overlap: another ops tick is running\n")
    sys.exit(0)
guard = subprocess.run(["ops/guard.sh"], capture_output=True, text=True)
money = subprocess.run(["python3", "ops/ledger.py", "summary"], capture_output=True, text=True).stdout.strip()
pause = open("state/pause_until").read().strip() if os.path.exists("state/pause_until") else "0"
# Put deterministic jobs in ops/hooks/*.py; each runs every tick; one that exceeds HOOK_TIMEOUT (300s) is killed.
for hook in sorted(glob.glob("ops/hooks/*.py")):
    try:
        r = subprocess.run(["python3", "-I", hook], capture_output=True, text=True, errors="replace", timeout=HOOK_TIMEOUT)
        line = f"{hook} rc={r.returncode} {r.stdout[-300:]} {r.stderr[-300:]}"
    except subprocess.TimeoutExpired:  # a hung hook must not stop later hooks or the status snapshot
        line = f"{hook} TIMEOUT after {HOOK_TIMEOUT}s (killed)"
    with open("logs/ops.log", "a") as f: f.write(f"{ts} HOOK {line}\n")
status = {"ts": ts, "may_run": guard.returncode == 0, "guard": guard.stdout.strip(), "ledger": money,
          "paused_until": datetime.datetime.fromtimestamp(int(pause)).isoformat() if int(pause) else None}
json.dump(status, open("state/status.json", "w"), indent=1)
with open("logs/ops.log", "a") as f: f.write(f"{ts} OPS {json.dumps(status)}\n")
# keep logs bounded
for lf in glob.glob("logs/*.log"):
    if os.path.getsize(lf) > 5_000_000: os.replace(lf, lf + ".1")
