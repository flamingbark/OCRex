#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY_PATH="${REGISTRY_PATH:-$ROOT_DIR/.openclaw-swarm/active-tasks.json}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

usage() {
  cat <<'EOF'
Usage:
  register-task.sh add --id <id> --description <text> --branch <branch> [--tmux <session>] [--agent <agent>]
  register-task.sh done --id <id> [--note <text>]
  register-task.sh fail --id <id> [--note <text>]
  register-task.sh list
EOF
}

ensure_registry() {
  mkdir -p "$(dirname "$REGISTRY_PATH")"
  if [[ ! -f "$REGISTRY_PATH" ]]; then
    jq -n --arg now "$(date -Is)" '{updatedAt:$now,tasks:[]}' >"$REGISTRY_PATH"
  fi
}

cmd="${1:-}"
shift || true

ensure_registry

case "$cmd" in
  add)
    id=""
    description=""
    branch=""
    tmux_session=""
    agent="codex"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --id) id="$2"; shift 2 ;;
        --description) description="$2"; shift 2 ;;
        --branch) branch="$2"; shift 2 ;;
        --tmux) tmux_session="$2"; shift 2 ;;
        --agent) agent="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
      esac
    done
    if [[ -z "$id" || -z "$description" || -z "$branch" ]]; then
      usage
      exit 1
    fi
    now="$(date -Is)"
    jq \
      --arg id "$id" \
      --arg desc "$description" \
      --arg branch "$branch" \
      --arg tmux "$tmux_session" \
      --arg agent "$agent" \
      --arg now "$now" \
      '
      .tasks |= map(select(.id != $id))
      | .tasks += [{
          id:$id,
          description:$desc,
          branch:$branch,
          tmuxSession: (if $tmux == "" then null else $tmux end),
          agent:$agent,
          status:"running",
          startedAt:$now,
          heartbeatAt:$now,
          pr:{number:null,state:null}
        }]
      | .updatedAt=$now
      ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
    mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
    jq '.tasks[] | select(.id=="'"$id"'")' "$REGISTRY_PATH"
    ;;
  done|fail)
    id=""
    note=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --id) id="$2"; shift 2 ;;
        --note) note="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
      esac
    done
    if [[ -z "$id" ]]; then
      usage
      exit 1
    fi
    now="$(date -Is)"
    target_status="done"
    [[ "$cmd" == "fail" ]] && target_status="failed"
    jq \
      --arg id "$id" \
      --arg status "$target_status" \
      --arg note "$note" \
      --arg now "$now" \
      '
      .tasks |= map(
        if .id == $id then
          .status = $status
          | .completedAt = $now
          | .note = (if $note == "" then .note else $note end)
        else . end
      )
      | .updatedAt = $now
      ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
    mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
    jq '.tasks[] | select(.id=="'"$id"'")' "$REGISTRY_PATH"
    ;;
  list)
    jq . "$REGISTRY_PATH"
    ;;
  *)
    usage
    exit 1
    ;;
esac
