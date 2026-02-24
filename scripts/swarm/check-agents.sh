#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY_PATH="${1:-$ROOT_DIR/.openclaw-swarm/active-tasks.json}"
SWARM_DIR="$ROOT_DIR/scripts/swarm"
REVIEW_SCRIPT="$SWARM_DIR/review-pr.sh"
NOTIFY_SCRIPT="$SWARM_DIR/notify-telegram.sh"
EVOLUTION_SCRIPT="$SWARM_DIR/evolution-archive.sh"
CONTEXT_ENGINEERING_SCRIPT="$SWARM_DIR/context-engineering.sh"
SPAWN_WORKER_SCRIPT="$SWARM_DIR/spawn-worker.sh"
RESOURCE_GUARD_SCRIPT="$SWARM_DIR/resource-guard.sh"
if [[ -x "$ROOT_DIR/dist/entry.js" ]]; then
  OPENCLAW_CLI_CMD="${OPENCLAW_CLI_CMD:-node $ROOT_DIR/dist/entry.js}"
else
  OPENCLAW_CLI_CMD="${OPENCLAW_CLI_CMD:-pnpm -s openclaw}"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

if [[ ! -f "$REGISTRY_PATH" ]]; then
  jq -n --arg now "$(date -Is)" '{updatedAt:$now,tasks:[]}'
  exit 0
fi

tmp="$(mktemp)"
cp "$REGISTRY_PATH" "$tmp"

now_iso="$(date -Is)"

ci_rollup_for_pr() {
  local pr_number="$1"
  if ! command -v gh >/dev/null 2>&1; then
    echo "unknown"
    return 0
  fi
  local view_json
  view_json="$(gh pr view "$pr_number" --json statusCheckRollup 2>/dev/null || echo '{}')"
  local count
  count="$(jq -r '(.statusCheckRollup // []) | length' <<<"$view_json" 2>/dev/null || echo "0")"
  if [[ "$count" == "0" ]]; then
    echo "unknown"
    return 0
  fi
  local has_fail
  has_fail="$(jq -r '
    (.statusCheckRollup // []) | any(
      (
        .conclusion // .state // .status // ""
      ) as $s
      | ($s | tostring | ascii_upcase) as $u
      | ($u == "FAILURE" or $u == "FAILED" or $u == "ERROR" or $u == "CANCELLED" or $u == "TIMED_OUT")
    )
  ' <<<"$view_json" 2>/dev/null || echo "false")"
  if [[ "$has_fail" == "true" ]]; then
    echo "failed"
    return 0
  fi
  local has_pending
  has_pending="$(jq -r '
    (.statusCheckRollup // []) | any(
      (
        .conclusion // .state // .status // ""
      ) as $s
      | ($s | tostring | ascii_upcase) as $u
      | ($u == "" or $u == "PENDING" or $u == "IN_PROGRESS" or $u == "QUEUED" or $u == "EXPECTED" or $u == "ACTION_REQUIRED")
    )
  ' <<<"$view_json" 2>/dev/null || echo "false")"
  if [[ "$has_pending" == "true" ]]; then
    echo "pending"
    return 0
  fi
  echo "passed"
}

as_json_bool_or_null() {
  local raw="$1"
  case "$raw" in
    true|false|null) echo "$raw" ;;
    *) echo "null" ;;
  esac
}

agent_wait_status() {
  local run_id="$1"
  if [[ -z "$run_id" ]]; then
    echo ""
    return 0
  fi
  if [[ -z "$OPENCLAW_CLI_CMD" ]]; then
    echo ""
    return 0
  fi
  local wait_json_raw wait_json
  wait_json_raw="$($OPENCLAW_CLI_CMD gateway call agent.wait --json --params "{\"runId\":\"$run_id\",\"timeoutMs\":10}" --timeout 5000 2>/dev/null || echo '{}')"
  wait_json="$(sed -n '/^[[:space:]]*{/,$p' <<<"$wait_json_raw")"
  jq -r '.status // empty' <<<"$wait_json" 2>/dev/null || echo ""
}

# Normalize legacy registry schemas to {updatedAt,tasks}.
jq --arg now "$now_iso" '
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
' "$tmp" >"$tmp.next"
mv "$tmp.next" "$tmp"

