#!/bin/bash
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js is required." >&2
  exit 1
fi

if ! node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)'; then
  echo "ERROR: Node.js 22.19 or newer is required by Pi." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.pi/agent"
cat > "$TEST_HOME/.pi/agent/mcp.json" <<'JSON'
{
  "settings": {"toolPrefix": "custom"},
  "mcpServers": {
    "moraine": {"transport": "stdio", "command": "/example/moraine"},
    "other": {"transport": "sse", "url": "https://example.com/sse"},
    "notion": {"transport": "stdio", "command": "stale"}
  }
}
JSON
chmod 0644 "$TEST_HOME/.pi/agent/mcp.json"
PI_SETUP_HOME="$TEST_HOME" "$SCRIPT_DIR/install.sh" --configure-notion-mcp
PI_SETUP_HOME="$TEST_HOME" "$SCRIPT_DIR/install.sh" --configure-notion-mcp
python3 - "$TEST_HOME/.pi/agent" <<'PY'
import json
import os
import stat
import sys

agent_dir = sys.argv[1]
config_path = os.path.join(agent_dir, "mcp.json")
auth_dir = os.path.join(agent_dir, "mcp-auth")
with open(config_path, encoding="utf-8") as handle:
    data = json.load(handle)

assert data["mcpServers"]["notion"] == {
    "transport": "streamable-http",
    "url": "https://mcp.notion.com/mcp",
    "auth": {"type": "oauth"},
    "lifecycle": "lazy",
}
assert data["mcpServers"]["moraine"] == {
    "transport": "stdio",
    "command": "/example/moraine",
}
assert data["mcpServers"]["other"] == {
    "transport": "sse",
    "url": "https://example.com/sse",
}
assert data["settings"] == {"toolPrefix": "custom"}
assert stat.S_IMODE(os.stat(config_path).st_mode) == 0o600
assert stat.S_IMODE(os.stat(auth_dir).st_mode) == 0o700
print("Pi Notion MCP configuration tests passed.")
PY

node "$SCRIPT_DIR/tests/extensions.test.ts"
"$SCRIPT_DIR/../setup/test-portable-skills.sh"
"$SCRIPT_DIR/../setup/test-tmux-nanny.sh"
