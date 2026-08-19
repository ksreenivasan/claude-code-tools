# Codex Setup

This directory provides a low-friction permission model, an optional
completion reviewer, tmux-agent supervision, and persistent cross-session
search.

## What gets installed

| Component | Purpose |
| --- | --- |
| `~/.codex/config.toml` settings | Use workspace sandboxing, route necessary escalations to automatic review, and register Notion's hosted MCP endpoint |
| `~/.codex/AGENTS.md` | Define autonomy, risky-action review, verification, GSD mode, and Moraine memory behavior |
| `~/.codex/rules/default.rules` | Route recognizable destructive command families through the reviewer |
| `stop-nanny.py` | Optional completion reviewer; retained in the repository but not installed by default |
| `~/.codex/skills/<name>` | Install every repository-owned portable skill from [`../skills/`](../skills/) |
| Moraine plugin and Codex `moraine-history` adapter | Search older agent sessions through local MCP tools |
| Moraine launch agents | Keep ClickHouse, ingest, and the backend alive outside per-session sandboxes |

DCG is intentionally not installed. Its `PreToolUse` hook can only allow or
deny, so it can block an operation before Codex's contextual reviewer sees it.
The sandbox, command rules, separate reviewer, and semantic policy remain the
permission framework.

For the Claude-to-Codex mapping, see [`PARITY.md`](PARITY.md).

## Install

From the repository root:

```bash
codex/install.sh
```

The installer:

1. Preserves unrelated `config.toml` settings while merging the three
   permission keys and `[mcp_servers.notion]` with only
   `url = "https://mcp.notion.com/mcp"`.
2. Backs up and installs the global instructions and command rules.
3. Installs every canonical portable skill from [`../skills/`](../skills/), with recoverable backups outside skill discovery.
4. Leaves the optional Stop nanny uninstalled.
5. Installs Moraine's official Codex plugin and the `moraine-history` skill.
6. On macOS, installs three launchd services for persistent Moraine startup.
7. Runs deterministic rule, shared-skill wiring, Stop-behavior, and config checks.

Moraine's first setup downloads a local ClickHouse build of roughly 175 MiB.
Moraine binds its monitor to `127.0.0.1` and remains local unless its config is
changed to use a remote backend.

If you do not want to run the installer, manually merge the top-level settings
from [`config-snippet.toml`](config-snippet.toml) into `~/.codex/config.toml`.
Do not overwrite the rest of that file. When an installed instruction, rule, or
config path is a symlink with different content, the installer preserves the
link as a backup, leaves its external target unchanged, and installs a regular
file. A valid symlinked `config.toml` is materialized first so unrelated
settings are retained during the structured merge; a broken managed symlink is
backed up without dereferencing and replaced with a fresh managed file.

The Stop hook is intentionally not installed: it interferes with the existing
nanny setup and is largely unnecessary with that nanny in place. The standalone
`codex/install-stop-nanny.sh` installer remains available for explicit use;
individual non-managed hooks can then be disabled with `/hooks`.

## Notion MCP authentication

The installer registers Notion's official hosted Streamable HTTP endpoint but
does not authenticate. It stores no OAuth tokens, authorization headers, or
other credentials in `config.toml`. Authenticate interactively when ready:

```bash
codex mcp login notion
```

Complete the Notion workspace authorization in the browser, then restart the
Codex desktop app and start a new task so it loads the server and its tools.
Verify the connection with `codex mcp get notion`, `codex mcp list`, or `/mcp`.

Invoke the supervisor explicitly with `$tmux-nanny`. The nanny stays in the
control plane: it delegates substantive coding,
testing, documentation, research, repository maintenance, and Git work to pane
agents, then inspects their evidence. Before dispatch it records checkout and
file ownership; concurrent writers in one repository default to separate
worktrees, with shared checkouts limited to read-only or explicitly
non-overlapping work under a named integration owner.

## Permission flow

Routine workspace operations remain sandboxed. Recognizable risky command
families in [`default.rules`](default.rules) request review, and boundary
crossings use `approval_policy = "on-request"`. With
`approvals_reviewer = "auto_review"`, a separate reviewer handles those
requests before the user is interrupted.

