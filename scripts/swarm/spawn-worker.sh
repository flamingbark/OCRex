#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY_PATH="${REGISTRY_PATH:-$ROOT_DIR/.openclaw-swarm/active-tasks.json}"
CONTEXT_ENGINEERING_SCRIPT="$ROOT_DIR/scripts/swarm/context-engineering.sh"
if [[ -x "$ROOT_DIR/dist/entry.js" ]]; then
  OPENCLAW_CLI_CMD="${OPENCLAW_CLI_CMD:-node $ROOT_DIR/dist/entry.js}"
else
  OPENCLAW_CLI_CMD="${OPENCLAW_CLI_CMD:-pnpm -s openclaw}"
fi

TASK_ID=""
TASK=""
BRANCH="main"
AGENT_ID="nova"
SESSION_KEY=""
REGISTRY_ONLY="false"

usage() {
  cat <<'USAGE'
Usage:
  spawn-worker.sh --task-id <id> --task <text> [--branch <branch>] [--agent-id <agent>] [--session-key <key>] [--registry-path <path>] [--registry-only <true|false>]

Behavior:
- Builds a context-engineered worker prompt.
- Starts a worker turn via gateway `agent` call.
- Stores `runId` and `sessionKey` in .openclaw-swarm/active-tasks.json for monitor loop tracking.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) TASK_ID="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --session-key) SESSION_KEY="$2"; shift 2 ;;
    --registry-path) REGISTRY_PATH="$2"; shift 2 ;;
    --registry-only) REGISTRY_ONLY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$TASK_ID" || -z "$TASK" ]]; then
  usage
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

if [[ ! -f "$REGISTRY_PATH" ]]; then
  mkdir -p "$(dirname "$REGISTRY_PATH")"
  jq -n --arg now "$(date -Is)" '{updatedAt:$now,tasks:[]}' >"$REGISTRY_PATH"
fi

if [[ -z "$SESSION_KEY" ]]; then
  SESSION_KEY="agent:${AGENT_ID}:main"
fi

now_iso="$(date -Is)"
if [[ "$REGISTRY_ONLY" == "true" ]]; then
  jq \
    --arg id "$TASK_ID" \
    --arg now "$now_iso" \
    '
    .tasks |= map(
      if (.id|tostring) == $id then
        .status = "running"
        | .heartbeatAt = $now
        | .lastError = null
        | .nextAction = "worker queued"
      else . end
    )
    | .updatedAt = $now
    ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
  mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
  jq -n --arg status "queued" --arg taskId "$TASK_ID" '{status:$status,taskId:$taskId}'
  exit 0
fi

prompt=""
if [[ -x "$CONTEXT_ENGINEERING_SCRIPT" ]]; then
  prompt="$($CONTEXT_ENGINEERING_SCRIPT --task "$TASK" --branch "$BRANCH" 2>/dev/null || true)"
fi
if [[ -z "$prompt" ]]; then
  prompt="Task: $TASK\nBranch: $BRANCH\nImplement smallest complete increment and report outcome."
fi

idempotency_key="swarm-${TASK_ID//[^a-zA-Z0-9_-]/-}-$(date +%s)"
params_json="$(jq -cn \
  --arg sessionKey "$SESSION_KEY" \
  --arg message "$prompt" \
  --arg idempotencyKey "$idempotency_key" \
  '{sessionKey:$sessionKey,message:$message,idempotencyKey:$idempotencyKey}')"

set +e
agent_response_raw="$($OPENCLAW_CLI_CMD gateway call agent --json --params "$params_json" --timeout 20000 2>/dev/null)"
call_status=$?
set -e

if [[ $call_status -ne 0 ]]; then
  jq \
    --arg id "$TASK_ID" \
    --arg now "$now_iso" \
    --arg err "gateway-agent-call-failed" \
    '
    .tasks |= map(
      if (.id|tostring) == $id then
        .status = "needs_attention"
        | .heartbeatAt = $now
        | .lastError = $err
        | .nextAction = "Verify gateway auth/token and rerun spawn-worker.sh"
      else . end
    )
    | .updatedAt = $now
    ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
  mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
  jq -n --arg status "error" --arg taskId "$TASK_ID" --arg error "gateway-agent-call-failed" '{status:$status,taskId:$taskId,error:$error}'
  exit 1
fi

agent_response="$(sed -n '/^[[:space:]]*{/,$p' <<<"$agent_response_raw")"
run_id="$(jq -r '.runId // empty' <<<"$agent_response" 2>/dev/null || true)"
spawn_status="$(jq -r '.status // "accepted"' <<<"$agent_response" 2>/dev/null || echo "accepted")"

jq \
  --arg id "$TASK_ID" \
  --arg now "$now_iso" \
  --arg runId "$run_id" \
  --arg sessionKey "$SESSION_KEY" \
  --arg spawnStatus "$spawn_status" \
  '
  .tasks |= map(
    if (.id|tostring) == $id then
      .status = "running"
      | .runId = (if $runId == "" then .runId else $runId end)
      | .sessionKey = $sessionKey
      | .heartbeatAt = $now
      | .lastError = null
      | .nextAction = ("worker running (" + $spawnStatus + ")")
    else . end
  )
  | .updatedAt = $now
  ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"

jq -n \
  --arg status "$spawn_status" \
  --arg taskId "$TASK_ID" \
  --arg runId "$run_id" \
  --arg sessionKey "$SESSION_KEY" \
  '{status:$status,taskId:$taskId,runId:$runId,sessionKey:$sessionKey}'
