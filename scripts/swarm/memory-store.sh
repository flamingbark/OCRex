#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRIDGE="$ROOT_DIR/scripts/swarm/mem0_bridge.py"
BACKEND="${SWARM_MEMORY_BACKEND:-mem0}"
USER_ID="${SWARM_MEMORY_USER_ID:-openclaw-swarm}"
AGENT_ID="${SWARM_MEMORY_AGENT_ID:-nova}"
PYTHON_BIN="${SWARM_MEMORY_PYTHON:-$ROOT_DIR/.venv/swarm/bin/python3}"

usage() {
  cat <<'EOF'
Usage:
  memory-store.sh add --text <text> [--run-id <id>] [--metadata-json <json>]
  memory-store.sh search --query <text> [--limit <n>] [--run-id <id>]
EOF
}

command="${1:-}"
shift || true

if [[ "$BACKEND" != "mem0" ]]; then
  echo '{"status":"skipped","reason":"non-mem0-backend"}'
  exit 0
fi

if [[ ! -f "$BRIDGE" ]]; then
  echo '{"status":"error","error":"mem0-bridge-missing"}'
  exit 1
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  else
    echo '{"status":"error","error":"python3-missing"}'
    exit 1
  fi
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo '{"status":"error","error":"python-runtime-missing"}'
  exit 1
fi

case "$command" in
  add)
    text=""
    run_id=""
    metadata_json=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --text) text="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        --metadata-json) metadata_json="$2"; shift 2 ;;
        *) usage; exit 1 ;;
      esac
    done
    if [[ -z "$text" ]]; then
      usage
      exit 1
    fi
    args=("$PYTHON_BIN" "$BRIDGE" add --user-id "$USER_ID" --agent-id "$AGENT_ID" --text "$text")
    [[ -n "$run_id" ]] && args+=(--run-id "$run_id")
    [[ -n "$metadata_json" ]] && args+=(--metadata-json "$metadata_json")
    "${args[@]}"
    ;;
  search)
    query=""
    limit="5"
    run_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --query) query="$2"; shift 2 ;;
        --limit) limit="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        *) usage; exit 1 ;;
      esac
    done
    if [[ -z "$query" ]]; then
      usage
      exit 1
    fi
    args=("$PYTHON_BIN" "$BRIDGE" search --user-id "$USER_ID" --agent-id "$AGENT_ID" --query "$query" --limit "$limit")
    [[ -n "$run_id" ]] && args+=(--run-id "$run_id")
    "${args[@]}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
