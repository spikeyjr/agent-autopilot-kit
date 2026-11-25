# How to run Claude Code on a schedule with cron (without surprise bills or burned limits)

Running `claude -p "..."` from cron looks like a one-liner. In practice, four things go wrong.
This guide explains each one and the guard that fixes it. Every guard is implemented in
[`ops/agent_tick.sh`](../ops/agent_tick.sh) in this repo, and tested by `ops/selftest.sh` against a stub `claude`.

*Unofficial. Not affiliated with Anthropic. Billing rules change: check the linked help-center pages.*

## 1. A stray API key switches you to metered billing

Signed in with a Pro/Max plan, `claude -p` draws from your subscription limits
([support.claude.com/en/articles/15036540](https://support.claude.com/en/articles/15036540-use-the-claude-plan-usage-limits)).
But if `ANTHROPIC_API_KEY` is present in the environment cron gives the job (crontab variables,
`/etc/environment`, a sourced profile), Claude Code may use the key, which is billed per token.

**Guard:** unset it in the launcher, every run:

```bash
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
```

Also check `apiKeyHelper` in your settings and any cloud-provider env vars, and verify with `claude auth status`.

## 2. Overlapping runs

A session that runs long collides with the next cron slot: two agents editing the same files.

**Guard:** a non-blocking lock. The second run exits immediately instead of queueing.

```bash
exec 9>state/agent.lock
flock -n 9 || { echo "another session running"; exit 0; }
```

## 3. Retrying into a usage limit

On a plan, scheduled runs share the rolling usage window with your interactive use. If a run fails on a
limit and the next slot simply tries again, you spend the fresh window on the same failure.

**Guard:** on a failed run, look for limit wording (`usage limit`, `rate limit`, `limit reached`, `429`,
`overloaded`), write a pause-until timestamp, and skip runs until then. Never retry automatically.
Only check *failed* runs: successful output can legitimately mention "rate limit" or contain `429` in an id.

```bash
echo $(( $(date +%s) + 18000 )) > state/pause_until    # 5 hours
```

## 4. Nothing ever stops it

**Guards:** a daily run cap, `--max-turns`, a hard `timeout 45m`, an end date checked before every run,
and a kill file (`touch state/STOP`).

## 5. Keep routine work out of the model

Most "agent" chores are deterministic: syncing data, rotating logs, checking a status page. Run them from a
plain cron tick (here: `ops/ops_tick.py` every 15 minutes, plus `ops/hooks/*.py`) so they keep working even
when you're out of usage, and reserve `claude -p` for work that needs judgment.

## 6. Test the guards without spending usage

Put a stub `claude` first on `PATH` that prints canned JSON (success, limit message, error, slow run),
then assert on the launcher's log. That is what `ops/selftest.sh` does: 12 checks, zero usage.

## Install

```bash
git clone https://github.com/spikeyjr/agent-autopilot-kit ~/autopilot && cd ~/autopilot
$EDITOR ops/config.env AGENTS.md TASKS.md
./install.sh
```
