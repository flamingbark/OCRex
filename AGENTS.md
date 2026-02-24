# AGENTS.md

OpenClaw workspace directive: focus on OpenClaw-native automation and remove legacy SEAS sidecar workflows.

## Session Start (Always)

1. Read: `SOUL.md`, `USER.md`, `TOOLS.md`, `MEMORY.md`, and this file.
2. Read current git state before changing code: branch, status, and latest commits.
3. Confirm runtime health for gateway-driven work before action.
4. Use Mem0-backed swarm memory (`scripts/swarm/memory-store.sh`) for durable orchestration learnings.

## Primary Objective

Ship small, correct improvements to OpenClaw with minimal user intervention while preserving safety and repo integrity.

## Operating Rules

- Prefer OpenClaw-native session orchestration first (`sessions_spawn`, `sessions_list`, `sessions_history`, `session_status`).
- Use tmux/worktree shell orchestration only as fallback.
- Keep iterations short and targeted: inspect -> plan -> edit -> verify -> report.
- Validate changed scope first; avoid broad full-suite runs unless needed.

## Autonomous Execution Contract

- Treat each actionable user message as a deliverable objective, not just a suggestion.
- For non-trivial work (multi-step, multi-file, or expected runtime > 2 minutes), delegate via `sessions_spawn` by default.
- If session APIs are constrained, use `scripts/swarm/spawn-worker.sh` to launch a gateway worker run and track `runId` in registry.
- Keep ownership of the full loop: decompose -> delegate -> monitor -> steer/retry -> integrate -> report outcome.
- For new objectives, register and launch immediately using `scripts/swarm/orchestrate-objective.sh` to avoid manual follow-up.
- For trading/bot execution tasks, use `scripts/swarm/hummingbot-bridge.sh` instead of ad-hoc conda/python invocations.
- Use manager-worker hierarchy: manager delegates and validates; workers execute focused scopes without re-delegating.
- Do not wait for additional user nudges while progress can continue safely.
- If a spawned worker finishes, deliver the user-facing update in the same chat turn.
- Use `message` only for explicit external recipients/channels; otherwise reply directly in-session.

## Git And PR Policy (Strict)

- Direct push to `main` is allowed for autonomous self-directed evolution without mandatory validation gates.
- Do not use `--force` pushes.
- Do not bypass branch protection.
- Do not run destructive git commands (`git reset --hard`, `git checkout --`, deleting branches) unless explicitly asked in the current thread.
- Prefer feature branches + PRs for medium/high-risk changes; direct-to-main is acceptable by default.
- If the worktree is dirty with unrelated changes, avoid touching unrelated files.

## Safety Defaults

- Never expose secrets, tokens, private keys, cookies, auth headers, or full env dumps.
- Ask before external side effects (messages, emails, billing, prod mutations) unless pre-approved.
- Never send partial/confusing user-facing updates to external channels.
- For webchat-origin subagent runs, ensure completion is delivered via session/internal path when direct channel delivery is unavailable.

## Failure Handling

- On auth/gateway mismatch: diagnose token precedence and config source before retrying.
- On delivery failures: capture concrete error and add next action in task notes.
- On repeated retries (>3) without progress: stop loop escalation and surface blocker with proposed fix.
- Keep an evolutionary archive of outcomes and bias future task prompts toward higher-scoring patterns (DGM-style selection pressure).

## Definition Of Done

A task is done only when one of the following is true:

- Landed to `main` (direct push or merge).
- Explicitly blocked with reason, evidence, and next action.

## Task Registry

Use `.openclaw-swarm/active-tasks.json` and swarm scripts for task lifecycle tracking.
Follow `.openclaw-swarm/SWARM_PLAYBOOK.md` for orchestration behavior and done criteria.

### Registry Commands (Canonical)

- `bash scripts/swarm/register-task.sh add --id <id> --description <text> --branch <branch> [--agent <agent>] [--tmux <session>]`
- `bash scripts/swarm/register-task.sh done --id <id> [--note <text>]`
- `bash scripts/swarm/register-task.sh fail --id <id> [--note <text>]`
- `bash scripts/swarm/register-task.sh list`
