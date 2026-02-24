---
summary: "CLI reference for `openclaw cron` (schedule and run background jobs)"
read_when:
  - You want scheduled jobs and wakeups
  - You’re debugging cron execution and logs
title: "cron"
---

# `openclaw cron`

Manage cron jobs for the Gateway scheduler.

Related:

- Cron jobs: [Cron jobs](/automation/cron-jobs)

Tip: run `openclaw cron --help` for the full command surface.

Note: isolated `cron add` jobs default to `--announce` delivery. Use `--no-deliver` to keep
output internal. `--deliver` remains as a deprecated alias for `--announce`.

Note: one-shot (`--at`) jobs delete after success by default. Use `--keep-after-run` to keep them.

Note: recurring jobs now use exponential retry backoff after consecutive errors (30s → 1m → 5m → 15m → 60m), then return to normal schedule after the next successful run.

## Autonomous self-improvement loop

Bootstrap a safe, isolated recurring improvement agent:

```bash
openclaw cron autonomy
```

This creates an isolated agent-turn cron job that runs a built-in loop:
inspect → plan → edit → validate → summarize.
Autonomy jobs keep output internal by default; add `--announce` to deliver summaries.
Default cadence is `15m`, with cron-safe guidance to avoid full-suite test runs.

Customize objective, cadence, and validation command:

```bash
openclaw cron autonomy \
  --every 30m \
  --objective "Improve OpenClaw reliability and reduce noisy permission prompts" \
  --test-command "pnpm test:fast"
```

`--replace` is on by default: one matching job is updated in place (history preserved); duplicates are reconciled to one job.
Use `--no-replace` to fail if a job with the same name already exists.

## Common edits

Update delivery settings without changing the message:

```bash
openclaw cron edit <job-id> --announce --channel telegram --to "123456789"
```

Disable delivery for an isolated job:

```bash
openclaw cron edit <job-id> --no-deliver
```

Announce to a specific channel:

```bash
openclaw cron edit <job-id> --announce --channel slack --to "channel:C1234567890"
```
