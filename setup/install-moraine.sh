#!/bin/bash
# Moraine installer — local trace DB + cross-session search for Claude Code.
#
# Moraine (https://github.com/eric-tramel/moraine) indexes your agent sessions
# into a local ClickHouse, serves a monitor UI, and exposes session search to
# agents over MCP. This script installs it, starts the stack, and wires the
# MCP server into ~/.claude.json so the search tools are available in Claude Code.
#
# Heads up: the first `moraine up` downloads a ClickHouse static build
# (~175MB) into ~/.local/lib/moraine. Everything stays local — nothing leaves
# your machine unless you configure a remote backend yourself.
set -euo pipefail

CLAUDE_JSON="$HOME/.claude.json"

echo "Moraine Installer"
echo "================="
echo ""

# --- 1. Install the moraine CLI ---
echo "[1/3] Installing moraine-cli..."
if command -v moraine &>/dev/null; then
  echo "  Already installed ($(moraine --version 2>/dev/null || echo present))."
elif command -v uv &>/dev/null; then
  uv tool install moraine-cli
  echo "  Installed via uv."
else
  echo "  'uv' not found — installing via the official bundle script instead."
  echo "  (Install uv for the recommended path: https://docs.astral.sh/uv/)"
  curl -fsSL https://raw.githubusercontent.com/eric-tramel/moraine/main/scripts/install.sh | sh
fi

if ! command -v moraine &>/dev/null; then
  echo "  ERROR: moraine still not on PATH. Ensure ~/.local/bin is in your PATH and re-run." >&2
  exit 1
fi

# --- 2. Start the stack (ClickHouse, ingest, monitor, MCP) ---
echo "[2/3] Starting Moraine services..."
echo "  (first run downloads ClickHouse ~175MB; subsequent runs are instant)"
moraine up --monitor --mcp
echo "  Monitor UI: http://127.0.0.1:8080"

# --- 3. Wire the MCP server into Claude Code (~/.claude.json) ---
echo "[3/3] Registering Moraine MCP server in $CLAUDE_JSON..."

# The stdio server proxies to the central server started by `moraine up --mcp`.
read -r -d '' MORAINE_ENTRY <<'JSON' || true
{"type": "stdio", "command": "moraine-mcp", "args": [], "env": {}}
JSON

wire_with_jq() {
  local tmp; tmp="$(mktemp)"
  jq --argjson entry "$MORAINE_ENTRY" \
     '.mcpServers = (.mcpServers // {}) | .mcpServers.moraine = $entry' \
     "$CLAUDE_JSON" > "$tmp" && mv "$tmp" "$CLAUDE_JSON"
}

wire_with_python() {
  python3 - "$CLAUDE_JSON" "$MORAINE_ENTRY" <<'PY'
import json, os, sys
path, entry = sys.argv[1], json.loads(sys.argv[2])
data = json.load(open(path)) if os.path.exists(path) else {}
data.setdefault("mcpServers", {})["moraine"] = entry
json.dump(data, open(path, "w"), indent=2)
PY
}

if [ -f "$CLAUDE_JSON" ] && grep -q '"moraine"' "$CLAUDE_JSON" 2>/dev/null; then
  echo "  'moraine' already registered — leaving it as is."
else
  [ -f "$CLAUDE_JSON" ] && cp "$CLAUDE_JSON" "$CLAUDE_JSON.bak.moraine" && echo "  Backed up to $CLAUDE_JSON.bak.moraine"
  if command -v jq &>/dev/null; then
    wire_with_jq && echo "  Registered (via jq)."
  elif command -v python3 &>/dev/null; then
    wire_with_python && echo "  Registered (via python3)."
  else
    echo "  Neither jq nor python3 found. Add this to \"mcpServers\" in $CLAUDE_JSON manually:"
    echo "    \"moraine\": $MORAINE_ENTRY"
  fi
fi

echo ""
echo "Done! Restart Claude Code, then run /mcp to confirm 'moraine' is connected."
echo ""
echo "Use it from Claude Code via the search_sessions / list_sessions / open MCP tools."
echo "Manage services with: moraine status | moraine up | moraine down"
