# Claude Code to Codex Feature Parity

| Claude Code feature | Codex equivalent | Status |
| --- | --- | --- |
| Global `CLAUDE.md` | Global `~/.codex/AGENTS.md` | Covered |
| Claude Nanny safety judgment | Sandbox, command rules, semantic risk policy, and automatic approval review | Covered |
| Nanny fast-path | Workspace sandbox with on-request approvals | Covered |
| Nanny GSD flag | User-invoked, task-scoped GSD instructions | Covered |
| DCG interception | Not used; contextual rules/review avoid an early hard-deny conflict | Deliberate difference |
| Config guard | Protected-path policy plus reviewer | Covered semantically |
| Nanny stop monitor | Optional native `Stop` hook with an ephemeral independent Codex evaluator | Available, not installed by default |
| Stop-monitor task awareness | Recent user messages, plan/goal updates, Git state, and proposed final response | Available with optional hook |
| Stop-monitor loop prevention | Native `stop_hook_active` plus child-process environment guard | Available with optional hook |
| Pyright LSP | Project Pyright or BasedPyright checks | Equivalent behavior |
| Fresh-eyes and simplifier passes | Focused review subagent or `codex review` | Covered |
| PR review toolkit | `codex review`, subagents, and GitHub integration | Covered |
| Commit commands | Native Git under the global Git policy | Covered |
| Ralph loop | Goals, plans, and persistence instructions | Rough equivalent |
| Tmux agent supervision | Shared `tmux-nanny` skill with control-plane-only delegation | Covered |
| Plugin and skill helpers | Native Codex plugin/skill creation | Covered |
| Moraine session search | Official Moraine Codex plugin and custom health-check skill | Covered |
| Moraine persistence | launchd-owned foreground services on macOS | Covered |
| Notifications | Desktop notifications or top-level `notify` command | Rough equivalent |
| Worktree-first branching | Codex worktrees plus Git instructions | Covered |
| Lessons and task tracking | Existing `tasks/lessons.md`, `tasks/todo.md`, and native plans/goals | Covered |

## Deliberate differences

### No DCG hook

DCG's `PreToolUse` decision is binary: allow or deny. It cannot defer a
questionable command to Codex's contextual automatic reviewer, so it can reject
a justified, recoverable action before the permission framework evaluates the
goal. The Codex setup uses rules to route risky command families to review and
keeps nuanced intent in `AGENTS.md`.

### Stop review is optional

The Stop hook is retained but not installed by default because it interferes
with the existing nanny setup and is largely unnecessary. If explicitly
installed, it invokes a small ephemeral Codex run with user configuration
ignored, a read-only sandbox, structured output, and an explicit recursion
guard.

### Moraine is host-owned

The Moraine CLI's default `up` command starts background processes but does not
install a login service. This setup uses launchd to own the three foreground
services. That avoids processes whose lifetime is accidentally coupled to a
single Codex execution sandbox.
