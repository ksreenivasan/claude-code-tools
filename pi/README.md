# Pi Setup

This directory ports the personal Codex/Claude workflow to Pi while keeping the
setup reproducible.

## Installed resources

| Resource | Purpose |
| --- | --- |
| `~/.pi/agent/AGENTS.md` | Global working agreement, autonomy, GSD, Git, and verification policy |
| `safety-review.ts` | Independently reviews recognized risky tool calls with a child Pi process |
| `stop-nanny.ts` | Available but disabled completion reviewer; retained for later tuning |
| `notify.ts` | Native terminal notification when Pi is genuinely idle |
| Portable skills | Installs every repository-owned skill from [`../skills/`](../skills/), including recon, evaluation, review, MCP-building, and explicit tmux supervision |
| Pi `moraine-history` adapter | Health check and Pi-native workflow for historical session retrieval |
| `pi-mcp-extension@1.5.0` | Exposes Moraine and hosted Notion MCP tools to Pi |
| Hosted Notion MCP | Uses Streamable HTTP and interactive OAuth without storing a token in repository config |
| Pi subagent extension | Runs isolated scout, planner, worker, reviewer, and simplifier agents |
| Prompt templates | `/scout-and-plan`, `/implement-and-review`, and `/review` |

DCG is deliberately not installed. Recognized high-risk actions are reviewed in
context instead of being denied by an earlier binary rule layer.

## Install

```bash
pi/install.sh
```

The installer:

1. Runs deterministic extension tests.
2. Backs up and installs the global working agreement.
3. Installs this directory as a local Pi package.
4. Copies every canonical portable skill from [`../skills/`](../skills/), with recoverable backups outside skill discovery.
5. Copies Pi's maintained subagent extension from the active Pi installation.
6. Installs the personal agent definitions.
7. Configures Moraine's official Pi MCP bridge and persistent launch agents.
8. Pins `pi-mcp-extension@1.5.0`, merges the hosted Notion MCP entry without replacing other servers, and creates private OAuth storage.
9. Installs the Moraine history skill.

Run `/reload` in an existing Pi session after installation. Invoke the nanny
explicitly with `/skill:tmux-nanny`.
Both Pi and Codex install every canonical skill under [`../skills/`](../skills/).
Pi targets a superset of portable Codex skills. Codex `.system` skills and
bundled, runtime, curated, or plugin-cache capabilities remain harness-native
and must not be copied blindly. When a capability needs different tools or
paths, keep explicit harness adapters and claim parity only after equivalent Pi
support is implemented and validated.

## Safety review

Routine tools proceed without review. The extension recognizes destructive Git,
recursive deletion, infrastructure mutations, external publication, privileged
service changes, and edits to agent control/credential files. It gives the
latest real user requests and proposed call to a separate tool-less
`gpt-5.6-luna` Pi process.

The reviewer returns one of:

- `allow`: proceed silently apart from a compact notification.
- `ask`: ask the user only because material ambiguity remains.
- `deny`: block a clearly unrelated, unbounded, catastrophic, evasive, or
  secret-exposing action.

Exact recursive cleanup of an existing non-symlink disposable temp, test,
build, or cache directory bypasses child review. Broad roots, unresolved
variables or globs, destructive history changes, infrastructure mutations, and
other high-blast actions remain reviewed.

Set `PI_REVIEW_MODEL` to override the reviewer model.

## Stop nanny (disabled)

The Stop nanny source and tests are retained for later tuning, but it is omitted
from `package.json` and is not loaded. If re-enabled later, it gives recent user
messages, Git status, diff statistics, and the proposed final response to an
isolated reviewer, with a one-nudge-per-user-prompt recursion guard.

## Moraine

Before using `search_sessions`, `list_sessions`, `file_attention`, `open`, or
`get_ingest_status`, follow the `moraine-history` skill and run its health check.
Moraine is owned by these launch agents on macOS:

- `dev.moraine.clickhouse`
- `dev.moraine.ingest`
- `dev.moraine.backend`

## Hosted Notion MCP

The installer preserves existing MCP servers and adds this exact non-secret entry to
`~/.pi/agent/mcp.json`:

```json
{
  "transport": "streamable-http",
  "url": "https://mcp.notion.com/mcp",
  "auth": { "type": "oauth" },
  "lifecycle": "lazy"
}
```

It keeps `mcp.json` at mode `0600` and precreates `~/.pi/agent/mcp-auth` at
mode `0700`. Authentication remains an explicit user action. In Pi, run:

```text
/reload
/mcp:auth notion
/mcp notion
```

The browser flow stores plaintext OAuth state under `~/.pi/agent/mcp-auth`.
After first authentication or any explicit reauthentication, normalize the state
file permissions without reading them:

```bash
find ~/.pi/agent/mcp-auth -maxdepth 1 -type f -exec chmod 0600 {} +
```

For a minimal smoke test, authorize a disposable Notion scratch parent, fetch it
without mutation, create one uniquely named child containing a random nonce, then
fetch that child by returned ID and verify the exact nonce. On later Pi launches,
start the lazy server with `/mcp:start notion`; `/mcp:auth notion` intentionally
resets saved OAuth state.

## Verification

```bash
pi/test.sh
bash -n pi/install.sh pi/test.sh
setup/test-portable-skills.sh
~/.pi/agent/skills/moraine-history/scripts/health-check.sh
pi list
```

## Maintaining the Pi fork

Use `origin` for `git@github.com:ksreenivasan/pi.git` and `upstream` for the
canonical `git@github.com:earendil-works/pi.git`. Keep `main` tracking
`origin/main`, and disable pushing to `upstream` to prevent mistakes:

```bash
git remote set-url --push upstream DISABLED
```

To bring canonical changes into the fork, begin with a clean worktree and use a
merge rather than a rebase:

```bash
git fetch --prune origin
git fetch --prune upstream
git switch main
git merge --ff-only origin/main
git merge upstream/main
npm run check
git push origin main
```

If either merge reports a conflict, stop and resolve only understood files. Do
not force-push or discard concurrent agent work.
