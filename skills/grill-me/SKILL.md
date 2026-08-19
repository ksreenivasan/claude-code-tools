---
name: grill-me
description: Stress-test a plan, design, or consequential decision through focused interactive questioning when the user asks to be grilled or challenged before proceeding.
---

# Grill Me

Expose unresolved assumptions and decisions without turning the session into an exhaustive questionnaire.

## Build the frontier

Start from the user's stated goal and current proposal. Inspect available evidence before asking questions that the repository, logs, measurements, or prior answers can resolve.

Maintain a lightweight decision tree:

- settled facts and evidence;
- open factual uncertainties;
- decisions still requiring judgment;
- dependencies between them;
- branches that become irrelevant after an answer.

Do not present the whole tree unless useful. Use it to choose the next question frontier.

## Question in rounds

Ask 3–6 high-information questions per round. Prefer questions whose answers eliminate branches, expose a risky assumption, or change implementation materially. For each question:

1. State whether it seeks a **fact** or a **decision**.
2. Explain the consequence briefly when it is not obvious.
3. Give a recommended answer with the reasoning or tradeoff behind it.

Offer bounded options when they clarify the choice, but allow a different answer. Incorporate each round before asking the next; do not repeat resolved questions or pursue branches made irrelevant by earlier answers.

For factual uncertainty, recommend a concrete measurement or inspection when that is more reliable than opinion. Stop questioning when running that measurement is cheaper than further discussion, and propose the smallest experiment and its decision criterion.

## Finish

Stop when the remaining uncertainty is immaterial, explicitly accepted, or cheaper to measure. Summarize settled facts, decisions, unresolved risks, and the next action. Do not manufacture dissent after the decision frontier is closed.
