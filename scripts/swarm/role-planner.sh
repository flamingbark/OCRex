#!/usr/bin/env bash
set -euo pipefail

TASK=""
BRANCH="main"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CREWAI_PLANNER="$ROOT_DIR/scripts/swarm/crewai_role_planner.py"
SWARM_PYTHON="${SWARM_MEMORY_PYTHON:-$ROOT_DIR/.venv/swarm/bin/python3}"
ROLE_BACKEND="${SWARM_ROLE_PLANNER_BACKEND:-crewai}"

usage() {
  cat <<'EOF'
Usage:
  role-planner.sh --task <description> [--branch <branch>]

Outputs CrewAI-inspired hierarchical role plan JSON:
- manager role/goal/backstory (delegation enabled)
- worker roles (delegation disabled)
- process contract and quality gates
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$TASK" ]]; then
  usage
  exit 1
fi

if [[ "$ROLE_BACKEND" == "crewai" ]]; then
  if [[ -x "$SWARM_PYTHON" && -f "$CREWAI_PLANNER" ]]; then
    if "$SWARM_PYTHON" "$CREWAI_PLANNER" --task "$TASK" --branch "$BRANCH" 2>/dev/null; then
      exit 0
    fi
  fi
fi

task_lc="$(echo "$TASK" | tr '[:upper:]' '[:lower:]')"

domain="general"
if [[ "$task_lc" =~ (ui|frontend|css|design|component|layout|playwright) ]]; then
  domain="frontend"
elif [[ "$task_lc" =~ (api|backend|database|migration|refactor|service|worker|queue) ]]; then
  domain="backend"
elif [[ "$task_lc" =~ (test|flaky|vitest|unit|e2e|ci|lint|typecheck) ]]; then
  domain="qa"
elif [[ "$task_lc" =~ (docs|readme|guide|changelog|document) ]]; then
  domain="docs"
fi

workers_json="$(
  jq -cn --arg domain "$domain" '
    if $domain == "frontend" then
      [
        {id:"frontend_specialist",role:"Frontend Specialist",goal:"Implement UI changes cleanly",allowDelegation:false},
        {id:"qa_specialist",role:"QA Specialist",goal:"Validate UI behavior and regressions",allowDelegation:false}
      ]
    elif $domain == "backend" then
      [
        {id:"backend_specialist",role:"Backend Specialist",goal:"Implement core logic safely",allowDelegation:false},
        {id:"qa_specialist",role:"QA Specialist",goal:"Validate correctness and edge cases",allowDelegation:false}
      ]
    elif $domain == "qa" then
      [
        {id:"qa_specialist",role:"QA Specialist",goal:"Find and stabilize failing behavior",allowDelegation:false},
        {id:"fix_specialist",role:"Fix Specialist",goal:"Apply minimal targeted fixes",allowDelegation:false}
      ]
    elif $domain == "docs" then
      [
        {id:"docs_specialist",role:"Documentation Specialist",goal:"Update docs with accuracy and clarity",allowDelegation:false},
        {id:"review_specialist",role:"Review Specialist",goal:"Check consistency and completeness",allowDelegation:false}
      ]
    else
      [
        {id:"implementation_specialist",role:"Implementation Specialist",goal:"Ship scoped changes",allowDelegation:false},
        {id:"verification_specialist",role:"Verification Specialist",goal:"Confirm behavior and risks",allowDelegation:false}
      ]
    end
  '
)"

jq -n \
  --arg task "$TASK" \
  --arg branch "$BRANCH" \
  --arg domain "$domain" \
  --argjson workers "$workers_json" '
{
  process: "hierarchical",
  manager: {
    id: "nova_manager",
    role: "Orchestrator Manager",
    goal: "Delegate to specialists, validate outputs, and drive to done",
    backstory: "Experienced technical manager coordinating specialized agents under strict quality gates.",
    allowDelegation: true
  },
  workers: $workers,
  delegationRules: [
    "Manager delegates tasks based on specialization",
    "Workers do not delegate; they execute focused scoped tasks",
    "Manager is not included in worker execution pool",
    "Manager validates outputs before progressing"
  ],
  taskPacket: {
    description: $task,
    branch: $branch,
    domain: $domain,
    expectedOutput: "Merged code or explicit blocker with next action",
    qualityGates: [
      "Changed-scope validation passes",
      "Reviewer checks (codex/openrouter) pass or blocker recorded",
      "Task registry reflects latest state"
    ]
  }
}'
