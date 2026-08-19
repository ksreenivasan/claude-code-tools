---
name: skill-evaluator
description: Empirically evaluate an agent skill's activation and task impact with paired baseline and treatment trials; use for skill testing, not ordinary code review.
---

# Skill Evaluator

Evaluate whether a skill improves realistic agent behavior, not merely whether its prose looks polished.

## Design the evaluation

Define the claim being tested and build a small held-out suite that was not used to write the skill:

- **Positive triggers:** requests where the skill should activate, including varied phrasing and realistic ambiguity.
- **Near misses:** similar requests where activation would be distracting or harmful.
- **Task cases:** representative easy, typical, and difficult work with observable success criteria.

Keep expected outcomes and grading rules outside the material shown to the agent. Avoid examples copied from the skill itself.

## Run paired trials

For each task, compare:

- **Baseline:** the same harness without the evaluated skill available.
- **Treatment:** the same harness with the skill available.

Hold the request, model, tools, repository state, permissions, and other settings constant. Use equivalent fresh contexts and avoid revealing prior results. Repeat trials when nondeterminism could change the conclusion; otherwise prefer breadth over unnecessary repetition.

## Grade

Use deterministic checks wherever the outcome can be inspected mechanically: tests, schema validation, exact invariants, file diffs, command results, or trigger decisions. Add a predefined qualitative rubric only for properties that require judgment, and review baseline and treatment outputs without favoring the treatment.

Assess separately:

- positive-trigger activation and instruction adherence;
- near-miss non-activation;
- task correctness and completeness;
- regressions, unnecessary constraints, or scope expansion;
- quality of artifacts and verification.

Capture latency, token or monetary cost, and trial variance when the harness exposes them cheaply. Do not block a useful evaluation because those measurements are unavailable.

## Conclude

Report per-case evidence, aggregate baseline-versus-treatment differences, activation errors, variance, and material costs. Distinguish demonstrated improvements from inconclusive or qualitative impressions. Recommend the smallest skill change supported by failures, then preserve the held-out cases for regression testing rather than rewriting them around the new wording.
