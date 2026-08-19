#!/bin/bash
# Install Moraine and keep its services outside agent-session sandboxes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-codex}"
TARGET_HOME="${AGENT_SETUP_HOME:-${CODEX_SETUP_HOME:-$HOME}}"
MORAINE_BIN="$(command -v moraine 2>/dev/null || true)"

case "$TARGET" in
  codex) MCP_TARGET="codex" ;;
  claude-code) MCP_TARGET="claude-code" ;;
  pi) MCP_TARGET="pi-coding-agent" ;;
  *) echo "Usage: $0 [codex|claude-code|pi]" >&2; exit 2 ;;
esac

echo "Moraine Installer"
echo "================="

if [ -z "$MORAINE_BIN" ] && command -v uv >/dev/null 2>&1; then
  MORAINE_BIN="$(uv tool dir --bin)/moraine"
fi

if [ -z "$MORAINE_BIN" ] || [ ! -x "$MORAINE_BIN" ]; then
  if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv is required to install moraine-cli." >&2
    exit 1
  fi
  uv tool install moraine-cli
  MORAINE_BIN="$(uv tool dir --bin)/moraine"
fi

if [ ! -x "$MORAINE_BIN" ]; then
  echo "ERROR: moraine was installed but is not executable at $MORAINE_BIN." >&2
  exit 1
fi

MORAINE_BIN="$(cd "$(dirname "$MORAINE_BIN")" && pwd -P)/$(basename "$MORAINE_BIN")"

echo "Installed: $($MORAINE_BIN --version)"
if [ "$TARGET_HOME" = "$HOME" ]; then
  "$MORAINE_BIN" setup --yes --mcp-target "$MCP_TARGET"
else
  HOME="$TARGET_HOME" "$MORAINE_BIN" setup --yes --mcp-target "$MCP_TARGET"
fi

if [ "$TARGET" = "pi" ]; then
  MORAINE_MCP_BIN="$(dirname "$MORAINE_BIN")/moraine-mcp"
  if [ ! -x "$MORAINE_MCP_BIN" ]; then
    echo "ERROR: Moraine MCP executable not found at $MORAINE_MCP_BIN" >&2
    exit 1
  fi
  python3 - "$TARGET_HOME/.pi/agent/mcp.json" "$MORAINE_MCP_BIN" <<'PY'
import json
import os
import sys
import tempfile

path, moraine_mcp = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
server = data.setdefault("mcpServers", {}).get("moraine")
if not isinstance(server, dict):
    raise SystemExit(f"ERROR: Moraine setup did not create mcpServers.moraine in {path}")
desired_args = ["--serve", "stdio"]
if server.get("command") != moraine_mcp or server.get("args") != desired_args:
    server["command"] = moraine_mcp
    server["args"] = desired_args
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=os.path.dirname(path), delete=False
    ) as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
        temporary = handle.name
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    print(f"Pinned Moraine MCP command: {moraine_mcp} {' '.join(desired_args)}")
PY
fi

if [ "$TARGET" = "codex" ]; then
  SKILL_SOURCE="$REPO_DIR/codex/skills/moraine-history"
  SKILL_TARGET="$TARGET_HOME/.codex/skills/moraine-history"
  SKILL_BACKUP="$TARGET_HOME/.codex/backups/moraine-history/moraine-history.backup.$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$(dirname "$SKILL_TARGET")"
  if [ -L "$SKILL_TARGET" ] || { [ -e "$SKILL_TARGET" ] && ! diff -qr "$SKILL_SOURCE" "$SKILL_TARGET" >/dev/null; }; then
    mkdir -p "$(dirname "$SKILL_BACKUP")"
    if [ -L "$SKILL_TARGET" ]; then
      cp -P "$SKILL_TARGET" "$SKILL_BACKUP"
    else
      cp -R "$SKILL_TARGET" "$SKILL_BACKUP"
    fi
    rm -rf "$SKILL_TARGET"
    echo "Backed up: $SKILL_BACKUP"
  fi
  if [ -d "$SKILL_TARGET" ] && diff -qr "$SKILL_SOURCE" "$SKILL_TARGET" >/dev/null; then
    echo "Unchanged skill: $SKILL_TARGET"
  else
    cp -R "$SKILL_SOURCE" "$SKILL_TARGET"
    echo "Installed skill: $SKILL_TARGET"
  fi
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Moraine integration is configured, but no persistent service manager was installed."
  echo "Run Moraine under systemd or another host-level supervisor before using session search."
  exit 0
