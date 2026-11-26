#!/usr/bin/env bash
# Shared stop/pause checks. Exit 0 = may run, 1 = must not run (reason on stdout).
D="$(cd "$(dirname "$0")/.." && pwd)"; source "$D/ops/config.env"
[ -f "$D/state/STOP" ] && { echo "STOP file present"; exit 1; }
today=$(date +%F); [[ "$today" > "$MISSION_END" ]] && { echo "mission ended $MISSION_END"; touch "$D/state/STOP"; exit 1; }
# A failed ledger read means "do not run now", not "target reached": never create STOP for it.
out=$(python3 "$D/ops/ledger.py" summary 2>/dev/null) || { echo "ledger unreadable (will re-check next run)"; exit 1; }
net=${out##*net=}
python3 -c "import sys; t=float('$PROFIT_TARGET'); sys.exit(0 if t<=0 or float('$net') < t else 1)" || { echo "target reached net=$net"; touch "$D/state/STOP"; exit 1; }
exit 0
