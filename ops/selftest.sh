#!/usr/bin/env bash
# Exercises every safeguard against a stub `claude` (zero AI usage). Exit 0 = all pass.
set -u; SRC="$(cd "$(dirname "$0")/.." && pwd)"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ops" "$T/state" "$T/logs" "$T/bin"; cp "$SRC"/ops/*.sh "$SRC"/ops/*.py "$SRC"/ops/*.json "$SRC"/ops/config.env "$T/ops/"
cat > "$T/bin/claude" <<'S'
#!/usr/bin/env bash
[ -n "${ANTHROPIC_API_KEY:-}" ] && { echo "APIKEY_LEAK"; exit 9; }
case "$(cat "$STUB_MODE")" in
 ok) echo '{"result":"ok","is_error":false,"num_turns":1,"total_cost_usd":0}';;
 slow) sleep 3; echo '{"result":"ok","is_error":false,"num_turns":1,"total_cost_usd":0}';;
 limit) echo '{"result":"Claude usage limit reached. Resets 5pm","is_error":true}'; exit 1;;
 fail) echo 'boom'; exit 2;;
 mention) echo '{"result":"edited the rate limit docs","is_error":false,"num_turns":429,"total_cost_usd":0.429}';;
 hit) echo '{"result":"You have hit your limit, resets 5pm","is_error":true}';;
esac
S
sed -i -e "s/^PROFIT_TARGET=.*/PROFIT_TARGET=100/" -e "s/^MAX_AI_RUNS_PER_DAY=.*/MAX_AI_RUNS_PER_DAY=4/" -e "s/^MISSION_END=.*/MISSION_END=2099-01-01/" "$T/ops/config.env"
chmod +x "$T/bin/claude"; export PATH="$T/bin:$PATH" STUB_MODE="$T/mode" ANTHROPIC_API_KEY=sk-should-be-stripped
pass=0; fail=0; L="$T/logs/agent.log"
chk(){ if grep -q "$2" "$L"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; tail -3 "$L"; fail=$((fail+1)); fi; : > "$L"; }
run(){ "$T/ops/agent_tick.sh"; }
echo ok > "$T/mode"; run; chk "normal run + api key stripped" "DONE rc=0"
echo slow > "$T/mode"; run & sleep 1; run; wait; chk "overlap prevented" "SKIP overlap"
echo limit > "$T/mode"; run; chk "usage limit -> pause" "LIMIT detected"
run; chk "no retry while paused" "SKIP paused"; rm -f "$T/state/pause_until"
rm -f "$T/state/runs_$(date +%F)"
echo mention > "$T/mode"; run; chk "successful run mentioning limits is not paused" "DONE rc=0"
echo hit > "$T/mode"; run; chk "limit reported with exit 0 -> pause" "LIMIT detected"; rm -f "$T/state/pause_until" "$T/state/runs_$(date +%F)"
echo fail > "$T/mode"; run; chk "error -> backoff" "ERROR rc=2"; rm -f "$T/state/pause_until"
echo 4 > "$T/state/runs_$(date +%F)"; echo ok > "$T/mode"; run; chk "daily cap" "SKIP daily cap"; rm "$T/state/runs_$(date +%F)"
AGENT_PROMPT=x run; chk "unarmed test invocation ignored" "SKIP test invocation"
python3 "$T/ops/ledger.py" revenue 120 test selftest >/dev/null; run; chk "profit target stop" "target reached"; rm -f "$T/state/STOP" "$T/state/ledger.db"
echo "not a database, just a corrupted file" > "$T/state/ledger.db"; run
grep -q "SKIP guard: ledger unreadable" "$L" && [ ! -f "$T/state/STOP" ] && { echo "PASS unreadable ledger skips the run without a permanent stop"; pass=$((pass+1)); } || { echo "FAIL unreadable ledger"; tail -3 "$L"; fail=$((fail+1)); }
: > "$L"; rm -f "$T/state/STOP" "$T/state/ledger.db"
sed -i 's/^MISSION_END=.*/MISSION_END=2000-01-01/' "$T/ops/config.env"; run; chk "30-day deadline stop" "mission ended"
python3 "$T/ops/ops_tick.py" && grep -q '"may_run": false' "$T/state/status.json" && { echo "PASS ops tick (no AI) reports stop"; pass=$((pass+1)); } || { echo "FAIL ops tick"; fail=$((fail+1)); }
mkdir -p "$T/ops/hooks"; rm -f "$T/state/status.json"
echo 'import time; time.sleep(5)' > "$T/ops/hooks/10_slow.py"
echo 'open("state/second_hook_ran","w").close()' > "$T/ops/hooks/20_next.py"
HOOK_TIMEOUT=1 python3 "$T/ops/ops_tick.py" 2>"$T/tick.err" && [ -f "$T/state/second_hook_ran" ] && [ -f "$T/state/status.json" ] && grep -q "10_slow.py TIMEOUT" "$T/logs/ops.log" && { echo "PASS hung hook does not stop the ops tick"; pass=$((pass+1)); } || { echo "FAIL hook timeout"; tail -1 "$T/tick.err"; fail=$((fail+1)); }
echo "selftest: $pass passed, $fail failed"; [ $fail -eq 0 ]
