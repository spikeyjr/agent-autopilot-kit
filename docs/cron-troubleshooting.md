# Claude Code cron job not running? Diagnose it from the log

For installs of [agent-autopilot-kit](https://github.com/spikeyjr/agent-autopilot-kit) on Linux. The checks in
section 1 work for any `claude -p` cron job. Run commands from the kit folder, and start with:

```bash
ops/status.sh            # stop file, pause, runs today, running session, cron entry, recent log
tail -n 20 logs/agent.log
tail -n 20 logs/cron.err
```

## 1. No new line in `logs/agent.log` at the scheduled time

Cron probably never got as far as the launcher.

| Check | Command / fix |
|---|---|
| Entry installed for this user | `crontab -l` should show a `claude-autopilot` block with this folder's path. If not, run `./install.sh` |
| Cron daemon running and enabled | Debian/Ubuntu: `systemctl is-active cron; systemctl is-enabled cron` (the service is `crond` on Fedora/RHEL) |
| What cron itself reported | `journalctl -u cron --since today` (or `-u crond`) |
| Machine was off or asleep | Plain cron does not replay missed runs. Wait for the next slot |
| Unexpected hour | The schedule follows the machine's timezone: check `date` |
| `%` in a hand-written crontab line | Cron treats an unescaped `%` as a newline. Write `\%` or move the command into a script |

**`claude` works in your terminal but not from cron:** cron starts with a much shorter `PATH` than your shell.
Reproduce that environment:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/sh -c 'claude --version'
```

If that says `not found`, the job needs the directory printed by `dirname "$(command -v claude)"` in its `PATH`.
`install.sh` adds it to each of its cron lines. If you reinstall or move Claude Code (for example, switch Node
versions with a version manager), run `./install.sh` again.

## 2. `SKIP` lines: the launcher ran and chose not to start

| Log line | Meaning | What to do |
|---|---|---|
| `SKIP overlap` | Another session holds the lock | Normal if one is running. If it repeats for over an hour, inspect `pgrep -af "claude -p"` |
| `SKIP guard: STOP file present` | Kill switch is on | Find out why in the log, fix that, then `rm state/STOP` |
| `SKIP guard: mission ended …` | Past `MISSION_END`; this also creates `state/STOP` | Set a new date in `ops/config.env`, then `rm state/STOP` |
| `SKIP guard: target reached …` | Ledger net reached `PROFIT_TARGET`; also creates `state/STOP` | Raise or disable the target (`0`), then `rm state/STOP` |
| `SKIP guard: invalid MISSION_END` or `invalid PROFIT_TARGET` | Config typo | Use `YYYY-MM-DD` and a plain number |
| `SKIP guard: invalid …_PAUSE_SECONDS` or `invalid MAX_AI_RUNS_PER_DAY` | A value such as `5h` or an empty setting | Use a plain whole number (pause lengths are seconds, above 0) |
| `SKIP guard: invalid state/pause_until` | The pause file is empty or not epoch seconds | `rm state/pause_until`, or write epoch seconds, e.g. `date -d "tomorrow 17:00" +%s` |
| `SKIP guard: ledger unreadable` | `ops/ledger.py summary` failed | Run `python3 ops/ledger.py summary` to see the error |
| `SKIP paused until …` | Earlier usage limit or failed run | See section 3. After a limit, wait it out |
| `SKIP daily cap` | `MAX_AI_RUNS_PER_DAY` used up (failed runs count too) | Wait for tomorrow, or raise the cap if your plan has headroom |
| `SKIP test invocation` | `AGENT_PROMPT` is set without `state/allow_test` | Expected for stray test calls; see the command `install.sh` prints |

## 3. The session started but did not do the job

The last run's JSON output is in `logs/last_session.json`. Read `result`, `subtype` and `permission_denials`.

| Symptom | Likely cause / fix |
|---|---|
| `ERROR rc=127` | `claude` was not found on the job's `PATH` (section 1) |
| `ERROR rc=126` | `claude` was found but could not be executed: check file permissions |
| `ERROR rc=124` | The 45-minute `timeout` ended the session. Make tasks smaller |
| Output reports a login or authentication error | Run `claude` interactively **as the same user** the cron job runs as, and log in |
| `subtype` is `error_max_turns` | The session hit `AI_MAX_TURNS`. Split the task, or raise the limit |
| `permission_denials` is not empty | A tool call was refused. Allow only what the job needs in `ops/agent_settings.json`; keep the deny rules |
| `LIMIT detected` | Usage or rate limit. The launcher pauses and does not retry; leave it paused |
| `START` with no `DONE`, `LIMIT` or `ERROR` | Still running, or the launcher was interrupted (reboot, kill) |
| `DONE`, but nothing useful changed | The agent follows `AGENTS.md` and `TASKS.md`. Check that the top task is concrete and unchecked |

After fixing the cause of an `ERROR`, you can lift the error pause with `rm state/pause_until`.

## 4. The AI runs, but your hooks do not

Hooks in `ops/hooks/*.py` are run by `ops_tick.py` every 15 minutes, not by the AI launcher. Check
`logs/ops.log` for the hook's `rc=` and error text, or `TIMEOUT`. Hooks are started with `python3 -I`, so they
ignore `PYTHON*` environment variables and your user site-packages directory.
