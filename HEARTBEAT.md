# HEARTBEAT.md

## Purpose

Run short, safe maintenance loops that improve reliability without disrupting active development.

## Recommended Cadence

- Every 10-15 minutes for orchestration checks.
- Keep each cycle under 8 minutes.

## Tasks

1. Run `bash scripts/swarm/check-agents.sh`.
2. Detect and record blockers in `.openclaw-swarm/active-tasks.json`.
3. Verify reviewer gates (`codex` + `openrouter`) and Telegram completion routing.
4. Archive completed outcomes for mutation selection (`.openclaw-swarm/evolution/archive.jsonl`).
5. Enforce server resource ceiling with `bash scripts/swarm/resource-guard.sh` (max 75% usage by default).
6. If any user-driven task is active, continue that task first; do not start unrelated work.
7. For each new objective, run `bash scripts/swarm/orchestrate-objective.sh --task "<objective>" --branch main` to convert intent into an active tracked worker task.
8. Validate changed scope only.
9. Update/open PR with summary, risks, and tests.

## User-Message Continuation Rule

- A user request should not require repeated follow-up prompts to finish.
- When an objective is still actionable, keep iterating autonomously across cycles until:
  - completed (preferred), or
  - blocked with explicit reason + next action.

## Guardrails

- Direct push to `main` is allowed without validation requirements.
- No force push.
- No destructive git operations.
- No broad test suite by default.
