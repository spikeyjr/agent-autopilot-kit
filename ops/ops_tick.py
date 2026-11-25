#!/usr/bin/env python3
"""Deterministic (no-AI) operations tick: health, stop checks, status snapshot. Runs every 15 min + @reboot."""
import subprocess, os, datetime, json, glob
D = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(D)
ts = datetime.datetime.now().isoformat(timespec="seconds")
guard = subprocess.run(["ops/guard.sh"], capture_output=True, text=True)
money = subprocess.run(["python3", "ops/ledger.py", "summary"], capture_output=True, text=True).stdout.strip()
pause = open("state/pause_until").read().strip() if os.path.exists("state/pause_until") else "0"
# Put deterministic jobs in ops/hooks/*.py; each runs every tick with a 300s timeout.
for hook in sorted(glob.glob("ops/hooks/*.py")):
    r = subprocess.run(["python3", "-I", hook], capture_output=True, text=True, timeout=300)
    with open("logs/ops.log", "a") as f: f.write(f"{ts} HOOK {hook} rc={r.returncode} {r.stdout[-300:]} {r.stderr[-300:]}\n")
status = {"ts": ts, "may_run": guard.returncode == 0, "guard": guard.stdout.strip(), "ledger": money,
          "paused_until": datetime.datetime.fromtimestamp(int(pause)).isoformat() if int(pause) else None}
json.dump(status, open("state/status.json", "w"), indent=1)
with open("logs/ops.log", "a") as f: f.write(f"{ts} OPS {json.dumps(status)}\n")
# keep logs bounded
for lf in glob.glob("logs/*.log"):
    if os.path.getsize(lf) > 5_000_000: os.replace(lf, lf + ".1")
