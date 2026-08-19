---
name: codebase-recon
description: Use Git history for read-only reconnaissance of an unfamiliar repository before planning changes, ownership-sensitive work, or risk-focused review.
license: MIT; see LICENSE.txt
---

# Codebase Recon

Build an evidence-backed map of a repository from read-only Git data before reading implementation details deeply.

## Scope and safety

- Treat an omitted or blank repository path as the current directory. Pass paths to `git -C` as quoted arguments; never splice an untrusted path into a shell command.
- Use only read-only Git operations such as `status`, `rev-parse`, `log`, `shortlog`, `show`, `diff`, `ls-files`, and `rev-list`.
- Do not fetch, checkout, switch, reset, clean, commit, create refs, or otherwise change the repository.
- Check whether the path is a Git worktree before analyzing it. If it is not, say so and stop the Git workflow.
- If `HEAD` has no commit, report that history-based analysis is unavailable. You may summarize tracked or present files only when useful, clearly separating that from historical evidence.
- Detect shallow history with `git rev-parse --is-shallow-repository`. Do not fetch automatically. State that time, ownership, and trend conclusions cover only the available history.

## Reconnaissance

Choose commands and time windows proportionate to the request. Establish:

1. Repository state, current branch or detached state, history depth, earliest available commit, and recent activity.
2. Change concentration by file or directory using commit counts and numstat churn. Separate generated, vendored, lock, and migration files when they would dominate the result.
3. Recurring change clusters: files that often change together and subsystems repeatedly touched by the same work.
4. Contributor concentration and recency by area.
5. Fix-associated hotspots by inspecting commits whose messages plausibly indicate fixes, regressions, or reverts.
6. Recent direction: active areas, dormant areas, and abrupt shifts in ownership or churn.

Cross-check suspicious results against representative commits before reporting them. Prefer a small number of findings tied to commands, counts, dates, and commit examples over broad rankings.

## Interpretation

Ownership, bus-factor, hotspot, and “bug magnet” findings are heuristics, not facts:

- Commit authorship does not prove current ownership or expertise.
- Churn can reflect healthy migration or generated output rather than risk.
- Fix-like commit messages are noisy and do not establish defect density.
- Available history may omit squashed, shallow, rewritten, or pre-migration work.

Label these conclusions explicitly as heuristics and state the evidence and important caveats.

## Output

Report:

- repository and history scope;
- high-signal hotspots and change clusters;
- heuristic ownership or continuity concerns;
- heuristic fix-associated hotspots;
- recent development direction;
- concrete implications for the requested work;
- limitations that materially affect confidence.
