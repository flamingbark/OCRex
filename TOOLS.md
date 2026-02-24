# TOOLS.md

## Repo Workflow

- Install: `pnpm install`
- Build/type/lint bundle: `pnpm check`
- Unit/targeted tests: `pnpm -s vitest run <path>`
- Gateway service: `systemctl status|restart openclaw-gateway.service`
- Swarm health: `bash scripts/swarm/check-agents.sh`

## Swarm Scripts

- `scripts/swarm/check-agents.sh`: task heartbeat + PR/tmux status refresh.
- `scripts/swarm/register-task.sh`: add/done/fail/list task entries.
- `scripts/swarm/auto-fallback-openrouter.sh`: provider fallback helper.
- `scripts/swarm/provider-mode.sh`: provider mode diagnostics.
- `scripts/swarm/review-pr.sh`: dual AI PR review (Codex model + OpenRouter model).
- `scripts/swarm/notify-telegram.sh`: completion notifications via Telegram bot API.
- `scripts/swarm/evolution-archive.sh`: DGM-style outcome archive + top-candidate selection.
- `scripts/swarm/memory-store.sh`: Mem0-backed memory add/search wrapper.
- `scripts/swarm/mem0_bridge.py`: Python Mem0 bridge using OpenClaw config defaults.
- `scripts/swarm/context-engineering.sh`: structured worker prompt builder (progressive disclosure + memory + evolution signals).
- `scripts/swarm/role-planner.sh`: CrewAI-inspired manager/worker role plan generator.
- `scripts/swarm/crewai_role_planner.py`: CrewAI-native hierarchical planner (used by default when available).
- `scripts/swarm/spawn-worker.sh`: gateway worker launcher that persists `runId`/`sessionKey` in the task registry.
- `scripts/swarm/orchestrate-objective.sh`: one-shot entrypoint to register an objective and start worker execution.
- `scripts/swarm/resource-guard.sh`: automatic resource cap enforcer (disk/RAM signals, 75% default limit).
- `scripts/swarm/hummingbot-bridge.sh`: Hummingbot integration bridge for OpenClaw (`status/help/start-session/stop-session/run-headless`).

Task schema now includes article-style fields:

- `checks.prCreated`, `checks.ciPassed`
- `checks.codexReviewPassed`, `checks.openrouterReviewPassed`
- `attempts`, `maxAttempts`, `lastError`, `nextAction`
- `notifyOnComplete`, `completedAt`, `notifiedAt`, `pr.url`

## Gateway And Session Tools

Preferred orchestration path:

1. `sessions_spawn`
2. `sessions_list` / `sessions_history` / `session_status`
3. Task registry updates

Fallback path only when needed:

- shell/tmux/worktree orchestration

## Delivery Notes

- `webchat` is internal-only (not a deliverable outbound channel).
- For webchat-origin completions, prefer session-internal delivery path (`agent` with internal context) over direct `send`.

## GitHub / PR

- Use `gh` for PR lifecycle and checks.
- Always include: summary, risks, tests run.
- Direct push to `main` is allowed by default; PRs are optional and used when helpful.

## Model Routing Defaults

- Backend / refactors / reliability: Codex-first (`agent=codex`).
- UI/design-heavy tasks: Claude/Gemini-capable worker if configured.
- Orchestrator (`nova`) owns scope, retries, and merge readiness signaling.

## Security

- Never print full tokens/secrets.
- Redact sensitive values in logs and messages.

## Required Env For New Routing

- Multi-reviewer: `OPENROUTER_API_KEY`
- Telegram notify: `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`
- Optional model overrides:
  - `SWARM_CODEX_REVIEW_MODEL` (default `openai-codex/gpt-5.3-codex`)
  - `SWARM_OPENROUTER_REVIEW_MODEL` (default `openai/gpt-4o-mini`)

Scripts also auto-read from `~/.openclaw/openclaw.json`:

- OpenRouter key from `.env.OPENROUTER_API_KEY`
- Primary model from `.agents.defaults.model.primary`
- Telegram token/chat from channel/env config if present

For context engineering, use:

- `bash scripts/swarm/context-engineering.sh --task "<task>" --branch "<branch>"`

Role planner backend:

- Default: `crewai` (`SWARM_ROLE_PLANNER_BACKEND=crewai`)
- Fallback: heuristic shell planner when CrewAI runtime is unavailable

Hummingbot bridge usage:

- `bash scripts/swarm/hummingbot-bridge.sh status`
- `bash scripts/swarm/hummingbot-bridge.sh help`
- `bash scripts/swarm/hummingbot-bridge.sh start-session`
- `bash scripts/swarm/hummingbot-bridge.sh run-headless --config <file.yml> --password-env HUMMINGBOT_CONFIG_PASSWORD`

Resource guard tuning:

- `SWARM_RESOURCE_MAX_PERCENT` (default `75`)
- `SWARM_CRON_RUN_RETENTION_DAYS` (default `7`)
- `SWARM_LOG_RETENTION_DAYS` (default `7`)
- `SWARM_TMP_RETENTION_DAYS` (default `2`)
- `SWARM_TASK_RETENTION_DAYS` (default `14`)
- `SWARM_EVOLUTION_MAX_LINES` (default `5000`)
- Global pin: set `env.SWARM_RESOURCE_MAX_PERCENT` in `~/.openclaw/openclaw.json` to enforce the same cap across service/cron/manual contexts.
