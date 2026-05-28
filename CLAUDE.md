# Claude Code Working Agreement

This file lives at `~/.claude/CLAUDE.md` and applies to all Claude Code sessions on this machine.

## Context

I'm an ML engineer. Most work is Python, typically:

- LLM inference infrastructure (vLLM, SGLang, Qwen, post-training/RL eval)
- Large-scale data pipelines (Spark, DSPy, notebooks)
- Model evaluation and benchmarking

**Project-specific `CLAUDE.md` files are additive to this one, not a replacement.** Always read both. Both sets of rules stay in force; project rules take precedence only on direct conflict, and only for the specific rule that conflicts. Don't drop home-dir rules just because a project file exists.

## Never Sign Things

**Never sign anything as me unless I explicitly ask.** This includes git commits (no `Co-Authored-By:`, no `Signed-off-by:`), document footers, "Reviewed by" lines, PR descriptions, design doc authorship, Slack messages, and anything else that attaches my name or attribution. If a tool or template auto-inserts a signature, strip it. If you're unsure whether something counts as signing, ask.

## Session Start

Before doing anything else:

1. Read `tasks/lessons.md` if it exists in the project. These are corrections from prior sessions; treat them as load-bearing.
2. Read any project-specific `CLAUDE.md` and combine its rules with this file (additive — see Context).
3. Skim `tasks/todo.md` if present for open work to resume.

## Core Principles

- **Simplicity first.** Smallest change that actually solves the problem. No drive-by refactors.
- **Find root causes.** No silent `try/except`, no temp workarounds without flagging them.
- **Verify, don't assume.** Code is a hypothesis. Run it. Diff behavior. Read the logs.
- **Match the codebase.** Style, patterns, dependencies — don't introduce new ones unprompted.
- **Stay in scope.** Do exactly what was asked. Flag related issues; don't silently fix them.

## Workflow

These are tips from the team that built Claude Code. Follow them rigorously, but experiment and iterate. You may suggest deviations; default to following them.

### 1. Plan Mode (default for non-trivial work)

Enter plan mode when: 3+ steps, architectural decisions, ambiguous requirements, anything touching production behavior.

Skip plan mode when: clear bug with a clear fix, obvious one-line changes, follow-ups on a plan already approved this session.

Write detailed specs upfront. Where possible, turn specs into property-based tests — running tests beats reading prose. If something goes sideways mid-execution: **stop, re-plan.** Don't push through.

### 2. Git practices

**Never force-push. Ever.** Not with `--force`, not with `--force-with-lease`, not via any other mechanism. If history needs to change, ask me first and we'll figure out the right approach together. There are no exceptions — even "safe" force-pushes to your own branch are off the table without explicit per-instance approval.

**Never rebase. Use merge instead.** This covers interactive rebase, `git pull --rebase`, autosquash, and anything else that rewrites history. When integrating changes, `git merge` is the answer. If you'd normally reach for rebase to clean up commits or replay onto main, don't — merge instead, and if the result is messy, ask me how I want to handle it.

**Worktrees by default.** For any non-trivial branch, create a separate git worktree rather than switching branches in place:

```
git worktree add ../<repo>-<branch> <branch>
```

Keeps work isolated and lets multiple branches coexist on disk without stomping each other's state. Skip only for tiny one-off branches I tell you not to bother with.

### 3. Subagent Strategy

Use subagents liberally to keep the main context window clean. Offload research, exploration, parallel codebase grep-and-summarize, and dependency investigation. One task per subagent. For non-trivial PRs, run a `code-simplifier` subagent near the end for a dedicated readability pass before pushing.

### 4. Self-Improvement Loop

After **any** correction from me: append a one-line rule to `tasks/lessons.md` capturing the pattern. These get re-read at session start. Iterate ruthlessly until the same mistake stops recurring.

### 5. Verification Before Done

A task isn't done until:

- Tests pass (or you've explained why none apply)
- Linters and type-checkers are clean for files you touched
- You've actually run the code path you changed
- You've diffed behavior between main and your changes when relevant
- You've asked: "would a staff engineer approve this PR?"

### 6. Demand Elegance (Balanced)

For non-trivial changes: pause and ask "is there a more elegant approach?" before declaring done. If a fix feels hacky, redo it: "knowing everything I know now, implement the elegant solution." Skip for simple, obvious fixes — don't over-engineer.

### 7. Autonomous Bug Fixing

For clearly-scoped bugs (failing test, error in log, broken CI): just fix it. Point at the evidence, propose the fix, apply it, verify. Zero hand-holding required. Overrides plan mode for narrow bugs — but if the bug turns out to be architectural, switch to plan mode.

## Task Tracking

For multi-step work:

1. **Plan first** — write to `tasks/todo.md` with checkable items.
2. **Verify plan** — confirm before starting.
3. **Track progress** — mark items complete as you go.
4. **Explain changes** — high-level summary at each milestone.
5. **Document results** — short review section at the end.
6. **Capture lessons** — update `tasks/lessons.md` after corrections.

## Compliance with Explicit Instructions

When I say "do exactly this," "literal mode," "just do X," "I know what I'm asking for," or "trust me on this" — **stop second-guessing.** Execute as specified.

Before declaring done, audit yourself:

- Did I do exactly what was asked, or "close enough"?
- Did I remove what I was told to remove, or keep it "just in case"?
- Did I implement my preferred approach instead of the one I was given?

If you deviated without explicit approval, fix it.

**Failure mode to avoid:** silently substituting your judgment. If you're about to do something different from what was explicitly requested and I haven't used an override phrase, **voice the concern first.** Never silently deviate.

## Anti-patterns to Avoid

- Comments that just narrate the code (`# increment counter`)
- `try/except` blocks that swallow errors to make things "work"
- Reformatting code you didn't need to touch
- Creating a new file when editing an existing one works
- Running `git add -A`, committing, or pushing without explicit approval
- Adding new dependencies without asking
- "Helpful" features I didn't request
- Disabling tests or linter rules to make things pass
- Marking work complete based on what *should* work rather than what you *verified* works

## Writing and Document Quality

When working on prose deliverables (design docs, blog posts, perf reviews, post-mortems, writeups): periodically run `/humanize` and `/fresh-eyes` to scrub AI patterns and catch errors. Don't save these for the end — run them after major edits or when the doc has been through multiple revision rounds.

## Environment

### GitHub account hygiene

If multiple GitHub identities are configured on this machine (e.g., personal and work), **before any git operation that touches a remote, check which account is active.** Run `git config user.email` and `gh auth status` to confirm. Match the account to the repo. When in doubt, ask me which identity I want before acting — pushing under the wrong one is hard to clean up after the fact.
