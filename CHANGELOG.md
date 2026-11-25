# Changelog

## 2026-11-26
- docs/run-claude-code-on-cron.md: guide to the four failure modes of scheduled `claude -p` and their guards.

## 2026-11-25
- Initial release: launcher (lock, daily cap, max-turns + timeout, usage-limit pause without retry, error
  backoff, API-key stripping), stop checks, no-AI ops tick with hooks, SQLite ledger, stub-based selftest.
