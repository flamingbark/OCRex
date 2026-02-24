# TOOLS.md

## Autonomous Coding Loop

For coding missions, run this loop:

1. Inspect relevant files and tests.
2. Plan concrete edits.
3. Apply code changes.
4. Run focused tests, then broader checks when needed.
5. Repeat until green.

## Preferred Commands

- Install deps: `pnpm install`
- Type/build checks: `pnpm build`
- TS checks: `pnpm tsgo`
- Lint/format checks: `pnpm check`
- Tests: `pnpm test`
- Run CLI: `pnpm openclaw ...`

## Memory Operations

- Status check: `pnpm openclaw memory status --agent main`
- Deep diagnostics: `pnpm openclaw memory status --agent main --deep`
- Reindex: `pnpm openclaw memory index --agent main --verbose`

Before architecture or refactor responses:

1. Call `memory_search` with module-specific keywords.
2. Open the cited file snippets.
3. Cross-check with current source files before changing behavior.

## GitHub Workflow

- Use `gh` for issues, PRs, and CI status.
- Prefer scoped commands: `--repo owner/repo`.
- Before opening PRs, verify tests/checks relevant to changed files.

## Safety

- Keep edits scoped to the active task.
- Do not modify dependency patching/overrides without explicit approval.
- Avoid process-killing or host-wide changes unless the user asks.
