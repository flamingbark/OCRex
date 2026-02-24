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
  register-task.sh add --id <id> --description <text> --branch <branch> [--tmux <session>] [--agent <agent>] [--repo <repo>] [--worktree <path>] [--notify-on-complete <true|false>] [--max-attempts <n>]
  register-task.sh done --id <id> [--note <text>]
  register-task.sh fail --id <id> [--note <text>]
  register-task.sh list

Legacy aliases (supported):
  register-task.sh --add ...
  register-task.sh --done ...
  register-task.sh --fail ...
  register-task.sh --list
EOF
}

ensure_registry() {
  mkdir -p "$(dirname "$REGISTRY_PATH")"
  local now
  now="$(date -Is)"

  if [[ ! -f "$REGISTRY_PATH" ]]; then
    jq -n --arg now "$now" '{updatedAt:$now,tasks:[]}' >"$REGISTRY_PATH"
    return
  fi

  # Normalize legacy schemas (e.g. {active,needs_attention,done}) to {updatedAt,tasks}.
  if ! jq -e . "$REGISTRY_PATH" >/dev/null 2>&1; then
    jq -n --arg now "$now" '{updatedAt:$now,tasks:[]}' >"$REGISTRY_PATH"
    return
  fi

  jq --arg now "$now" '
    if (.tasks | type) == "array" then
      .updatedAt = (.updatedAt // $now)
      | .tasks |= map(
          .id = (.id | tostring)
          | .description = (.description // .title // "task")
          | .branch = (.branch // "main")
          | .agent = (.agent // "codex")
          | .status = (.status // "running")
          | .startedAt = (.startedAt // $now)
          | .heartbeatAt = (.heartbeatAt // $now)
          | .repo = (.repo // null)
          | .worktree = (.worktree // null)
          | .completedAt = (.completedAt // null)
          | .runId = (.runId // null)
          | .sessionKey = (.sessionKey // null)
          | .notifyOnComplete = (.notifyOnComplete // true)
          | .attempts = (.attempts // 0)
          | .maxAttempts = (.maxAttempts // 3)
          | .checks = (
              if (.checks | type) == "object" then
                (.checks + {
                  prCreated: (.checks.prCreated // false),
                  ciPassed: (.checks.ciPassed // false),
                  codexReviewPassed: (.checks.codexReviewPassed // null),
                  openrouterReviewPassed: (.checks.openrouterReviewPassed // null),
                  claudeReviewPassed: (.checks.claudeReviewPassed // null),
                  geminiReviewPassed: (.checks.geminiReviewPassed // null)
                })
              else
                {
                  prCreated:false,
                  ciPassed:false,
                  codexReviewPassed:null,
                  openrouterReviewPassed:null,
                  claudeReviewPassed:null,
                  geminiReviewPassed:null
                }
              end
            )
          | .lastError = (.lastError // null)
          | .nextAction = (.nextAction // null)
          | .notifiedAt = (.notifiedAt // null)
          | .evolutionLoggedAt = (.evolutionLoggedAt // null)
          | .evolutionScore = (.evolutionScore // null)
          | .pr = (
              if (.pr | type) == "object" then
                (.pr + {number:(.pr.number // null),state:(.pr.state // null),url:(.pr.url // null)})
              else
                {number:null,state:null,url:null}
              end
            )
        )
    else
      {
        updatedAt: (.updatedAt // $now),
        tasks: (
          ((.tasks // []) + (.active // []))
          | map({
              id: ((.id // .taskId // "task") | tostring),
              description: (.description // .title // .summary // "task"),
              branch: (.branch // "main"),
              tmuxSession: (.tmuxSession // .tmux // null),
              repo: (.repo // null),
              worktree: (.worktree // null),
              agent: (.agent // "codex"),
              status: (.status // "running"),
              startedAt: (.startedAt // .updatedAt // $now),
              heartbeatAt: (.heartbeatAt // .updatedAt // $now),
              completedAt: (.completedAt // null),
              runId: (.runId // null),
              sessionKey: (.sessionKey // null),
              notifyOnComplete: (.notifyOnComplete // true),
              attempts: (.attempts // 0),
              maxAttempts: (.maxAttempts // 3),
              checks: (
                if (.checks | type) == "object" then
                  {
                    prCreated: (.checks.prCreated // false),
                    ciPassed: (.checks.ciPassed // false),
                    codexReviewPassed: (.checks.codexReviewPassed // null),
                    openrouterReviewPassed: (.checks.openrouterReviewPassed // null),
                    claudeReviewPassed: (.checks.claudeReviewPassed // null),
                    geminiReviewPassed: (.checks.geminiReviewPassed // null)
                  }
                else
                  {
                    prCreated:false,
                    ciPassed:false,
                    codexReviewPassed:null,
                    openrouterReviewPassed:null,
                    claudeReviewPassed:null,
                    geminiReviewPassed:null
                  }
                end
              ),
              lastError: (.lastError // null),
              nextAction: (.nextAction // null),
              notifiedAt: (.notifiedAt // null),
              evolutionLoggedAt: (.evolutionLoggedAt // null),
              evolutionScore: (.evolutionScore // null),
              pr: (
                if (.pr | type) == "object" then
                  {
                    number: (.pr.number // null),
                    state: (.pr.state // null),
                    url: (.pr.url // null)
                  }
                else
                  {
                    number: (.prNumber // null),
                    state: (.prState // null),
                    url: (.prUrl // null)
                  }
                end
              )
            })
        )
      }
    end
  ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
  mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
}

cmd="${1:-}"
shift || true

ensure_registry

case "$cmd" in
  --add) cmd="add" ;;
  --done) cmd="done" ;;
  --fail) cmd="fail" ;;
  --list) cmd="list" ;;
esac

case "$cmd" in
  add)
    id=""
    description=""
    branch=""
    tmux_session=""
    agent="codex"
    repo=""
    worktree=""
    notify_on_complete="true"
    max_attempts="3"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --id) id="$2"; shift 2 ;;
        --description) description="$2"; shift 2 ;;
        --task) description="$2"; shift 2 ;;
        --branch) branch="$2"; shift 2 ;;
        --tmux) tmux_session="$2"; shift 2 ;;
        --agent) agent="$2"; shift 2 ;;
        --repo) repo="$2"; shift 2 ;;
        --worktree) worktree="$2"; shift 2 ;;
        --notify-on-complete) notify_on_complete="$2"; shift 2 ;;
        --max-attempts) max_attempts="$2"; shift 2 ;;
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
      --arg repo "$repo" \
      --arg worktree "$worktree" \
      --arg notifyOnComplete "$notify_on_complete" \
      --argjson maxAttempts "$max_attempts" \
      --arg now "$now" \
      '
      .tasks |= ((. // []) | map(select((.id | tostring) != $id)))
      | .tasks += [{
          id:$id,
          description:$desc,
          branch:$branch,
          tmuxSession: (if $tmux == "" then null else $tmux end),
          repo: (if $repo == "" then null else $repo end),
          worktree: (if $worktree == "" then null else $worktree end),
          agent:$agent,
          status:"running",
          startedAt:$now,
          heartbeatAt:$now,
          completedAt:null,
          runId:null,
          sessionKey:null,
          notifyOnComplete: ($notifyOnComplete == "true"),
          attempts: 0,
          maxAttempts: (if $maxAttempts < 1 then 1 else $maxAttempts end),
          checks:{
            prCreated:false,
            ciPassed:false,
            codexReviewPassed:null,
            openrouterReviewPassed:null,
            claudeReviewPassed:null,
            geminiReviewPassed:null
          },
          lastError:null,
          nextAction:null,
          notifiedAt:null,
          evolutionLoggedAt:null,
          evolutionScore:null,
          pr:{number:null,state:null,url:null}
        }]
      | .updatedAt=$now
      ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
    mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
    jq --arg id "$id" '.tasks[] | select((.id | tostring) == $id)' "$REGISTRY_PATH"
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
      .tasks |= ((. // []) | map(
        if (.id | tostring) == $id then
          .status = $status
          | .completedAt = $now
          | .note = (if $note == "" then .note else $note end)
        else . end
      ))
      | .updatedAt = $now
      ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp"
    mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
    jq --arg id "$id" '.tasks[] | select((.id | tostring) == $id)' "$REGISTRY_PATH"
    ;;
  list)
    jq . "$REGISTRY_PATH"
    ;;
  *)
    usage
    exit 1
    ;;
esac
