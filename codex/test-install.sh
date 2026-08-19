#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTER_HOME=$(mktemp -d /tmp/codex-install-outer.XXXXXX)
TARGET_HOME=$(mktemp -d /tmp/codex-install-target.XXXXXX)
MARKER="claude-code-tools-codex-install-test:$$"

cleanup() {
  for directory in "$OUTER_HOME" "$TARGET_HOME"; do
    [ -d "$directory" ] && [ ! -L "$directory" ]
    case "$(realpath "$directory")" in
      /private/tmp/codex-install-outer.*|/private/tmp/codex-install-target.*|/tmp/codex-install-outer.*|/tmp/codex-install-target.*) ;;
      *) return 1 ;;
    esac
    [ "$(cat "$directory/.integration-test-owned")" = "$MARKER" ]
  done
  rm -rf -- "$OUTER_HOME" "$TARGET_HOME"
}
trap cleanup EXIT

for directory in "$OUTER_HOME" "$TARGET_HOME"; do
  [ -d "$directory" ] && [ ! -L "$directory" ]
  ! find "$directory" -mindepth 1 -print -quit | grep -q .
  printf '%s\n' "$MARKER" > "$directory/.integration-test-owned"
done

DOTFILES="$TARGET_HOME/dotfiles"
CODEX_DIR="$TARGET_HOME/.codex"
mkdir -p "$DOTFILES" "$CODEX_DIR/rules"
printf 'external agents\n' > "$DOTFILES/AGENTS.md"
printf 'external rules\n' > "$DOTFILES/default.rules"
cat > "$DOTFILES/config.toml" <<'EOF'
model = "keep-me"

[features]
web_search = true

[mcp_servers.existing]
url = "https://example.com/mcp"
enabled = false
EOF
ln -s "$DOTFILES/AGENTS.md" "$CODEX_DIR/AGENTS.md"
ln -s "$DOTFILES/default.rules" "$CODEX_DIR/rules/default.rules"
ln -s "$DOTFILES/config.toml" "$CODEX_DIR/config.toml"

HOME="$OUTER_HOME" \
CODEX_SETUP_HOME="$TARGET_HOME" \
CODEX_SETUP_SKIP_MORAINE=1 \
"$SCRIPT_DIR/install.sh" > "$OUTER_HOME/install.log"

python3 - "$SCRIPT_DIR" "$OUTER_HOME" "$TARGET_HOME" <<'PY'
from pathlib import Path
import sys
import tomllib

script_dir, outer, target = map(Path, sys.argv[1:])
codex = target / ".codex"
dotfiles = target / "dotfiles"

assert (dotfiles / "AGENTS.md").read_text() == "external agents\n"
assert (dotfiles / "default.rules").read_text() == "external rules\n"
assert (dotfiles / "config.toml").read_text() == (
    'model = "keep-me"\n\n'
    '[features]\n'
    'web_search = true\n\n'
    '[mcp_servers.existing]\n'
    'url = "https://example.com/mcp"\n'
    'enabled = false\n'
)

assert not (codex / "AGENTS.md").is_symlink()
assert not (codex / "rules/default.rules").is_symlink()
assert not (codex / "config.toml").is_symlink()
assert (codex / "AGENTS.md").read_bytes() == (script_dir / "AGENTS.md").read_bytes()
assert (codex / "rules/default.rules").read_bytes() == (script_dir / "default.rules").read_bytes()

config = tomllib.loads((codex / "config.toml").read_text())
assert config["model"] == "keep-me"
assert config["features"]["web_search"] is True
assert config["approval_policy"] == "on-request"
assert config["sandbox_mode"] == "workspace-write"
assert config["approvals_reviewer"] == "auto_review"
assert config["mcp_servers"]["existing"] == {
    "url": "https://example.com/mcp",
    "enabled": False,
}
assert config["mcp_servers"]["notion"] == {
    "url": "https://mcp.notion.com/mcp"
}

agent_backups = list(codex.glob("AGENTS.md.backup.*"))
rule_backups = list((codex / "rules").glob("default.rules.backup.*"))
config_link_backups = list((codex / "backups").glob("config.toml.symlink.backup.*"))
assert len(agent_backups) == len(rule_backups) == len(config_link_backups) == 1
assert agent_backups[0].is_symlink() and agent_backups[0].readlink() == dotfiles / "AGENTS.md"
assert rule_backups[0].is_symlink() and rule_backups[0].readlink() == dotfiles / "default.rules"
assert config_link_backups[0].is_symlink() and config_link_backups[0].readlink() == dotfiles / "config.toml"
assert not (codex / "hooks/stop-nanny.py").exists()
PY

BROKEN_HOME="$TARGET_HOME/broken-home"
mkdir -p "$BROKEN_HOME/.codex/rules"
ln -s "$BROKEN_HOME/missing/AGENTS.md" "$BROKEN_HOME/.codex/AGENTS.md"
ln -s "$BROKEN_HOME/missing/default.rules" "$BROKEN_HOME/.codex/rules/default.rules"
ln -s "$BROKEN_HOME/missing/config.toml" "$BROKEN_HOME/.codex/config.toml"
HOME="$OUTER_HOME" \
CODEX_SETUP_HOME="$BROKEN_HOME" \
CODEX_SETUP_SKIP_MORAINE=1 \
"$SCRIPT_DIR/install.sh" > "$OUTER_HOME/broken-install.log"

python3 - "$SCRIPT_DIR" "$BROKEN_HOME" <<'PY'
from pathlib import Path
import sys
import tomllib

script_dir, target = map(Path, sys.argv[1:])
codex = target / ".codex"
assert not (codex / "AGENTS.md").is_symlink()
assert not (codex / "rules/default.rules").is_symlink()
assert not (codex / "config.toml").is_symlink()
assert (codex / "AGENTS.md").read_bytes() == (script_dir / "AGENTS.md").read_bytes()
assert (codex / "rules/default.rules").read_bytes() == (script_dir / "default.rules").read_bytes()
config = tomllib.loads((codex / "config.toml").read_text())
assert config["approval_policy"] == "on-request"
assert config["sandbox_mode"] == "workspace-write"
assert config["approvals_reviewer"] == "auto_review"
assert config["mcp_servers"]["notion"] == {
    "url": "https://mcp.notion.com/mcp"
}
agent_backup = next(codex.glob("AGENTS.md.backup.*"))
rule_backup = next((codex / "rules").glob("default.rules.backup.*"))
config_backup = next((codex / "backups").glob("config.toml.symlink.backup.*"))
assert agent_backup.is_symlink() and not agent_backup.exists()
assert rule_backup.is_symlink() and not rule_backup.exists()
assert config_backup.is_symlink() and not config_backup.exists()
assert not list(codex.glob(".config.toml.materialized.*"))
assert not (codex / "hooks/stop-nanny.py").exists()
PY

echo "Codex installer symlink tests passed."
