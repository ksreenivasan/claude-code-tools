# Claude Code Tools

Personal Claude Code hooks, plugins, and dev environment setup. Portable across any machine.

## Quick Start

```bash
git clone git@github.com:ksreenivasan/claude-code-tools.git
cd claude-code-tools
./install.sh
```

## What's Included

### Claude Nanny (`claude-nanny/`)

AI-powered safety layer for Claude Code. Evaluates every tool call before execution using Opus as a judge.

- **Fast-path**: Instant allow for read-only tools, safe Bash commands, git read-only subcommands
- **Opus evaluation**: Everything else gets evaluated. Errs on the side of allowing — only flags genuinely destructive or dangerous actions
- **GSD mode**: "Get Shit Done" mode with minimal interruptions. Toggle per-session.
- **Config guard**: Protects `~/.claude/settings*` and `~/.config/dcg/*` from accidental overwrites

**Test suite**: 33 test cases with parallel execution. Run `claude-nanny/test-nanny-prompt.sh` to verify prompt behavior.

### Install Script (`install.sh`)

One command to set up everything:
1. Copies nanny hooks to `~/.claude/hooks/claude-nanny/`
2. Installs [DCG](https://github.com/Dicklesworthstone/destructive_command_guard) (Destructive Command Guard)
3. Installs Claude Code plugins from public marketplaces
4. Wires hooks into `~/.claude/settings.json`

### Settings Template (`setup/settings-template.json`)

Hook wiring config for `~/.claude/settings.json`. Maps nanny scripts to Claude Code events:
- `PreToolUse` — main nanny evaluation + config guard
- `PostToolUse` / `PostToolUseFailure` — status display
- `UserPromptSubmit` — rejection reason display
- `PermissionRequest` — permission display

### Plugins (installed via `install.sh`)

All from public sources:

| Plugin | Source | Description |
|--------|--------|-------------|
| pyright-lsp | claude-plugins-official | Python type checking |
| fresheyes | [danshapiro/fresheyes](https://github.com/danshapiro/fresheyes) | Independent code review |
| code-simplifier | claude-plugins-official | Code cleanup |
| pr-review-toolkit | claude-plugins-official | PR review agents |
| commit-commands | claude-plugins-official | Git commit helpers |
| hookify | claude-plugins-official | Hook creation from conversation |
| ralph-loop | claude-plugins-official | Autonomous dev loop |
| plugin-dev | claude-plugins-official | Plugin development |
| claude-code-setup | claude-plugins-official | Setup recommendations |
| skill-creator | claude-plugins-official | Skill authoring |

## Optional: Peon-Ping

Sound notification system that plays voice lines on Claude Code events (tool calls, completions, errors). Install from: https://github.com/PeonPing/peon-ping

## Customization

### GSD Mode

Toggle Get Shit Done mode for the current session:

```bash
# Enable (describe your task)
echo "Working on feature X" > ~/.claude/nanny-gsd-${SESSION_ID}

# Disable
rm ~/.claude/nanny-gsd-${SESSION_ID}
```

### Adding to Fast-Path

Edit `claude-nanny/claude-nanny.sh` line ~213 to add commands to the instant-allow list.

### Tuning the Opus Prompt

Edit the `HEADER` block in `claude-nanny/claude-nanny.sh` (~line 50). Run the test suite after changes:

```bash
claude-nanny/test-nanny-prompt.sh
```
