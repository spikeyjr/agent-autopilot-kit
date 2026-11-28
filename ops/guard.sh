#!/usr/bin/env bash
# Shared stop/pause checks. Exit 0 = may run, 1 = must not run (reason on stdout).
D="$(cd "$(dirname "$0")/.." && pwd)"; source "$D/ops/config.env"
[ -f "$D/state/STOP" ] && { echo "STOP file present"; exit 1; }
# A pause file that is not an epoch (empty, a date string, milliseconds) holds the agent instead of being ignored.
if [ -e "$D/state/pause_until" ] && ! [[ "$(cat "$D/state/pause_until" 2>/dev/null)" =~ ^[0-9]{1,11}$ ]]; then
  echo "invalid state/pause_until (put epoch seconds in it, or delete it)"; exit 1; fi
# A config typo means "do not run until fixed": it must neither run past the deadline nor create STOP.
[ "$(date -d "$MISSION_END" +%F 2>/dev/null)" = "$MISSION_END" ] || { echo "invalid MISSION_END '$MISSION_END' (use YYYY-MM-DD)"; exit 1; }
[[ "$PROFIT_TARGET" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || { echo "invalid PROFIT_TARGET '$PROFIT_TARGET' (plain number, 0 = disabled)"; exit 1; }
# Pause lengths and the run cap must be whole numbers: otherwise the launcher cannot pause or cap.
for k in RATE_LIMIT_PAUSE_SECONDS ERROR_PAUSE_SECONDS; do
  [[ "${!k:-}" =~ ^[1-9][0-9]{0,8}$ ]] || { echo "invalid $k '${!k:-}' (whole seconds above 0, e.g. 18000)"; exit 1; }
done
[[ "${MAX_AI_RUNS_PER_DAY:-}" =~ ^(0|[1-9][0-9]{0,8})$ ]] || { echo "invalid MAX_AI_RUNS_PER_DAY '${MAX_AI_RUNS_PER_DAY:-}' (whole number, 0 = no AI sessions)"; exit 1; }
today=$(date +%F); [[ "$today" > "$MISSION_END" ]] && { echo "mission ended $MISSION_END"; touch "$D/state/STOP"; exit 1; }
# A failed ledger read means "do not run now", not "target reached": never create STOP for it.
out=$(python3 "$D/ops/ledger.py" summary 2>/dev/null) || { echo "ledger unreadable (will re-check next run)"; exit 1; }
net=${out##*net=}
python3 -c "import sys; t=float('$PROFIT_TARGET'); sys.exit(0 if t<=0 or float('$net') < t else 1)" || { echo "target reached net=$net"; touch "$D/state/STOP"; exit 1; }
exit 0
