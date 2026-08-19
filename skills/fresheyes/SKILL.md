---
name: fresheyes
description: Request a clean-context independent review of a change, plan, or investigation when a genuine second opinion is wanted beyond ordinary self-review.
---

# Fresh Eyes

Use the current harness's native reviewer or isolated subagent capability to obtain an independent assessment with minimal anchoring.

## Prepare the review

Give the reviewer:

- the user's actual goal and relevant constraints;
- the exact review target, such as a diff, files, branch comparison, plan, or raw evidence;
- the required review focus and output format;
- only the context needed to understand the target.

Do not provide your conclusions, suspected defects, preferred solution, or a leading summary unless the reviewer must evaluate that specific claim. A clean context matters more than switching model brands.

Keep the review read-only by default. The reviewer may inspect files, history, tests, and diagnostics, but must not edit, commit, publish, or trigger external mutations. If no native isolated reviewer is available, disclose that limitation rather than simulating independence with a detached CLI process.

## Reconcile

Evaluate findings against the source material. Verify actionable claims directly where practical, reject unsupported or out-of-scope suggestions, and preserve disagreements when evidence remains ambiguous. The primary agent remains responsible for integration and the final recommendation.

Do not install hooks, launch pollers, force commits, or require Git-visible artifacts when the harness can pass the review material directly.
