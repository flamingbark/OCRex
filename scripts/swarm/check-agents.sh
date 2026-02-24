#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY_PATH="${1:-$ROOT_DIR/.openclaw-swarm/active-tasks.json}"

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
  if [[ -n "$branch" ]] && command -v gh >/dev/null 2>&1; then
    pr_json="$(gh pr list --head "$branch" --state all --limit 1 --json number,state 2>/dev/null || echo '[]')"
    pr_number="$(jq -r '.[0].number // empty' <<<"$pr_json")"
    pr_state="$(jq -r '.[0].state // empty' <<<"$pr_json")"
  fi

  next_status="$status"
  if [[ "$tmux_alive" == "dead" && -z "$pr_number" ]]; then
    next_status="needs_attention"
  elif [[ "$pr_state" == "MERGED" ]]; then
    next_status="done"
  fi

  jq \
    --argjson idx "$i" \
    --arg tmuxAlive "$tmux_alive" \
    --arg prNumber "$pr_number" \
    --arg prState "$pr_state" \
    --arg nextStatus "$next_status" \
    --arg now "$now_iso" \
    '
      .tasks[$idx].heartbeatAt = $now
      | .tasks[$idx].tmuxAlive = $tmuxAlive
      | .tasks[$idx].pr.number = (if $prNumber == "" then null else ($prNumber|tonumber) end)
      | .tasks[$idx].pr.state = (if $prState == "" then null else $prState end)
      | .tasks[$idx].status = $nextStatus
    ' "$tmp" >"$tmp.next"
  mv "$tmp.next" "$tmp"
done

jq --arg now "$now_iso" '.updatedAt = $now' "$tmp" >"$tmp.next"
mv "$tmp.next" "$tmp"
cat "$tmp"
rm -f "$tmp"
