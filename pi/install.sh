#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_HOME="${PI_SETUP_HOME:-$HOME}"
PI_DIR="$TARGET_HOME/.pi/agent"
STAMP="$(date '+%Y%m%d-%H%M%S')"
PI_BIN="$(command -v pi 2>/dev/null || true)"

if [ -z "$PI_BIN" ]; then
  echo "ERROR: pi is required." >&2
  exit 1
fi

install_file() {
  local source="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  if [ -e "$destination" ] && cmp -s "$source" "$destination"; then
    echo "Unchanged: $destination"
    return
  fi
  if [ -L "$destination" ]; then
    cp -P "$destination" "$destination.backup.$STAMP"
    rm "$destination"
    echo "Backed up symlink: $destination.backup.$STAMP"
  elif [ -e "$destination" ]; then
    cp -p "$destination" "$destination.backup.$STAMP"
    echo "Backed up: $destination.backup.$STAMP"
  fi
  cp "$source" "$destination"
  chmod 0644 "$destination"
  echo "Installed: $destination"
}

install_dir() {
  local source="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  if [ -d "$destination" ] && diff -qr "$source" "$destination" >/dev/null; then
    echo "Unchanged: $destination"
    return
  fi
  if [ -L "$destination" ]; then
    cp -P "$destination" "$destination.backup.$STAMP"
    rm "$destination"
    echo "Backed up symlink: $destination.backup.$STAMP"
  elif [ -e "$destination" ]; then
    cp -R "$destination" "$destination.backup.$STAMP"
    echo "Backed up: $destination.backup.$STAMP"
    rm -rf "$destination"
  fi
  cp -R "$source" "$destination"
  echo "Installed: $destination"
}

echo "Pi setup"
echo "========"
echo "Target: $PI_DIR"
echo

"$SCRIPT_DIR/test.sh"
mkdir -p "$PI_DIR"
install_file "$SCRIPT_DIR/AGENTS.md" "$PI_DIR/AGENTS.md"

# Install this directory as a local Pi package. Pi records the absolute path and
# loads its safety, notification, and prompt resources. The Stop nanny source
# remains packaged but is intentionally disabled in package.json.
PI_CODING_AGENT_DIR="$PI_DIR" "$PI_BIN" install "$SCRIPT_DIR"

# Codex and Pi install the same repository-owned tmux-nanny skill. Keep stale
# copies outside skills/ so Pi cannot discover a backup as a duplicate skill.
TMUX_NANNY_SOURCE="$REPO_DIR/skills/tmux-nanny"
TMUX_NANNY_DESTINATION="$PI_DIR/skills/tmux-nanny"
TMUX_NANNY_BACKUP="$PI_DIR/backups/tmux-nanny/tmux-nanny.backup.$STAMP"
if [ -L "$TMUX_NANNY_DESTINATION" ] || { [ -e "$TMUX_NANNY_DESTINATION" ] && ! diff -qr "$TMUX_NANNY_SOURCE" "$TMUX_NANNY_DESTINATION" >/dev/null; }; then
  mkdir -p "$(dirname "$TMUX_NANNY_BACKUP")"
  if [ -L "$TMUX_NANNY_DESTINATION" ]; then
    cp -P "$TMUX_NANNY_DESTINATION" "$TMUX_NANNY_BACKUP"
  else
    cp -R "$TMUX_NANNY_DESTINATION" "$TMUX_NANNY_BACKUP"
  fi
  rm -rf "$TMUX_NANNY_DESTINATION"
  echo "Backed up: $TMUX_NANNY_BACKUP"
fi
install_dir "$TMUX_NANNY_SOURCE" "$TMUX_NANNY_DESTINATION"

# Use Pi's maintained subagent extension from the installed Pi version while
# keeping personal agent prompts in this repository.
PI_REAL="$(realpath "$PI_BIN")"
PI_ROOT="$(dirname "$(dirname "$PI_REAL")")"
SUBAGENT_SOURCE=""
for candidate in \
  "$PI_ROOT/examples/extensions/subagent" \
  "$PI_ROOT/dist/examples/extensions/subagent"; do
  if [ -f "$candidate/index.ts" ]; then
    SUBAGENT_SOURCE="$candidate"
    break
  fi
done
if [ -n "$SUBAGENT_SOURCE" ]; then
  install_file "$SUBAGENT_SOURCE/index.ts" "$PI_DIR/extensions/subagent/index.ts"
  install_file "$SUBAGENT_SOURCE/agents.ts" "$PI_DIR/extensions/subagent/agents.ts"
  for agent in "$SCRIPT_DIR"/agents/*.md; do
    install_file "$agent" "$PI_DIR/agents/$(basename "$agent")"
  done
else
  echo "WARNING: Pi's subagent example was not found; core extensions will still work." >&2
fi

# Moraine owns its persistent host services and official Pi MCP bridge. The
# custom history skill adds the workflow and health-check policy. Keep stale
# copies outside skills/ so Pi cannot discover backups as duplicate skills.
AGENT_SETUP_HOME="$TARGET_HOME" "$REPO_DIR/setup/install-moraine.sh" pi
MORAINE_SKILL_SOURCE="$SCRIPT_DIR/skills/moraine-history"
MORAINE_SKILL_DESTINATION="$PI_DIR/skills/moraine-history"
MORAINE_SKILL_BACKUP="$PI_DIR/backups/moraine-history/moraine-history.backup.$STAMP"
if [ -L "$MORAINE_SKILL_DESTINATION" ] || { [ -e "$MORAINE_SKILL_DESTINATION" ] && ! diff -qr "$MORAINE_SKILL_SOURCE" "$MORAINE_SKILL_DESTINATION" >/dev/null; }; then
  mkdir -p "$(dirname "$MORAINE_SKILL_BACKUP")"
  if [ -L "$MORAINE_SKILL_DESTINATION" ]; then
    cp -P "$MORAINE_SKILL_DESTINATION" "$MORAINE_SKILL_BACKUP"
  else
    cp -R "$MORAINE_SKILL_DESTINATION" "$MORAINE_SKILL_BACKUP"
  fi
  rm -rf "$MORAINE_SKILL_DESTINATION"
  echo "Backed up: $MORAINE_SKILL_BACKUP"
fi
install_dir "$MORAINE_SKILL_SOURCE" "$MORAINE_SKILL_DESTINATION"
chmod 0755 "$MORAINE_SKILL_DESTINATION/scripts/health-check.sh"

printf '\nInstalled Pi resources. Run /reload in an existing Pi session, or start a new one.\n'
