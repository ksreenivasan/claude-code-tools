# Claude Code Tools

Personal Claude Code hooks, plugins, and dev environment config.

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
- **Auto-approve**: Suppresses Claude Code's built-in permission prompts when the nanny already allowed the action
- **Conversation context**: Reads last 3 user messages from the transcript so Opus can determine if externally-visible actions were explicitly requested

**Important:** Do NOT add `"Bash"` to your `permissions.allow` list in `settings.local.json`. The nanny's `ask` decision is overridden by the allow list — if Bash is blanket-allowed, the nanny can never prompt you for confirmation. The auto-approve hook handles silently approving safe commands instead.

**Test suite**: 34 test cases with parallel execution. Run `claude-nanny/test-nanny-prompt.sh` to verify prompt behavior.

#### How It Works — Permission Flow

The nanny replaces Claude Code's built-in permission heuristics. Three hooks coordinate to make this work:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Tool Call Triggered                          │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
                 ┌─────────────────────────┐
                 │   1. PreToolUse Hook     │
                 │    (claude-nanny.sh)     │
                 └────────────┬────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐   ┌──────────┐   ┌──────────────┐
        │ Fast-path│   │  Opus    │   │  Read-only   │
        │  (local  │   │evaluates │   │  tools       │
        │  cmds)   │   │ command  │   │(Read,Glob,..)│
        └────┬─────┘   └────┬─────┘   └──────┬───────┘
             │               │                │
             ▼               ▼                ▼
          ALLOW         SAFE / RISKY       ALLOW
             │          ╱         ╲           │
             │         ▼           ▼          │
             │      ALLOW        ASK          │
             │    (no file)   (writes         │
             │                pending file)   │
             │                    │           │
             └────────┬───────────┘───────────┘
                      │
                      ▼
       ┌──────────────────────────────────┐
       │  Claude Code Permission Check    │
       │  Is "Bash" in permissions.allow? │
       └──────────────┬───────────────────┘
                      │
            ┌─────────┴─────────┐
            ▼                   ▼
     ┌─────────────┐    ┌─────────────────┐
     │ YES (BAD!)  │    │ NO (correct)    │
     │ allow list  │    │ fires           │
     │ overrides   │    │ PermissionReq   │
     │ nanny ask   │    └────────┬────────┘
     │ → nanny is  │             │
     │   bypassed  │             ▼
     └─────────────┘   ┌──────────────────────┐
                       │ 2. PermissionRequest  │
                       │  (nanny-auto-approve) │
                       └───────────┬───────────┘
                                   │
                       ┌───────────┴───────────┐
                       ▼                       ▼
               ┌──────────────┐        ┌──────────────┐
               │ Pending file │        │ No pending   │
               │ EXISTS       │        │ file         │
               │ (nanny said  │        │ (nanny said  │
               │  ask)        │        │  allow)      │
               └──────┬───────┘        └──────┬───────┘
                      │                       │
                      ▼                       ▼
               ┌──────────────┐        ┌──────────────┐
               │ Show prompt  │        │ Auto-approve │
               │ to user      │        │ (suppress    │
               │              │        │  prompt)     │
               └──────┬───────┘        └──────┬───────┘
                      │                       │
            ┌─────────┴────────┐              │
            ▼                  ▼              │
     ┌────────────┐    ┌────────────┐         │
     │ User       │    │ User       │         │
     │ approves   │    │ rejects    │         │
     └─────┬──────┘    └─────┬──────┘         │
           │                 │                │
           ▼                 ▼                ▼
    ┌─────────────┐   ┌────────────┐   ┌────────────┐
    │ Tool runs   │   │ Tool       │   │ Tool runs  │
    │             │   │ blocked    │   │ silently   │
    └─────┬───────┘   └────────────┘   └─────┬──────┘
          │                                   │
          ▼                                   ▼
   ┌─────────────────┐                ┌─────────────────┐
   │ 3. PostToolUse  │                │ 3. PostToolUse  │
   │ clears pending  │                │ (no pending to  │
   │ file            │                │  clear)         │
   └─────────────────┘                └─────────────────┘
```

**Key insight:** The auto-approve hook (`nanny-auto-approve.sh`) is what makes it safe to keep `Bash` out of the allow list. Without it, Claude Code's built-in heuristics would prompt on every non-trivial Bash command. With it, the nanny's ALLOW decisions flow through silently while its ASK decisions still show the prompt.

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
