#!/usr/bin/env bash
# Installs claude-autopilot cron entries for the current user (idempotent). Review before running.
set -eu; D="$(cd "$(dirname "$0")" && pwd)"; chmod +x "$D"/ops/*.sh "$D"/ops/*.py
case "$D" in *[[:space:]%]*) echo "install path must not contain spaces or %: $D"; exit 1;; esac
for req in AGENTS.md TASKS.md; do
  [ -f "$D/$req" ] || { echo "missing $D/$req (tells the agent what to do; copy from templates/ if your kit has it, or write your own)"; exit 1; }
done
mkdir -p "$D/state" "$D/logs"
CLAUDE_BIN="$(command -v claude || true)"; [ -z "$CLAUDE_BIN" ] && { echo "claude CLI not found in PATH"; exit 1; }
CRON_PATH="$(dirname "$CLAUDE_BIN"):/usr/local/bin:/usr/bin:/bin"
case "$CRON_PATH" in *[[:space:]%]*) echo "claude install dir must not contain spaces or %: $CLAUDE_BIN"; exit 1;; esac
echo "Running safeguard self-test (stub claude, zero usage)..."; "$D/ops/selftest.sh"
SLOTS="${SLOTS:-17 3,11,19 * * *}"
block="# >>> claude-autopilot $D
*/15 * * * * PATH=$CRON_PATH $D/ops/ops_tick.py >>$D/logs/cron.err 2>&1
@reboot sleep 90 && PATH=$CRON_PATH $D/ops/ops_tick.py >>$D/logs/cron.err 2>&1
$SLOTS PATH=$CRON_PATH /bin/bash $D/ops/agent_tick.sh >>$D/logs/cron.err 2>&1
# <<< claude-autopilot $D"
current="$(crontab -l 2>/dev/null | sed "\|^# >>> claude-autopilot $D\$|,\|^# <<< claude-autopilot $D\$|d")"
printf '%s\n%s\n' "$current" "$block" | crontab -
echo "Installed. Schedule: $SLOTS. Kill switch: touch $D/state/STOP"
echo "Verify one real run (tiny haiku call): touch $D/state/allow_test && AGENT_PROMPT='Reply with exactly: CRON_OK' AI_MODEL=haiku $D/ops/agent_tick.sh; tail -1 $D/logs/agent.log; rm $D/state/allow_test"
