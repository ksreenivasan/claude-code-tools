#!/bin/bash
# Claude Code Tools Installer
# Copies hooks, installs plugins, and wires settings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

echo "Claude Code Tools Installer"
echo "==========================="
echo ""

# --- 1. Install claude-nanny hooks ---
echo "[1/4] Installing claude-nanny hooks..."
mkdir -p "$HOOKS_DIR/claude-nanny"
cp "$SCRIPT_DIR/claude-nanny/claude-nanny.sh" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/guard.sh" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/nanny-clear-pending.sh" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/nanny-display.sh" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/nanny-permission-display.sh" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/nanny-show-rejection.sh" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/nanny-auto-approve.sh" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/test-cases.json" "$HOOKS_DIR/claude-nanny/"
cp "$SCRIPT_DIR/claude-nanny/test-nanny-prompt.sh" "$HOOKS_DIR/claude-nanny/"
chmod +x "$HOOKS_DIR/claude-nanny/"*.sh
echo "  Done."

# --- 2. Install Claude Code plugins ---
echo "[2/4] Installing plugins..."

# Check if claude CLI is available
if ! command -v claude &>/dev/null; then
  echo "  WARNING: 'claude' CLI not found. Install plugins manually after installing Claude Code."
else
  # Add fresheyes marketplace
  echo "  Adding fresheyes marketplace..."
  claude plugin marketplace add danshapiro/fresheyes 2>/dev/null || true

  # Install plugins
  PLUGINS=(
    "pyright-lsp@claude-plugins-official"
    "fresheyes@fresheyes-marketplace"
    "code-simplifier@claude-plugins-official"
    "pr-review-toolkit@claude-plugins-official"
    "commit-commands@claude-plugins-official"
    "hookify@claude-plugins-official"
    "ralph-loop@claude-plugins-official"
    "plugin-dev@claude-plugins-official"
    "claude-code-setup@claude-plugins-official"
    "skill-creator@claude-plugins-official"
  )

  for PLUGIN in "${PLUGINS[@]}"; do
    echo "  Installing $PLUGIN..."
    claude plugin install "$PLUGIN" 2>/dev/null || echo "    (skipped — may already be installed or unavailable)"
  done
fi

# --- 3. Wire hooks into settings.json ---
echo "[3/4] Wiring hooks into settings.json..."

if [ ! -f "$SETTINGS" ]; then
  # No existing settings — use template directly (expand $HOME)
  sed "s|\$HOME|$HOME|g" "$SCRIPT_DIR/setup/settings-template.json" > "$SETTINGS"
  echo "  Created $SETTINGS from template."
else
  echo "  $SETTINGS already exists."
  echo "  Please merge hooks manually from: $SCRIPT_DIR/setup/settings-template.json"
  echo "  (Automated merge would risk overwriting your existing settings.)"
fi

# --- 4. Install persistent Moraine cross-session search ---
echo "[4/4] Installing Moraine..."
"$SCRIPT_DIR/setup/install-moraine.sh" claude-code

echo ""
echo "Done! Restart Claude Code for hooks to take effect."
echo ""
echo "Optional extras (install manually):"
echo "  - peon-ping: Sound notifications for Claude Code events"
echo "    https://github.com/PeonPing/peon-ping"
