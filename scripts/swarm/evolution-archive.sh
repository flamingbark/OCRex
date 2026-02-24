#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY_PATH="${1:-$ROOT_DIR/.openclaw-swarm/active-tasks.json}"
EVOLUTION_DIR="${EVOLUTION_DIR:-$ROOT_DIR/.openclaw-swarm/evolution}"
ARCHIVE_PATH="$EVOLUTION_DIR/archive.jsonl"
TOP_PATH="$EVOLUTION_DIR/top-candidates.json"
MEMORY_STORE_SCRIPT="$ROOT_DIR/scripts/swarm/memory-store.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

mkdir -p "$EVOLUTION_DIR"
touch "$ARCHIVE_PATH"

if [[ ! -f "$REGISTRY_PATH" ]]; then
  jq -n '{updatedAt:null,archived:0,topCandidates:[]}'
  exit 0
fi

tmp="$(mktemp)"
cp "$REGISTRY_PATH" "$tmp"
now_iso="$(date -Is)"
archived_count=0

tasks_len="$(jq '.tasks | length' "$tmp" 2>/dev/null || echo "0")"
for ((i=0; i<tasks_len; i++)); do
  status="$(jq -r ".tasks[$i].status // \"running\"" "$tmp")"
  evolution_logged_at="$(jq -r ".tasks[$i].evolutionLoggedAt // empty" "$tmp")"
  [[ "$status" == "done" || "$status" == "failed" ]] || continue
  [[ -z "$evolution_logged_at" ]] || continue

  task_id="$(jq -r ".tasks[$i].id // \"\"" "$tmp")"
  description="$(jq -r ".tasks[$i].description // \"\"" "$tmp")"
  branch="$(jq -r ".tasks[$i].branch // \"\"" "$tmp")"
  attempts="$(jq -r ".tasks[$i].attempts // 0" "$tmp")"
  ci_passed="$(jq -r ".tasks[$i].checks.ciPassed // false" "$tmp")"
  codex_passed="$(jq -r ".tasks[$i].checks.codexReviewPassed // false" "$tmp")"
  openrouter_passed="$(jq -r ".tasks[$i].checks.openrouterReviewPassed // false" "$tmp")"
  merged="$(jq -r ".tasks[$i].pr.state // \"\"" "$tmp")"
  last_error="$(jq -r ".tasks[$i].lastError // empty" "$tmp")"
  next_action="$(jq -r ".tasks[$i].nextAction // empty" "$tmp")"

  score=0
  [[ "$status" == "done" ]] && score=$((score + 2))
  [[ "$ci_passed" == "true" ]] && score=$((score + 2))
  [[ "$codex_passed" == "true" ]] && score=$((score + 1))
  [[ "$openrouter_passed" == "true" ]] && score=$((score + 1))
  [[ "$merged" == "MERGED" ]] && score=$((score + 2))
  if [[ "$attempts" -gt 0 ]]; then
    score=$((score - attempts))
  fi

  jq -n \
    --arg ts "$now_iso" \
    --arg id "$task_id" \
    --arg status "$status" \
    --arg desc "$description" \
    --arg branch "$branch" \
    --argjson score "$score" \
    --argjson attempts "$attempts" \
    --arg ci "$ci_passed" \
    --arg codex "$codex_passed" \
    --arg openrouter "$openrouter_passed" \
    --arg merged "$merged" \
    --arg err "$last_error" \
    --arg next "$next_action" \
    '{
      ts:$ts,
      taskId:$id,
      status:$status,
      description:$desc,
      branch:$branch,
      score:$score,
      attempts:$attempts,
      signals:{
        ciPassed: ($ci=="true"),
        codexReviewPassed: ($codex=="true"),
        openrouterReviewPassed: ($openrouter=="true"),
        merged: ($merged=="MERGED")
      },
      failure: (if $err=="" then null else $err end),
      nextAction: (if $next=="" then null else $next end)
    }' >>"$ARCHIVE_PATH"

  # Push archived learning to Mem0 so orchestration can retrieve past high-signal outcomes.
  if [[ -x "$MEMORY_STORE_SCRIPT" ]]; then
    memory_text="task=$task_id status=$status score=$score attempts=$attempts branch=$branch ci=$ci_passed codex=$codex_passed openrouter=$openrouter_passed merged=$merged"
    memory_meta="$(jq -cn \
      --arg id "$task_id" \
      --arg status "$status" \
      --arg branch "$branch" \
      --argjson score "$score" \
      --argjson attempts "$attempts" \
      --arg ci "$ci_passed" \
      --arg codex "$codex_passed" \
      --arg openrouter "$openrouter_passed" \
      --arg merged "$merged" \
      '{
        source:"swarm-evolution",
        taskId:$id,
        status:$status,
        branch:$branch,
        score:$score,
        attempts:$attempts,
        signals:{
          ciPassed:($ci=="true"),
          codexReviewPassed:($codex=="true"),
          openrouterReviewPassed:($openrouter=="true"),
          merged:($merged=="MERGED")
        }
      }')"
    "$MEMORY_STORE_SCRIPT" add --text "$memory_text" --metadata-json "$memory_meta" >/dev/null 2>&1 || true
  fi

  jq --argjson idx "$i" --arg now "$now_iso" --argjson score "$score" \
    '
      .tasks[$idx].evolutionLoggedAt = $now
      | .tasks[$idx].evolutionScore = $score
    ' "$tmp" >"$tmp.next"
  mv "$tmp.next" "$tmp"
  archived_count=$((archived_count + 1))
done

# Keep a compact "best variants" view inspired by DGM selection pressure.
jq -s '
  map(select(.score != null))
  | sort_by(.score)
  | reverse
  | .[:20]
' "$ARCHIVE_PATH" >"$TOP_PATH" 2>/dev/null || echo "[]" >"$TOP_PATH"

cat "$tmp" >"$REGISTRY_PATH"
rm -f "$tmp"

jq -n --arg now "$now_iso" --argjson archived "$archived_count" --slurpfile top "$TOP_PATH" '
  {
    updatedAt:$now,
    archived:$archived,
    topCandidates: ($top[0] // [])
  }'
