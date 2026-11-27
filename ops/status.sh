#!/usr/bin/env bash
# One screen for "why isn't it running?". Read-only: writes nothing, takes no lock, uses no AI.
D="$(cd "$(dirname "$0")/.." && pwd)"; cd "$D" || exit 1; source ops/config.env
row(){ printf '%-14s %s\n' "$1:" "$2"; }
if [ -f state/STOP ]; then row "stop file" "PRESENT (no runs until you delete state/STOP)"; else row "stop file" "none"; fi
p=$(cat state/pause_until 2>/dev/null)
if [[ "$p" =~ ^[0-9]+$ ]] && [ "$(date +%s)" -lt "$p" ]; then row "pause" "until $(date -d "@$p" '+%F %R')"; else row "pause" "none"; fi
row "runs today" "$(cat "state/runs_$(date +%F)" 2>/dev/null || echo 0)/$MAX_AI_RUNS_PER_DAY"
row "end date" "$MISSION_END"
# Read /proc/locks instead of trying the lock: a probe could make a run starting right now skip itself.
ino=$(stat -c %i state/agent.lock 2>/dev/null)
if [ -n "$ino" ] && grep -qE "FLOCK .*:$ino 0 EOF" /proc/locks 2>/dev/null; then row "session" "running (lock held)"; else row "session" "not running"; fi
if crontab -l 2>/dev/null | grep -qFx "# >>> claude-autopilot $D"; then row "cron" "installed"; else row "cron" "no entry for $D (run ./install.sh)"; fi
row "last ops tick" "$(python3 -I -c '
import json
try:
    s = json.load(open("state/status.json"))
    print(s["ts"], "may run" if s["may_run"] else "blocked: " + s["guard"], "|", s["ledger"])
except (OSError, ValueError, KeyError): print("no readable state/status.json yet")
')"
echo "recent launcher log:"
tail -n 5 logs/agent.log 2>/dev/null | sed 's/^/  /'
exit 0
