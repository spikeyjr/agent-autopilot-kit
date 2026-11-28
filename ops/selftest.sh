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
cp "$T/ops/config.env" "$T/config.good"; bad=0
for kv in MISSION_END=12/31/2099 MISSION_END=31-12-2000 MISSION_END= PROFIT_TARGET=1,000 PROFIT_TARGET= \
          RATE_LIMIT_PAUSE_SECONDS=5h RATE_LIMIT_PAUSE_SECONDS= RATE_LIMIT_PAUSE_SECONDS=0 ERROR_PAUSE_SECONDS=1h \
          ERROR_PAUSE_SECONDS=08 MAX_AI_RUNS_PER_DAY=three MAX_AI_RUNS_PER_DAY=; do
  sed -i "s|^${kv%%=*}=.*|$kv|" "$T/ops/config.env"; run
  grep -q "SKIP guard: invalid ${kv%%=*}" "$L" && ! grep -q "START session" "$L" && [ ! -f "$T/state/STOP" ] || { echo "  not handled: $kv -> $(tail -1 "$L")"; bad=1; }
  : > "$L"; rm -f "$T/state/STOP" "$T/state/runs_$(date +%F)"; cp "$T/config.good" "$T/ops/config.env"
done
[ $bad = 0 ] && { echo "PASS config typo skips the run without a permanent stop"; pass=$((pass+1)); } || { echo "FAIL config typo"; fail=$((fail+1)); }
# a pause file that cannot be read as an epoch must hold the agent, not be ignored
bad=0; echo ok > "$T/mode"
for v in "" "tomorrow 5pm" "2099-01-01"; do
  echo "$v" > "$T/state/pause_until"; rm -f "$T/state/status.json" "$T/state/runs_$(date +%F)"; run
  grep -q "SKIP guard: invalid state/pause_until" "$L" && ! grep -q "START session" "$L" || { echo "  ran or wrong log for '$v': $(tail -1 "$L")"; bad=1; }
  python3 "$T/ops/ops_tick.py" 2>"$T/tick.err" && grep -q '"may_run": false' "$T/state/status.json" && grep -q "invalid state/pause_until" "$T/state/status.json" || { echo "  ops tick for '$v': $(tail -1 "$T/tick.err")"; bad=1; }
  grep -q "pause: *INVALID" <<<"$("$T/ops/status.sh")" || { echo "  status.sh for '$v'"; bad=1; }
  : > "$L"
done
rm -f "$T/state/pause_until" "$T/state/runs_$(date +%F)"
[ $bad = 0 ] && { echo "PASS unreadable pause file holds the agent"; pass=$((pass+1)); } || { echo "FAIL unreadable pause file"; fail=$((fail+1)); }
sed -i 's/^MISSION_END=.*/MISSION_END=2000-01-01/' "$T/ops/config.env"; run; chk "30-day deadline stop" "mission ended"
python3 "$T/ops/ops_tick.py" && grep -q '"may_run": false' "$T/state/status.json" && { echo "PASS ops tick (no AI) reports stop"; pass=$((pass+1)); } || { echo "FAIL ops tick"; fail=$((fail+1)); }
mkdir -p "$T/ops/hooks"; rm -f "$T/state/status.json"
echo 'import time; time.sleep(5)' > "$T/ops/hooks/10_slow.py"
echo 'open("state/second_hook_ran","w").close()' > "$T/ops/hooks/20_next.py"
HOOK_TIMEOUT=1 python3 "$T/ops/ops_tick.py" 2>"$T/tick.err" && [ -f "$T/state/second_hook_ran" ] && [ -f "$T/state/status.json" ] && grep -q "10_slow.py TIMEOUT" "$T/logs/ops.log" && { echo "PASS hung hook does not stop the ops tick"; pass=$((pass+1)); } || { echo "FAIL hook timeout"; tail -1 "$T/tick.err"; fail=$((fail+1)); }
rm -f "$T"/ops/hooks/*.py; echo 'import time; open("state/hook_runs","a").write("x"); time.sleep(3)' > "$T/ops/hooks/10_slow.py"
python3 "$T/ops/ops_tick.py" & sleep 1; python3 "$T/ops/ops_tick.py"; wait
[ "$(cat "$T/state/hook_runs" 2>/dev/null)" = x ] && grep -q "SKIP overlap: another ops tick" "$T/logs/ops.log" && { echo "PASS overlapping ops tick skipped"; pass=$((pass+1)); } || { echo "FAIL ops tick overlap"; fail=$((fail+1)); }
# status.sh: reports each blocker and changes nothing (stub crontab: the real one is never read)
printf '#!/bin/sh\nexit 1\n' > "$T/bin/crontab"; chmod +x "$T/bin/crontab"
rm -f "$T/state/STOP"; echo 2 > "$T/state/runs_$(date +%F)"; echo $(( $(date +%s) + 3600 )) > "$T/state/pause_until"
snap(){ (cd "$T" && find state logs -type f -exec cksum {} + | sort); }
before=$(snap); a=$("$T/ops/status.sh"); after=$(snap)
touch "$T/state/STOP"; echo 1 > "$T/state/pause_until"
flock "$T/state/agent.lock" sleep 2 & sleep 1; b=$("$T/ops/status.sh"); wait
if [ "$before" = "$after" ] && grep -q "stop file: *none" <<<"$a" && grep -q "pause: *until" <<<"$a" && grep -q "runs today: *2/4" <<<"$a" && grep -q "session: *not running" <<<"$a" \
   && grep -q "stop file: *PRESENT" <<<"$b" && grep -q "pause: *none" <<<"$b" && grep -q "session: *running" <<<"$b"; then
  echo "PASS status reports blockers without changing state"; pass=$((pass+1)); else echo "FAIL status"; printf '%s\n---\n%s\n' "$a" "$b"; fail=$((fail+1)); fi
echo "selftest: $pass passed, $fail failed"; [ $fail -eq 0 ]
