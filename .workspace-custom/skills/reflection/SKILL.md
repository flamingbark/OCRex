---
name: Reflection
description: Structured self-evaluation before delivering work. Catches blind spots and improves quality through multi-lens critique.
version: 1.0.0
---

## When to Use

Before delivering important work, pause for structured self-evaluation. Catches blind spots, improves quality, builds trust.

Triggers:

- Complex deliverables (architecture, strategy, analysis)
- High-stakes outputs (production code, client-facing docs)
- Uncertainty about quality ("is this actually good?")
- After extended work sessions (tunnel vision risk)

## The Reflection Process

**1. Distance** — Step back mentally. Pretend you're reviewing someone else's work.

**2. Multi-lens evaluation:**

- **Correctness**: Does it actually solve the problem stated?
- **Completeness**: What's missing? Edge cases? Assumptions?
- **Clarity**: Would someone else understand this immediately?
- **Robustness**: What could go wrong? What breaks this?

**3. Steel-man critique** — Find the strongest objection to your work. Address it.

**4. Honest assessment** — Rate confidence 1-10. Below 7? State what would raise it.

## Reflection Depth

| Situation         | Depth                    |
| ----------------- | ------------------------ |
| Quick answer      | 10 seconds, one lens     |
| Standard task     | 30 seconds, all lenses   |
| Critical delivery | 2 minutes, full critique |

## Red Flags to Catch

- First solution accepted without alternatives considered
- Assumptions not validated with user
- Edge cases hand-waved
- Complexity added without clear benefit
- "It works" without understanding why

## Output Format

After reflection, either:

1. **Deliver with confidence** — reflection confirmed quality
2. **Improve then deliver** — found issues, fixed them
3. **Flag uncertainty** — "I'm 6/10 confident because X, want me to dig deeper?"

See `dimensions.md` for domain-specific evaluation criteria.
See `prompts.md` for self-reflection questions by task type.

---

_Related: diverge (multiple perspectives), brainstorm (idea generation)_
