#!/usr/bin/env bash
# AI work session launcher (cron). Non-overlapping, budgeted, pauses on usage limits, never retries.
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"; cd "$D"; source ops/config.env
LOG=logs/agent.log; ts(){ date -Is; }
exec 9>state/agent.lock
flock -n 9 || { echo "$(ts) SKIP overlap: another session running" >>$LOG; exit 0; }
if [ -n "${AGENT_PROMPT:-}" ] && [ ! -f state/allow_test ]; then echo "$(ts) SKIP test invocation (state/allow_test absent)" >>$LOG; exit 0; fi
reason=$(ops/guard.sh) || { echo "$(ts) SKIP guard: $reason" >>$LOG; exit 0; }
if [ -f state/pause_until ] && [ "$(date +%s)" -lt "$(cat state/pause_until)" ]; then
  echo "$(ts) SKIP paused until $(date -d @$(cat state/pause_until) -Is)" >>$LOG; exit 0; fi
cnt_file=state/runs_$(date +%F); n=$(cat $cnt_file 2>/dev/null || echo 0)
[ "$n" -ge "$MAX_AI_RUNS_PER_DAY" ] && { echo "$(ts) SKIP daily cap $n/$MAX_AI_RUNS_PER_DAY" >>$LOG; exit 0; }
echo $((n+1)) > $cnt_file
# Never let a stray API key turn this into paid API usage: force subscription (OAuth) auth.
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDECODE CLAUDE_CODE_ENTRYPOINT
DEFAULT_PROMPT="Read AGENTS.md and follow its session protocol exactly. Work the top items of TASKS.md, keep context small, update the state files, then stop."
PROMPT="${AGENT_PROMPT:-${SESSION_PROMPT:-$DEFAULT_PROMPT}}"
echo "$(ts) START session $((n+1))/$MAX_AI_RUNS_PER_DAY model=$AI_MODEL" >>$LOG
out=$(timeout 45m claude -p "$PROMPT" --model "$AI_MODEL" --max-turns "$AI_MAX_TURNS" \
      --permission-mode acceptEdits --settings ops/agent_settings.json --output-format json 2>&1); rc=$?
printf '%s\n' "$out" > logs/last_session.json
# Look for limit messages only on FAILED runs: successful output can mention "rate limit" or contain 429 in numbers/ids.
verdict=$(printf '%s' "$out" | RC=$rc python3 -I -c '
import json, os, re, sys
res, other = None, []
for line in sys.stdin.read().splitlines():
    try: j = json.loads(line)
    except ValueError: j = None
    if isinstance(j, dict) and "is_error" in j: res = j
    else: other.append(line)
if os.environ["RC"] == "0" and res and not res["is_error"]:
    print("DONE turns=%s cost_equiv=%s err=false" % (res.get("num_turns"), res.get("total_cost_usd"))); sys.exit()
if res: other += [str(res.get(k, "")) for k in ("result", "errors", "error", "api_error_status", "subtype")]
pat = r"usage limit|rate.?limit|limit reached|hit your .{0,30}limit|out of extra usage|\b429\b|\b529\b|overloaded"
print("LIMIT" if re.search(pat, "\n".join(other), re.I) else "ERROR")
')
case "$verdict" in
  LIMIT)
    echo $(( $(date +%s) + RATE_LIMIT_PAUSE_SECONDS )) > state/pause_until
    echo "$(ts) LIMIT detected -> paused ${RATE_LIMIT_PAUSE_SECONDS}s (no retry)" >>$LOG ;;
  DONE*) echo "$(ts) DONE rc=0 ${verdict#DONE }" >>$LOG ;;
  *)
    echo $(( $(date +%s) + ERROR_PAUSE_SECONDS )) > state/pause_until
    echo "$(ts) ERROR rc=$rc -> paused ${ERROR_PAUSE_SECONDS}s; see logs/last_session.json" >>$LOG ;;
esac
python3 ops/ledger.py action agent_tick "session rc=$rc" >/dev/null
