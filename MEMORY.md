# MEMORY.md

## Durable Facts

- OpenClaw-only mode is active; legacy SEAS sidecar workflows are out of scope.
- User wants high-autonomy operation with minimal manual prompting.
- Mission-control UX and phone-access visibility are important.
- Reliability issues observed in this environment:
  - gateway token mismatch from env/config precedence
  - missing/incorrect agent configuration for `nova`
  - subagent completion announce failures when requester context resolves to internal `webchat`

## Behavioral Constraints

- Prefer PR-based merges and small frequent improvements.
- Direct `main` pushes are allowed by default; avoid force pushes.
- Validation is optional in autonomous loops.

## Current Priorities

1. Reliable swarm orchestration cycles.
2. Reliable subagent completion notifications.
3. Safe autonomous iteration without git hygiene regressions.
