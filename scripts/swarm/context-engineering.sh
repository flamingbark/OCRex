#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MEMORY_STORE_SCRIPT="$ROOT_DIR/scripts/swarm/memory-store.sh"
TOP_CANDIDATES_PATH="${TOP_CANDIDATES_PATH:-$ROOT_DIR/.openclaw-swarm/evolution/top-candidates.json}"
ROLE_PLANNER_SCRIPT="$ROOT_DIR/scripts/swarm/role-planner.sh"

TASK=""
BRANCH="main"
MEMORY_QUERY=""
FILES_CSV=""
LIMIT="5"

usage() {
  cat <<'EOF'
Usage:
  context-engineering.sh --task <description> [--branch <branch>] [--memory-query <query>] [--files <comma,separated,paths>] [--limit <n>]

Outputs a structured worker prompt with:
- Context budget
- Progressive disclosure instructions
- Retrieved long-term memory hints (Mem0)
- Top evolution candidates
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --memory-query) MEMORY_QUERY="$2"; shift 2 ;;
    --files) FILES_CSV="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$TASK" ]]; then
  usage
  exit 1
fi

if [[ -z "$MEMORY_QUERY" ]]; then
  MEMORY_QUERY="$TASK"
fi

selected_files=""
if [[ -n "$FILES_CSV" ]]; then
  IFS=',' read -r -a raw_files <<<"$FILES_CSV"
  for f in "${raw_files[@]}"; do
    trimmed="$(echo "$f" | xargs)"
    [[ -n "$trimmed" ]] || continue
    selected_files+="- $trimmed"$'\n'
  done
fi

memory_block="- (no mem0 context available)"
if [[ -x "$MEMORY_STORE_SCRIPT" ]]; then
  memory_json="$("$MEMORY_STORE_SCRIPT" search --query "$MEMORY_QUERY" --limit "$LIMIT" 2>/dev/null || echo '{}')"
  parsed="$(jq -r '
    if (.results | type) == "array" then
      .results
      | .[:5]
      | map("- " + ((.memory // .text // .content // .fact // tostring) | gsub("\\n"; " ")))
      | join("\n")
    elif (.items | type) == "array" then
      .items
      | .[:5]
      | map("- " + ((.memory // .text // .content // .fact // tostring) | gsub("\\n"; " ")))
      | join("\n")
    else
      ""
    end
  ' <<<"$memory_json" 2>/dev/null || true)"
  if [[ -n "$parsed" ]]; then
    memory_block="$parsed"
  fi
fi

evolution_block="- (no evolution candidates yet)"
if [[ -f "$TOP_CANDIDATES_PATH" ]]; then
  parsed_candidates="$(jq -r '
    (if type=="array" then . else [] end)
    | .[:5]
    | map("- score=" + ((.score // 0)|tostring) + " task=" + (.taskId // "unknown") + " desc=" + ((.description // "") | gsub("\\n"; " ")))
    | join("\n")
  ' "$TOP_CANDIDATES_PATH" 2>/dev/null || true)"
  if [[ -n "$parsed_candidates" ]]; then
    evolution_block="$parsed_candidates"
  fi
fi

crew_block="- (role planner unavailable)"
if [[ -x "$ROLE_PLANNER_SCRIPT" ]]; then
  crew_json="$("$ROLE_PLANNER_SCRIPT" --task "$TASK" --branch "$BRANCH" 2>/dev/null || echo '{}')"
  crew_block="$(jq -r '
    [
      "Process: " + (.process // "hierarchical"),
      "Manager: " + (.manager.role // "Orchestrator Manager") + " (delegation=" + ((.manager.allowDelegation // true)|tostring) + ")",
      "Workers:",
      (
        (.workers // [])
        | map("  - " + (.id // "worker") + ": " + (.role // "Specialist") + " (delegation=" + ((.allowDelegation // false)|tostring) + ")")
        | join("\n")
      ),
      "Delegation rules:",
      (
        (.delegationRules // [])
        | map("  - " + .)
        | join("\n")
      )
    ] | join("\n")
  ' <<<"$crew_json" 2>/dev/null || echo "- (role planner parse failed)")"
fi

cat <<EOF
# Worker Prompt (Context-Engineered)

## Objective
$TASK

## Branch
$BRANCH

## Context Budget
- Budget intent: keep high-signal, low-noise context.
- Load only files required for the current subtask.
- Avoid full-file dumps when targeted reads are enough.

## Progressive Disclosure Rules
1. Start with only the objective + selected files.
2. Expand context only when blocked.
3. Summarize intermediate findings before loading more context.
4. Prefer deterministic tools and scoped validation.

## Selected Files
${selected_files:-"- (none provided; discover minimal file set first)"}

## Long-Term Memory (Mem0)
$memory_block

## Evolution Signals (Top Prior Outcomes)
$evolution_block

## Crew Hierarchy Plan
$crew_block

## Execution Contract
- Implement the smallest complete increment.
- Validate changed scope only.
- Report: what changed, evidence, risks, next action.
EOF
