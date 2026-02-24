#!/usr/bin/env bash
set -euo pipefail

PR_NUMBER=""
BRANCH=""
TASK_ID=""
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_CUSTOM_PATH="${ENV_CUSTOM_PATH:-$ROOT_DIR/.env.custom}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --task-id) TASK_ID="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PR_NUMBER" ]]; then
  jq -n '{codexReviewPassed:null,openrouterReviewPassed:null,summary:"missing-pr-number"}'
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  jq -n '{codexReviewPassed:null,openrouterReviewPassed:null,summary:"gh-not-installed"}'
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  jq -n '{codexReviewPassed:null,openrouterReviewPassed:null,summary:"curl-not-installed"}'
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

OR_KEY="${OPENROUTER_API_KEY:-}"
if [[ -z "$OR_KEY" && -f "$OPENCLAW_CONFIG_PATH" ]]; then
  OR_KEY="$(jq -r '.env.OPENROUTER_API_KEY // empty' "$OPENCLAW_CONFIG_PATH" 2>/dev/null || true)"
fi
if [[ -z "$OR_KEY" && -f "$ENV_CUSTOM_PATH" ]]; then
  OR_KEY="$(awk -F= '/^OPENROUTER_API_KEY=/{sub(/^OPENROUTER_API_KEY=/,""); print; exit}' "$ENV_CUSTOM_PATH")"
fi
if [[ -z "$OR_KEY" ]]; then
  jq -n '{codexReviewPassed:null,openrouterReviewPassed:null,summary:"openrouter-key-missing"}'
  exit 0
fi

strip_openrouter_prefix() {
  local model="$1"
  if [[ "$model" == openrouter/* ]]; then
    echo "${model#openrouter/}"
  else
    echo "$model"
  fi
}

PRIMARY_MODEL=""
FALLBACK_MODEL=""
if [[ -f "$OPENCLAW_CONFIG_PATH" ]]; then
  PRIMARY_MODEL="$(jq -r '.agents.defaults.model.primary // empty' "$OPENCLAW_CONFIG_PATH" 2>/dev/null || true)"
  FALLBACK_MODEL="$(jq -r '.agents.defaults.model.fallbacks[0] // empty' "$OPENCLAW_CONFIG_PATH" 2>/dev/null || true)"
fi

DEFAULT_OPENROUTER_MODEL="$(strip_openrouter_prefix "${PRIMARY_MODEL:-openrouter/openai/gpt-4o-mini}")"
DEFAULT_CODEX_MODEL_RAW="${FALLBACK_MODEL:-openai-codex/gpt-5.3-codex}"
DEFAULT_CODEX_MODEL="$(strip_openrouter_prefix "$DEFAULT_CODEX_MODEL_RAW")"

CODEX_MODEL="${SWARM_CODEX_REVIEW_MODEL:-$DEFAULT_CODEX_MODEL}"
OPENROUTER_MODEL="${SWARM_OPENROUTER_REVIEW_MODEL:-$DEFAULT_OPENROUTER_MODEL}"
API_URL="${OPENROUTER_API_URL:-https://openrouter.ai/api/v1/chat/completions}"

pr_meta="$(gh pr view "$PR_NUMBER" --json title,body,url 2>/dev/null || echo '{}')"
pr_title="$(jq -r '.title // ""' <<<"$pr_meta")"
pr_url="$(jq -r '.url // ""' <<<"$pr_meta")"
pr_body="$(jq -r '.body // ""' <<<"$pr_meta")"
pr_diff="$(gh pr diff "$PR_NUMBER" 2>/dev/null | head -c 18000 || true)"

build_prompt() {
  local reviewer_name="$1"
  cat <<EOF
You are a strict pull request reviewer ($reviewer_name).
Return only compact JSON with this shape:
{"pass":true|false,"summary":"short summary","criticalFindings":["..."]}

Rules:
- pass=true only if no critical correctness/security/reliability issues exist.
- Keep summary <= 180 chars.
- Keep up to 5 criticalFindings.

Task ID: $TASK_ID
Branch: $BRANCH
PR #$PR_NUMBER
Title: $pr_title
URL: $pr_url

PR Body:
$pr_body

Diff (truncated):
$pr_diff
EOF
}

run_review() {
  local model="$1"
  local reviewer_name="$2"
  local prompt
  prompt="$(build_prompt "$reviewer_name")"

  response="$(
    curl -sS "$API_URL" \
      -H "Authorization: Bearer $OR_KEY" \
      -H "Content-Type: application/json" \
      -d @- <<JSON || true
{
  "model": "$model",
  "temperature": 0,
  "messages": [
    {"role":"system","content":"You are a PR reviewer that outputs only JSON."},
    {"role":"user","content": $(jq -Rn --arg v "$prompt" '$v')}
  ]
}
JSON
  )"

  content="$(jq -r '.choices[0].message.content // ""' <<<"$response" 2>/dev/null || echo "")"
  if [[ -z "$content" ]]; then
    jq -n '{"pass":null,"summary":"empty-model-response","criticalFindings":[]}'
    return 0
  fi

  # Extract first JSON object if model wrapped output.
  parsed="$(sed -n '/{/,/}/p' <<<"$content" | tr -d '\r' | jq -c . 2>/dev/null || true)"
  if [[ -z "$parsed" ]]; then
    jq -n '{"pass":null,"summary":"unparseable-review","criticalFindings":[]}'
    return 0
  fi
  jq -c '{
    pass: (if (.pass|type)=="boolean" then .pass else null end),
    summary: (.summary // ""),
    criticalFindings: (if (.criticalFindings|type)=="array" then .criticalFindings else [] end)
  }' <<<"$parsed"
}

codex_review="$(run_review "$CODEX_MODEL" "codex")"
openrouter_review="$(run_review "$OPENROUTER_MODEL" "openrouter")"

codex_pass="$(jq -r '.pass' <<<"$codex_review")"
openrouter_pass="$(jq -r '.pass' <<<"$openrouter_review")"
codex_summary="$(jq -r '.summary // ""' <<<"$codex_review")"
openrouter_summary="$(jq -r '.summary // ""' <<<"$openrouter_review")"

jq -n \
  --argjson codex "$(jq -r '.pass' <<<"$codex_review")" \
  --argjson openrouter "$(jq -r '.pass' <<<"$openrouter_review")" \
  --arg codexSummary "$codex_summary" \
  --arg openrouterSummary "$openrouter_summary" \
  '{
    codexReviewPassed:$codex,
    openrouterReviewPassed:$openrouter,
    summary: ("codex: " + ($codexSummary|tostring) + " | openrouter: " + ($openrouterSummary|tostring))
  }'
