#!/usr/bin/env bash
# Shared stop/pause checks. Exit 0 = may run, 1 = must not run (reason on stdout).
D="$(cd "$(dirname "$0")/.." && pwd)"; source "$D/ops/config.env"
[ -f "$D/state/STOP" ] && { echo "STOP file present"; exit 1; }
# A config typo means "do not run until fixed": it must neither run past the deadline nor create STOP.
[ "$(date -d "$MISSION_END" +%F 2>/dev/null)" = "$MISSION_END" ] || { echo "invalid MISSION_END '$MISSION_END' (use YYYY-MM-DD)"; exit 1; }
[[ "$PROFIT_TARGET" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || { echo "invalid PROFIT_TARGET '$PROFIT_TARGET' (plain number, 0 = disabled)"; exit 1; }
today=$(date +%F); [[ "$today" > "$MISSION_END" ]] && { echo "mission ended $MISSION_END"; touch "$D/state/STOP"; exit 1; }
# A failed ledger read means "do not run now", not "target reached": never create STOP for it.
out=$(python3 "$D/ops/ledger.py" summary 2>/dev/null) || { echo "ledger unreadable (will re-check next run)"; exit 1; }
net=${out##*net=}
python3 -c "import sys; t=float('$PROFIT_TARGET'); sys.exit(0 if t<=0 or float('$net') < t else 1)" || { echo "target reached net=$net"; touch "$D/state/STOP"; exit 1; }
exit 0
