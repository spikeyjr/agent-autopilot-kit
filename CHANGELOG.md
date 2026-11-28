# Changelog

## 2026-11-28
- Fix: a `state/pause_until` that was empty or not epoch seconds (for example a hand-written date) did not pause
  anything: the launcher printed a shell error and started the session, and the ops tick crashed. Such a file now
  holds the agent, logs the reason, and `ops/status.sh` shows it as INVALID. New selftest check.

## 2026-11-27
- docs/cron-troubleshooting.md: diagnose a scheduled run from its log line (PATH, SKIP reasons, exit codes, hooks).
- New: `ops/status.sh`, a read-only one-screen summary (stop file, pause, runs today, end date, running session,
  cron entry, last ops tick, recent launcher log). New selftest check.
- Fix: a typo in `ops/config.env` could stop the agent for good or ignore the deadline. `PROFIT_TARGET=1,000` or an
  empty value was reported as "target reached" and created `state/STOP`; `MISSION_END=12/31/2099` read as already
  ended; a day-first date such as `31-12-2000` never expired. Invalid values now skip the run, log the reason, and
  resume once fixed. New selftest check.

## 2026-11-26
- Fix: the no-AI ops tick had no lock, so slow hooks running past the 15-minute interval could run twice at once
  (duplicate actions). A second tick now logs SKIP and exits. New selftest check.
- Fix: if the ledger could not be read (corrupted or failing database) while a profit target was set, the stop check
  reported "target reached" and created `state/STOP`, halting the agent for good. It now skips that run and re-checks
  next time. New selftest check.
- Fix: a hook running past the 300s timeout crashed the ops tick (later hooks skipped, status.json stale). It is now
  killed and logged as TIMEOUT, and the tick continues. Non-UTF-8 hook output no longer crashes it. New selftest check.
- docs/run-claude-code-on-cron.md: guide to the four failure modes of scheduled `claude -p` and their guards.

## 2026-11-25
- Initial release: launcher (lock, daily cap, max-turns + timeout, usage-limit pause without retry, error
  backoff, API-key stripping), stop checks, no-AI ops tick with hooks, SQLite ledger, stub-based selftest.