tasks_len="$(jq '.tasks | length' "$tmp")"

for ((i=0; i<tasks_len; i++)); do
  status="$(jq -r ".tasks[$i].status // \"running\"" "$tmp")"
  if [[ "$status" == "done" || "$status" == "failed" ]]; then
    continue
  fi

  tmux_session="$(jq -r ".tasks[$i].tmuxSession // empty" "$tmp")"
  branch="$(jq -r ".tasks[$i].branch // empty" "$tmp")"

  tmux_alive="unknown"
  if [[ -n "$tmux_session" ]]; then
    if tmux has-session -t "$tmux_session" >/dev/null 2>&1; then
      tmux_alive="alive"
    else
      tmux_alive="dead"
    fi
  fi

  pr_number=""
  pr_state=""
  pr_url=""
  ci_state="unknown"
  codex_review="$(jq -r ".tasks[$i].checks.codexReviewPassed // \"null\"" "$tmp")"
  openrouter_review="$(jq -r ".tasks[$i].checks.openrouterReviewPassed // \"null\"" "$tmp")"
  notified_at="$(jq -r ".tasks[$i].notifiedAt // empty" "$tmp")"
  notify_on_complete="$(jq -r ".tasks[$i].notifyOnComplete // true" "$tmp")"
  task_id="$(jq -r ".tasks[$i].id // \"\"" "$tmp")"
  task_description="$(jq -r ".tasks[$i].description // \"\"" "$tmp")"
  if [[ -n "$branch" ]] && command -v gh >/dev/null 2>&1; then
    pr_json="$(gh pr list --head "$branch" --state all --limit 1 --json number,state,url 2>/dev/null || echo '[]')"
    pr_number="$(jq -r '.[0].number // empty' <<<"$pr_json")"
    pr_state="$(jq -r '.[0].state // empty' <<<"$pr_json")"
    pr_url="$(jq -r '.[0].url // empty' <<<"$pr_json")"
    if [[ -n "$pr_number" ]]; then
      ci_state="$(ci_rollup_for_pr "$pr_number")"
    fi
  fi

  attempts="$(jq -r ".tasks[$i].attempts // 0" "$tmp")"
  max_attempts="$(jq -r ".tasks[$i].maxAttempts // 3" "$tmp")"
  next_status="$status"
  next_action="$(jq -r ".tasks[$i].nextAction // empty" "$tmp")"
  last_error="$(jq -r ".tasks[$i].lastError // empty" "$tmp")"
  run_id="$(jq -r ".tasks[$i].runId // empty" "$tmp")"
  session_key="$(jq -r ".tasks[$i].sessionKey // empty" "$tmp")"

  worker_run_state=""
  if [[ -n "$run_id" ]]; then
    worker_run_state="$(agent_wait_status "$run_id")"
    if [[ "$worker_run_state" == "ok" ]]; then
      if [[ -z "$pr_number" || "$pr_state" == "MERGED" ]]; then
        next_status="done"
        next_action="Worker run completed successfully."
      fi
      last_error=""
    elif [[ "$worker_run_state" == "error" ]]; then
      attempts=$((attempts + 1))
      last_error="Worker run failed (runId=$run_id)."
      if [[ "$attempts" -ge "$max_attempts" ]]; then
        next_status="needs_attention"
        next_action="Max retry attempts reached ($attempts/$max_attempts)."
      else
        next_status="running"
        next_action="Auto-respawning worker ($attempts/$max_attempts)."
      fi
    fi
  fi

  review_note=""
  if [[ -n "$pr_number" && "$pr_state" != "MERGED" && "$ci_state" == "passed" ]]; then
    if [[ "$codex_review" == "null" || "$openrouter_review" == "null" ]]; then
      if [[ -x "$REVIEW_SCRIPT" ]]; then
        review_json="$("$REVIEW_SCRIPT" --pr "$pr_number" --branch "$branch" --task-id "$task_id" 2>/dev/null || echo '{}')"
        codex_review="$(jq -r '.codexReviewPassed // "null"' <<<"$review_json" 2>/dev/null || echo "null")"
        openrouter_review="$(jq -r '.openrouterReviewPassed // "null"' <<<"$review_json" 2>/dev/null || echo "null")"
        review_note="$(jq -r '.summary // empty' <<<"$review_json" 2>/dev/null || echo "")"
      fi
    fi
    if [[ "$codex_review" == "false" || "$openrouter_review" == "false" ]]; then
      next_status="needs_attention"
      last_error="AI review failed for PR #$pr_number"
      if [[ -n "$review_note" ]]; then
        next_action="Apply reviewer fixes: $review_note"
      else
        next_action="Apply reviewer fixes and re-run checks."
      fi
    fi
  fi

  if [[ -n "$pr_number" && "$pr_state" != "MERGED" && "$ci_state" == "failed" ]]; then
    attempts=$((attempts + 1))
    last_error="CI checks failed for PR #$pr_number"
    if [[ "$attempts" -ge "$max_attempts" ]]; then
      next_status="needs_attention"
      next_action="Max retry attempts reached ($attempts/$max_attempts). Build retry prompt: bash $CONTEXT_ENGINEERING_SCRIPT --task \"Fix failing CI for PR #$pr_number\" --branch \"$branch\""
    else
      next_status="running"
      next_action="Retry worker with focused prompt and address failing checks ($attempts/$max_attempts)."
    fi
  fi

  if [[ "$tmux_alive" == "dead" && -z "$pr_number" ]]; then
    next_status="needs_attention"
    last_error="Worker session ended before PR creation."
    next_action="Respawn worker using context prompt: bash $CONTEXT_ENGINEERING_SCRIPT --task \"$task_description\" --branch \"$branch\""
  elif [[ "$pr_state" == "MERGED" ]]; then
    next_status="done"
    next_action="Merged. No further action."
    last_error=""
  fi

  if [[ "$next_status" == "running" && "$next_action" == Auto-respawning* ]]; then
    if [[ -x "$SPAWN_WORKER_SCRIPT" ]]; then
      if "$SPAWN_WORKER_SCRIPT" \
        --task-id "$task_id" \
        --task "$task_description" \
        --branch "${branch:-main}" \
        --session-key "${session_key:-agent:nova:main}" \
        --registry-path "$tmp" >/dev/null 2>&1; then
        next_action="Worker auto-respawned."
        last_error=""
      else
        next_status="needs_attention"
        next_action="Auto-respawn failed; verify gateway auth and rerun spawn-worker.sh."
      fi
    fi
  fi

  notified_now=""
  if [[ "$next_status" == "done" && "$notify_on_complete" == "true" && -z "$notified_at" ]]; then
    if [[ -x "$NOTIFY_SCRIPT" ]]; then
      notify_message="✅ Swarm task finished: $task_description"$'\n'
      notify_message+="Task: $task_id"$'\n'
      if [[ -n "$pr_number" ]]; then
        notify_message+="PR #$pr_number ($pr_state)"$'\n'
      fi
      if [[ -n "$pr_url" ]]; then
        notify_message+="$pr_url"$'\n'
      fi
      notify_message+="Checks: ciPassed=$( [[ "$ci_state" == "passed" ]] && echo true || echo false ), codexReviewPassed=$codex_review, openrouterReviewPassed=$openrouter_review"
      if "$NOTIFY_SCRIPT" --message "$notify_message" >/dev/null 2>&1; then
        notified_now="$now_iso"
      fi
    fi
  fi

  jq \
    --argjson idx "$i" \
    --arg tmuxAlive "$tmux_alive" \
    --arg prNumber "$pr_number" \
    --arg prState "$pr_state" \
    --arg prUrl "$pr_url" \
    --arg ciState "$ci_state" \
    --argjson codexReview "$(as_json_bool_or_null "$codex_review")" \
    --argjson openrouterReview "$(as_json_bool_or_null "$openrouter_review")" \
    --argjson attempts "$attempts" \
    --arg runId "$run_id" \
    --arg sessionKey "$session_key" \
    --arg nextStatus "$next_status" \
    --arg nextAction "$next_action" \
    --arg lastError "$last_error" \
    --arg notifiedNow "$notified_now" \
    --arg now "$now_iso" \
    '
      .tasks[$idx].heartbeatAt = $now
      | .tasks[$idx].tmuxAlive = $tmuxAlive
      | .tasks[$idx].pr.number = (if $prNumber == "" then null else ($prNumber|tonumber) end)
      | .tasks[$idx].pr.state = (if $prState == "" then null else $prState end)
      | .tasks[$idx].pr.url = (if $prUrl == "" then null else $prUrl end)
      | .tasks[$idx].checks.prCreated = ($prNumber != "")
      | .tasks[$idx].checks.ciPassed = ($ciState == "passed")
      | .tasks[$idx].checks.codexReviewPassed = $codexReview
      | .tasks[$idx].checks.openrouterReviewPassed = $openrouterReview
      | .tasks[$idx].attempts = $attempts
      | .tasks[$idx].runId = (if $runId == "" then .tasks[$idx].runId else $runId end)
      | .tasks[$idx].sessionKey = (if $sessionKey == "" then .tasks[$idx].sessionKey else $sessionKey end)
      | .tasks[$idx].lastError = (if $lastError == "" then null else $lastError end)
      | .tasks[$idx].nextAction = (if $nextAction == "" then .tasks[$idx].nextAction else $nextAction end)
      | .tasks[$idx].completedAt = (if $nextStatus == "done" then (.tasks[$idx].completedAt // $now) else .tasks[$idx].completedAt end)
      | .tasks[$idx].notifiedAt = (if $notifiedNow == "" then .tasks[$idx].notifiedAt else $notifiedNow end)
      | .tasks[$idx].status = $nextStatus
    ' "$tmp" >"$tmp.next"
  mv "$tmp.next" "$tmp"
done

# Notify for tasks that are already marked done but have not been notified yet.
for ((i=0; i<tasks_len; i++)); do
  status="$(jq -r ".tasks[$i].status // \"running\"" "$tmp")"
  [[ "$status" == "done" ]] || continue
  notify_on_complete="$(jq -r ".tasks[$i].notifyOnComplete // true" "$tmp")"
  [[ "$notify_on_complete" == "true" ]] || continue
  notified_at="$(jq -r ".tasks[$i].notifiedAt // empty" "$tmp")"
  [[ -z "$notified_at" ]] || continue
  [[ -x "$NOTIFY_SCRIPT" ]] || continue

  task_id="$(jq -r ".tasks[$i].id // \"\"" "$tmp")"
  task_description="$(jq -r ".tasks[$i].description // \"\"" "$tmp")"
  pr_number="$(jq -r ".tasks[$i].pr.number // empty" "$tmp")"
  pr_state="$(jq -r ".tasks[$i].pr.state // empty" "$tmp")"
  pr_url="$(jq -r ".tasks[$i].pr.url // empty" "$tmp")"
  ci_passed="$(jq -r ".tasks[$i].checks.ciPassed // false" "$tmp")"
  codex_review="$(jq -r ".tasks[$i].checks.codexReviewPassed // \"null\"" "$tmp")"
  openrouter_review="$(jq -r ".tasks[$i].checks.openrouterReviewPassed // \"null\"" "$tmp")"

  notify_message="✅ Swarm task finished: $task_description"$'\n'
  notify_message+="Task: $task_id"$'\n'
  if [[ -n "$pr_number" ]]; then
    notify_message+="PR #$pr_number ($pr_state)"$'\n'
  fi
  if [[ -n "$pr_url" ]]; then
    notify_message+="$pr_url"$'\n'
  fi
  notify_message+="Checks: ciPassed=$ci_passed, codexReviewPassed=$codex_review, openrouterReviewPassed=$openrouter_review"

  if "$NOTIFY_SCRIPT" --message "$notify_message" >/dev/null 2>&1; then
    jq --argjson idx "$i" --arg now "$now_iso" '.tasks[$idx].notifiedAt = $now' "$tmp" >"$tmp.next"
    mv "$tmp.next" "$tmp"
  fi
done

jq --arg now "$now_iso" '.updatedAt = $now' "$tmp" >"$tmp.next"
mv "$tmp.next" "$tmp"
cat "$tmp" >"$REGISTRY_PATH"
if [[ -x "$EVOLUTION_SCRIPT" ]]; then
  "$EVOLUTION_SCRIPT" "$REGISTRY_PATH" >/dev/null 2>&1 || true
fi
if [[ -x "$RESOURCE_GUARD_SCRIPT" ]]; then
  "$RESOURCE_GUARD_SCRIPT" >/dev/null 2>&1 || true
fi
cat "$REGISTRY_PATH"
rm -f "$tmp"
