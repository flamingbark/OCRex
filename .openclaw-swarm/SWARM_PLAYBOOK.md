# OpenClaw Swarm Playbook (Zoe-Style)

This workspace follows a one-orchestrator + many-worker pattern:

1. User request arrives to `nova` (orchestrator).
2. `nova` scopes the task and spawns specialized worker sessions.
3. Each worker executes one focused objective.
4. Worker progress is tracked in `.openclaw-swarm/active-tasks.json`.
5. `scripts/swarm/check-agents.sh` refreshes tmux/PR/check status.
6. Multi-reviewer gate runs (`codex` + `openrouter`) after CI is green.
7. Failures trigger retries (`attempts` up to `maxAttempts`) with tighter prompts.
8. When checks are green and branch policy allows, orchestrator merges/pushes.
9. Completion notification is routed to Telegram when `notifyOnComplete=true`.
10. Completed/failed tasks are archived with scores for next-cycle selection pressure.

Evolution strategy is inspired by DGM-style iterative generation/evaluation/selection:
https://github.com/jennyzzt/dgm

Context engineering flow is inspired by:
https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering

Role orchestration patterns are informed by CrewAI:
https://github.com/crewAIInc/crewAI

## Definition Of Done

Task is done when one of:

- merged to `main`, or
- blocked with explicit `lastError` + `nextAction`.

## Required Registry Fields

Each task entry should include:

- `id`, `description`, `branch`, `agent`, `status`
- `attempts`, `maxAttempts`
- `checks.prCreated`, `checks.ciPassed`
- `checks.codexReviewPassed`, `checks.openrouterReviewPassed`
- `lastError`, `nextAction`
- `pr.number`, `pr.state`, `pr.url`
- `notifyOnComplete`, `notifiedAt`
- `evolutionLoggedAt`, `evolutionScore`

## Operational Notes

- Prefer OpenClaw-native orchestration tools first (`sessions_spawn`, `subagents`, `sessions_list/history/status`).
- Use tmux/worktree shell fallback only when session tools are insufficient.
- Keep work small and parallel where possible.
- Do not require repeated user prompting for a still-actionable request.
- DGM-inspired loop: archive outcomes -> rank by score -> bias next mutations toward high-scoring patterns.
- Build worker prompts via `scripts/swarm/context-engineering.sh` before `sessions_spawn`.
- Use Mem0 as long-term memory backend via `scripts/swarm/memory-store.sh`.
- Use hierarchical manager-worker planning (`scripts/swarm/role-planner.sh`):
  manager delegates, workers execute, manager validates and integrates.
