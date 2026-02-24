#!/usr/bin/env bash
set -euo pipefail

HUMMINGBOT_HOME="${HUMMINGBOT_HOME:-/root/Desktop/hummingbot}"
HUMMINGBOT_CONDA_EXE="${HUMMINGBOT_CONDA_EXE:-/root/miniconda3/bin/conda}"
HUMMINGBOT_ENV_NAME="${HUMMINGBOT_ENV_NAME:-hummingbot}"
HUMMINGBOT_SESSION="${HUMMINGBOT_SESSION:-hummingbot-main}"
HUMMINGBOT_LOG_DIR="${HUMMINGBOT_LOG_DIR:-$HOME/.openclaw/hummingbot}"

mkdir -p "$HUMMINGBOT_LOG_DIR"

usage() {
  cat <<'USAGE'
Usage:
  hummingbot-bridge.sh status
  hummingbot-bridge.sh help
  hummingbot-bridge.sh start-session
  hummingbot-bridge.sh stop-session
  hummingbot-bridge.sh logs [--lines <n>]
  hummingbot-bridge.sh run-headless --config <file.yml> [--script-conf <file.yml>] [--password-env <ENV_NAME>]

Notes:
- `run-headless` is non-interactive and suited for OpenClaw automation.
- Password is read from env var (default: HUMMINGBOT_CONFIG_PASSWORD).
USAGE
}

require_bin() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required binary: $name" >&2
    exit 2
  fi
}

require_hummingbot_install() {
  if [[ ! -x "$HUMMINGBOT_CONDA_EXE" ]]; then
    echo "conda not found: $HUMMINGBOT_CONDA_EXE" >&2
    exit 2
  fi
  if [[ ! -d "$HUMMINGBOT_HOME" ]]; then
    echo "hummingbot repo not found: $HUMMINGBOT_HOME" >&2
    exit 2
  fi
  if [[ ! -f "$HUMMINGBOT_HOME/bin/hummingbot_quickstart.py" ]]; then
    echo "hummingbot quickstart not found in: $HUMMINGBOT_HOME" >&2
    exit 2
  fi
}

cmd="${1:-}"
shift || true

case "$cmd" in
  status)
    require_hummingbot_install
    env_ok="false"
    if "$HUMMINGBOT_CONDA_EXE" env list | awk '{print $1}' | grep -qx "$HUMMINGBOT_ENV_NAME"; then
      env_ok="true"
    fi
    hb_commit=""
    if command -v git >/dev/null 2>&1 && [[ -d "$HUMMINGBOT_HOME/.git" ]]; then
      hb_commit="$(git -C "$HUMMINGBOT_HOME" rev-parse --short HEAD 2>/dev/null || true)"
    fi
    py_ver="$($HUMMINGBOT_CONDA_EXE run -n "$HUMMINGBOT_ENV_NAME" python --version 2>/dev/null || true)"
    jq -n \
      --arg home "$HUMMINGBOT_HOME" \
      --arg conda "$HUMMINGBOT_CONDA_EXE" \
      --arg env "$HUMMINGBOT_ENV_NAME" \
      --arg envOk "$env_ok" \
      --arg commit "$hb_commit" \
      --arg py "$py_ver" \
      '{hummingbotHome:$home,conda:$conda,env:$env,envExists:($envOk=="true"),commit:(if $commit=="" then null else $commit end),python:(if $py=="" then null else $py end)}'
    ;;

  help)
    require_hummingbot_install
    cd "$HUMMINGBOT_HOME"
    "$HUMMINGBOT_CONDA_EXE" run -n "$HUMMINGBOT_ENV_NAME" python bin/hummingbot_quickstart.py --help
    ;;

  start-session)
    require_hummingbot_install
    require_bin tmux
    if tmux has-session -t "$HUMMINGBOT_SESSION" >/dev/null 2>&1; then
      jq -n --arg status "already_running" --arg session "$HUMMINGBOT_SESSION" '{status:$status,session:$session}'
      exit 0
    fi
    tmux new-session -d -s "$HUMMINGBOT_SESSION" -c "$HUMMINGBOT_HOME" \
      "$HUMMINGBOT_CONDA_EXE run -n $HUMMINGBOT_ENV_NAME python bin/hummingbot.py" \
      >>"$HUMMINGBOT_LOG_DIR/session.log" 2>&1
    jq -n --arg status "started" --arg session "$HUMMINGBOT_SESSION" '{status:$status,session:$session}'
    ;;

  stop-session)
    require_bin tmux
    if tmux has-session -t "$HUMMINGBOT_SESSION" >/dev/null 2>&1; then
      tmux kill-session -t "$HUMMINGBOT_SESSION"
      jq -n --arg status "stopped" --arg session "$HUMMINGBOT_SESSION" '{status:$status,session:$session}'
    else
      jq -n --arg status "not_running" --arg session "$HUMMINGBOT_SESSION" '{status:$status,session:$session}'
    fi
    ;;

  logs)
    lines="200"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --lines) lines="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
      esac
    done
    if [[ -f "$HUMMINGBOT_LOG_DIR/session.log" ]]; then
      tail -n "$lines" "$HUMMINGBOT_LOG_DIR/session.log"
    else
      echo "no logs yet"
    fi
    ;;

  run-headless)
    require_hummingbot_install
    config_file=""
    script_conf=""
    password_env="HUMMINGBOT_CONFIG_PASSWORD"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --config) config_file="$2"; shift 2 ;;
        --script-conf) script_conf="$2"; shift 2 ;;
        --password-env) password_env="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
      esac
    done

    if [[ -z "$config_file" ]]; then
      echo "--config is required" >&2
      exit 1
    fi

    password_value="${!password_env:-}"
    if [[ -z "$password_value" ]]; then
      echo "missing password env var: $password_env" >&2
      exit 1
    fi

    if [[ ! -f "$HUMMINGBOT_HOME/conf/$config_file" ]]; then
      echo "config not found: $HUMMINGBOT_HOME/conf/$config_file" >&2
      exit 1
    fi

    run_id="hb-$(date +%s)"
    out_log="$HUMMINGBOT_LOG_DIR/run-${run_id}.log"
    cmd=("$HUMMINGBOT_CONDA_EXE" run -n "$HUMMINGBOT_ENV_NAME" python bin/hummingbot_quickstart.py --headless true --config-password "$password_value" --config-file-name "$config_file")
    if [[ -n "$script_conf" ]]; then
      cmd+=(--script-conf "$script_conf")
    fi

    (
      cd "$HUMMINGBOT_HOME"
      "${cmd[@]}"
    ) >"$out_log" 2>&1

    jq -n --arg status "completed" --arg runId "$run_id" --arg log "$out_log" '{status:$status,runId:$runId,log:$log}'
    ;;

  -h|--help|"")
    usage
    ;;

  *)
    echo "unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