When explicitly installed, the Stop nanny is separate from permission review.
On a `Stop` event it gives a small, ephemeral, read-only Codex run the recent user requests, plan/goal
updates, repository status, and the proposed final response. If work is clearly
unfinished, the hook returns a continuation prompt. Native
`stop_hook_active` state limits it to one nudge per stop cycle, preventing a
recursive loop. The evaluator child also ignores user config and sets an
environment guard so it cannot invoke the nanny recursively.

## Moraine lifecycle

Moraine's CLI does not install an OS login service. Starting it from an agent
shell can also tie its background children to that one execution session. On
macOS this setup instead runs its foreground services under launchd:

- `dev.moraine.clickhouse`
- `dev.moraine.ingest`
- `dev.moraine.backend`

Each starts at login and is restarted if it exits. The `moraine-history` skill
checks database connectivity plus the ingest and backend processes before its
first search in a task. If needed, it kicks the launch agents; when sandboxing
is active, the agent runs that health check with host-level escalation from the
start rather than calling `moraine up` in the sandbox.

With foreground launchd ownership, `moraine status` may label ClickHouse's
managed-pid field as stopped even while the endpoint is healthy. The health
script deliberately uses `doctor.clickhouse_healthy` plus the ingest/backend
states instead of that managed-pid field.

Use Moraine whenever the user refers to prior sessions, old decisions,
historical errors, branches, files, or other agents. The official plugin exposes
`search_sessions`, `list_sessions`, `file_attention`, and `open`.

## Verification

```bash
codex --strict-config --version
codex/test-rules.sh
codex/test-install.sh
setup/test-portable-skills.sh
setup/test-tmux-nanny.sh
codex/test-stop-nanny.sh
~/.codex/skills/moraine-history/scripts/health-check.sh
codex plugin list
```

Check that a risky command is routed without executing it:

```bash
codex execpolicy check --pretty \
  --rules "$HOME/.codex/rules/default.rules" \
  -- rm -rf build
```

The result should contain `"decision": "prompt"`.

After explicitly installing the Stop hook, an end-to-end test can use a
disposable thread with two concrete changes. Try to stop after only one; the independent reviewer should return one
continuation prompt. A second stop in the continued cycle must be allowed so a
bad evaluation cannot trap the turn.

## GSD mode

GSD mode is task-scoped and activates only when the user explicitly says
something like "GSD", "get shit done", "go ham", or "do not ask me for
permissions." It authorizes understood, task-necessary work without routine
questions. It does not authorize unrelated work, unbounded destruction, secret
exposure, or bypassing the sandbox and automatic reviewer.

## Maintaining the setup

- Keep [`AGENTS.md`](AGENTS.md), [`default.rules`](default.rules),
  [`stop-nanny.py`](stop-nanny.py), and the Moraine skill as source-controlled
  sources of truth.
- Keep every repository-owned, harness-neutral skill under [`../skills/`](../skills/)
  as a single source for both Codex and Pi; do not add harness-local duplicates.
- Pi targets a superset of portable Codex skills. Do not copy Codex `.system`,
  bundled, runtime, curated, or plugin-cache skills into the portable root.
- Keep explicit harness adapters when tools or paths differ, and claim parity
  only after equivalent Pi support is implemented and validated.
- Keep the installers idempotent and preserve unrelated user configuration.
- Add positive and negative examples for every new command rule.
- Run both test scripts after changing rules or Stop behavior.
- Re-run the Moraine installer after changing its skill or launchd layout.

## References

- [Codex lifecycle hooks](https://learn.chatgpt.com/docs/hooks)
- [Automatic approval review](https://learn.chatgpt.com/docs/sandboxing/auto-review)
- [Sandboxing](https://learn.chatgpt.com/docs/sandboxing)
- [Command rules](https://learn.chatgpt.com/docs/agent-configuration/rules)
- [AGENTS.md instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [Moraine quickstart](https://moraine.sh/quickstart.html)
- [Moraine harness installation](https://moraine.sh/agent-mcp-search/install.html)
