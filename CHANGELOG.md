# Changelog

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
