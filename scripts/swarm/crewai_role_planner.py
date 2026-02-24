#!/usr/bin/env python3
"""CrewAI-backed role planner for swarm orchestration.

This script uses CrewAI classes to build a hierarchical manager/worker structure
and emits a deterministic JSON role plan for shell scripts.
"""

from __future__ import annotations

import argparse
import json
from typing import Any


def infer_domain(task: str) -> str:
    t = task.lower()
    if any(k in t for k in ("ui", "frontend", "css", "design", "component", "layout", "playwright")):
        return "frontend"
    if any(k in t for k in ("api", "backend", "database", "migration", "service", "worker", "queue", "refactor")):
        return "backend"
    if any(k in t for k in ("test", "flaky", "vitest", "unit", "e2e", "ci", "lint", "typecheck")):
        return "qa"
    if any(k in t for k in ("docs", "readme", "guide", "changelog", "document")):
        return "docs"
    return "general"


def resolve_worker_specs(domain: str) -> list[dict[str, Any]]:
    if domain == "frontend":
        return [
            {
                "id": "frontend_specialist",
                "role": "Frontend Specialist",
                "goal": "Implement UI changes cleanly and safely",
                "backstory": "Senior frontend engineer focused on robust UI behavior and maintainable components.",
            },
            {
                "id": "qa_specialist",
                "role": "QA Specialist",
                "goal": "Validate UI behavior, regressions, and flaky paths",
                "backstory": "Reliability-focused engineer specializing in deterministic test stabilization.",
            },
        ]
    if domain == "backend":
        return [
            {
                "id": "backend_specialist",
                "role": "Backend Specialist",
                "goal": "Implement backend logic with clear invariants and error handling",
                "backstory": "Backend engineer focused on correctness, performance, and API reliability.",
            },
            {
                "id": "qa_specialist",
                "role": "QA Specialist",
                "goal": "Validate edge cases, failure modes, and contract correctness",
                "backstory": "Test engineer focused on critical-path and regression validation.",
            },
        ]
    if domain == "qa":
        return [
            {
                "id": "qa_specialist",
                "role": "QA Specialist",
                "goal": "Identify failure source and define reproducible checks",
                "backstory": "Quality engineer focused on deterministic reproduction and verification.",
            },
            {
                "id": "fix_specialist",
                "role": "Fix Specialist",
                "goal": "Apply minimal scoped fixes to stabilize tests/checks",
                "backstory": "Engineer focused on quick, low-risk stabilization patches.",
            },
        ]
    if domain == "docs":
        return [
            {
                "id": "docs_specialist",
                "role": "Documentation Specialist",
                "goal": "Update docs for clarity and correctness",
                "backstory": "Technical writer-engineer focused on accurate, actionable docs.",
            },
            {
                "id": "review_specialist",
                "role": "Review Specialist",
                "goal": "Check completeness and consistency against implementation",
                "backstory": "Reviewer ensuring docs and code behavior stay aligned.",
            },
        ]
    return [
        {
            "id": "implementation_specialist",
            "role": "Implementation Specialist",
            "goal": "Deliver the smallest complete increment",
            "backstory": "Generalist engineer skilled at scoped implementation.",
        },
        {
            "id": "verification_specialist",
            "role": "Verification Specialist",
            "goal": "Validate outcomes and surface residual risk",
            "backstory": "Engineer focused on evidence-based validation.",
        },
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="CrewAI role planner")
    parser.add_argument("--task", required=True)
    parser.add_argument("--branch", default="main")
    args = parser.parse_args()

    domain = infer_domain(args.task)
    workers = resolve_worker_specs(domain)

    # Import CrewAI lazily so script can fail cleanly when missing.
    try:
        from crewai import Agent, Process  # type: ignore
    except Exception as exc:
        raise RuntimeError("crewai package not installed in swarm venv") from exc

    manager = Agent(
        role="Orchestrator Manager",
        goal="Delegate to specialists, validate outputs, and drive work to done state.",
        backstory="Experienced technical manager coordinating specialists under strict quality gates.",
        allow_delegation=True,
        verbose=False,
    )

    worker_agents = [
        Agent(
            role=spec["role"],
            goal=spec["goal"],
            backstory=spec["backstory"],
            allow_delegation=False,
            verbose=False,
        )
        for spec in workers
    ]

    output = {
        "process": Process.hierarchical.value if hasattr(Process.hierarchical, "value") else "hierarchical",
        "manager": {
            "id": "nova_manager",
            "role": manager.role,
            "goal": manager.goal,
            "backstory": manager.backstory,
            "allowDelegation": True,
        },
        "workers": [
            {
                "id": workers[idx]["id"],
                "role": agent.role,
                "goal": agent.goal,
                "allowDelegation": False,
            }
            for idx, agent in enumerate(worker_agents)
        ],
        "delegationRules": [
            "Manager delegates tasks based on specialization",
            "Workers do not delegate; they execute focused scoped tasks",
            "Manager is not included in worker execution pool",
            "Manager validates outputs before progressing",
        ],
        "taskPacket": {
            "description": args.task,
            "branch": args.branch,
            "domain": domain,
            "expectedOutput": "Merged code or explicit blocker with next action",
            "qualityGates": [
                "Changed-scope validation passes",
                "Reviewer checks (codex/openrouter) pass or blocker recorded",
                "Task registry reflects latest state",
            ],
        },
    }
    print(json.dumps(output, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

