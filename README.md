# agent-autopilot-kit

*Unofficial. Not affiliated with or endorsed by Anthropic.*


Run Claude Code on a schedule (cron) with guards against **stray API keys, overlapping runs, and retrying into usage limits**.

A small kit (bash + Python stdlib + SQLite, no pip packages) that turns `claude -p` into a
resumable background worker on Linux. Needs `python3`, `flock`, `timeout`, cron and the `claude` CLI.

## Safeguards

| Safeguard | How |
|---|---|
| Stray API keys ignored | Launcher unsets `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` so runs use your plan login (check `apiKeyHelper` and cloud-provider settings yourself) |
| No overlapping runs | `flock` lock — a second run exits immediately |
| Respects usage limits | Detects usage/rate-limit messages on failed runs → pauses 5h → **never retries** |
| Error backoff | Failed run → 1h pause, full output saved to `logs/last_session.json` |
| Daily budget | `MAX_AI_RUNS_PER_DAY` hard cap |
| Bounded sessions | `--max-turns` + 45-minute `timeout` |
| Stop conditions | End date, optional ledger target, or `touch state/STOP` |
| Survives reboots | cron `@reboot` + all state on disk; no daemon to babysit |
| Works without AI | `ops_tick.py` runs every 15 min with zero inference and runs your `ops/hooks/*.py` |
| Scoped permissions | `ops/agent_settings.json` denies sudo, git push, crontab edits, credential reads |
| Audit trail | SQLite ledger of actions (and money, if you track it) + plain-text logs |

`ops/selftest.sh` tests the launcher and stop checks against a **stub** `claude` (zero usage). It does
not test reboot behavior or the permission rules. Those rules are guardrails, **not a sandbox**: shell
access is allowed, so run the agent as an unprivileged user with nothing sensitive in reach.

## Install (2 minutes)

```bash
git clone https://github.com/spikeyjr/agent-autopilot-kit ~/autopilot && cd ~/autopilot
$EDITOR ops/config.env        # dates, run cap, model
$EDITOR AGENTS.md TASKS.md    # required: tell the agent what to do (minimal example below)
./install.sh                  # runs selftest, then installs cron entries (idempotent)
```

Default schedule: 03:17, 11:17, 19:17. Override: `SLOTS='0 */8 * * *' ./install.sh`.

## Billing facts (check the sources yourself, they change)

- Signed in with a Pro/Max plan, `claude -p` **draws from your subscription limits**, the same pool as
  interactive use — [support.claude.com/en/articles/15036540](https://support.claude.com/en/articles/15036540-use-the-claude-plan-usage-limits).
- Monthly API credits exist for Max/Ultra/Team only, and apply only with a linked Console API key —
  [support.claude.com/en/articles/17154008](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-ultra-and-team-plans).
- If an API key is present in the environment, Claude Code may use it, and that's metered billing. This kit strips it.
- Keep "extra usage" off in your Claude account settings if you never want charges.

On Pro, every scheduled run competes with your own interactive usage. Start with a low
`MAX_AI_RUNS_PER_DAY` and short sessions, and raise it only if you still have headroom.

## Minimal AGENTS.md / TASKS.md

The agent does exactly what these two files say. Smallest useful version:

```markdown
<!-- AGENTS.md -->
Each session: read TASKS.md, do the top unchecked task, check it off, append 2 lines to PROGRESS.md, stop.
Never: spend money, post/email anyone, push to git, edit crontab, use sudo, or retry after a usage limit.
```

```markdown
<!-- TASKS.md -->
- [ ] Summarize yesterday's logs/app.log into reports/$(date +%F).md
```

## Files

```
ops/agent_tick.sh      AI session launcher (cron)
ops/guard.sh           stop/deadline/target checks
ops/ops_tick.py        no-AI tick + hooks runner + status.json
ops/ledger.py          SQLite actions/revenue/expense ledger
ops/selftest.sh        safeguard tests with stub claude
ops/agent_settings.json permissions for scheduled sessions
```

## Operating

- Status: `cat state/status.json` · Logs: `tail logs/agent.log`
- Pause now: `echo $(( $(date +%s) + 86400 )) > state/pause_until`
- Stop: `touch state/STOP` · Uninstall: remove the `claude-autopilot` block from `crontab -e`

## License

MIT