fi

LAUNCH_AGENTS="$TARGET_HOME/Library/LaunchAgents"
LOG_DIR="$TARGET_HOME/.moraine/logs"
mkdir -p "$LAUNCH_AGENTS" "$LOG_DIR"

python3 - "$LAUNCH_AGENTS" "$LOG_DIR" "$MORAINE_BIN" "$TARGET_HOME" "$(date '+%Y%m%d-%H%M%S')" <<'PY'
import os
import plistlib
import shutil
import sys
import tempfile

launch_agents, log_dir, moraine, home, stamp = sys.argv[1:]
path = f"{home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
for service in ("clickhouse", "ingest", "backend"):
    label = f"dev.moraine.{service}"
    payload = {
        "Label": label,
        "ProgramArguments": [moraine, "run", service],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
        "ProcessType": "Background",
        "WorkingDirectory": home,
        "EnvironmentVariables": {"HOME": home, "PATH": path},
        "StandardOutPath": os.path.join(log_dir, f"launchd-{service}.log"),
        "StandardErrorPath": os.path.join(log_dir, f"launchd-{service}.log"),
    }
    destination = os.path.join(launch_agents, f"{label}.plist")
    next_content = plistlib.dumps(payload, sort_keys=False)
    try:
        with open(destination, "rb") as handle:
            current_content = handle.read()
    except FileNotFoundError:
        current_content = None
    if current_content == next_content:
        print(f"Unchanged launch agent: {destination}")
        continue
    if current_content is not None:
        backup = f"{destination}.backup.{stamp}"
        shutil.copy2(destination, backup)
        print(f"Backed up launch agent: {backup}")
    with tempfile.NamedTemporaryFile(dir=launch_agents, delete=False) as handle:
        handle.write(next_content)
        temporary = handle.name
    os.chmod(temporary, 0o644)
    os.replace(temporary, destination)
    open(f"{destination}.changed", "w").close()
    print(f"Installed launch agent: {destination}")
PY

if [ "$TARGET_HOME" != "$HOME" ]; then
  rm -f "$LAUNCH_AGENTS"/dev.moraine.*.plist.changed
  echo "Prepared launch agents under $TARGET_HOME without loading them into the current user's launchd domain."
  exit 0
fi

DOMAIN="gui/$(id -u)"
for service in clickhouse ingest backend; do
  label="dev.moraine.$service"
  plist="$LAUNCH_AGENTS/$label.plist"
  if [ -f "$plist.changed" ]; then
    launchctl bootout "$DOMAIN/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "$DOMAIN" "$plist"
    rm "$plist.changed"
  elif ! launchctl print "$DOMAIN/$label" >/dev/null 2>&1; then
    launchctl bootstrap "$DOMAIN" "$plist"
  elif ! launchctl print "$DOMAIN/$label" 2>/dev/null | grep -q 'state = running'; then
    launchctl kickstart -k "$DOMAIN/$label"
  fi
done

for _ in $(seq 1 60); do
  if "$MORAINE_BIN" status --output json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
services = {item["service"]: item["state"] for item in data.get("services", [])}
healthy = data.get("doctor", {}).get("clickhouse_healthy") is True
healthy = healthy and all(services.get(name) == "running" for name in ("ingest", "backend"))
raise SystemExit(0 if healthy else 1)
'; then
    echo "Moraine is healthy and owned by launchd."
    echo "Monitor: http://127.0.0.1:8080"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Moraine did not become healthy within 60 seconds." >&2
"$MORAINE_BIN" status >&2 || true
exit 1
