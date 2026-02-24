#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTER_SCRIPT="$ROOT_DIR/scripts/swarm/register-task.sh"
SPAWN_SCRIPT="$ROOT_DIR/scripts/swarm/spawn-worker.sh"
REGISTRY_PATH="${REGISTRY_PATH:-$ROOT_DIR/.openclaw-swarm/active-tasks.json}"

TASK=""
BRANCH="main"
TASK_ID=""
AGENT="codex"
AGENT_ID="nova"
NOTIFY_ON_COMPLETE="true"

usage() {
  cat <<'USAGE'
Usage:
  orchestrate-objective.sh --task <description> [--branch <branch>] [--task-id <id>] [--agent <agent>] [--agent-id <agent-id>] [--notify-on-complete <true|false>]

Creates/updates task registry entry and immediately spawns a worker run.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --task-id) TASK_ID="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --notify-on-complete) NOTIFY_ON_COMPLETE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$TASK" ]]; then
  usage
  exit 1
fi

if [[ -z "$TASK_ID" ]]; then
  slug="$(echo "$TASK" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-48)"
  [[ -n "$slug" ]] || slug="task"
  TASK_ID="${slug}-$(date +%s)"
fi

if [[ ! -x "$REGISTER_SCRIPT" ]]; then
  echo "missing register script: $REGISTER_SCRIPT" >&2
  exit 2
fi
if [[ ! -x "$SPAWN_SCRIPT" ]]; then
  echo "missing spawn script: $SPAWN_SCRIPT" >&2
  exit 2
fi

"$REGISTER_SCRIPT" add \
  --id "$TASK_ID" \
  --description "$TASK" \
  --branch "$BRANCH" \
  --agent "$AGENT" \
  --notify-on-complete "$NOTIFY_ON_COMPLETE" \
  --max-attempts 3 >/dev/null

"$SPAWN_SCRIPT" \
  --task-id "$TASK_ID" \
  --task "$TASK" \
  --branch "$BRANCH" \
  --agent-id "$AGENT_ID" \
  --registry-path "$REGISTRY_PATH"
