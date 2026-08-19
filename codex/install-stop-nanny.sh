#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${CODEX_SETUP_HOME:-$HOME}"
CODEX_DIR="$TARGET_HOME/.codex"
HOOK_DIR="$CODEX_DIR/hooks"
HOOKS_FILE="$CODEX_DIR/hooks.json"
CONFIG_FILE="$CODEX_DIR/config.toml"
SOURCE="$SCRIPT_DIR/stop-nanny.py"
DESTINATION="$HOOK_DIR/stop-nanny.py"
STAMP="$(date '+%Y%m%d-%H%M%S')"
PYTHON_BIN="$(command -v python3)"

mkdir -p "$HOOK_DIR"

if [ -e "$DESTINATION" ] && ! cmp -s "$SOURCE" "$DESTINATION"; then
  cp -p "$DESTINATION" "$DESTINATION.backup.$STAMP"
fi
cp "$SOURCE" "$DESTINATION"
chmod 0755 "$DESTINATION"

python3 - "$HOOKS_FILE" "$CONFIG_FILE" "$PYTHON_BIN" "$DESTINATION" "$STAMP" <<'PY'
import json
import os
import re
import shlex
import shutil
import sys
import tempfile
import tomllib

path, config_path, python_binary, script, stamp = sys.argv[1:]
if os.path.exists(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
else:
    data = {}
original = json.dumps(data, sort_keys=True)

hooks = data.setdefault("hooks", {})

# DCG cannot defer uncertain calls to Codex's contextual reviewer. Remove only
# handlers whose command resolves to the DCG executable, preserving all others.
pre_tool_use = []
removed_state_keys = []
for group_index, group in enumerate(hooks.get("PreToolUse", [])):
    handlers = []
    for handler_index, handler in enumerate(group.get("hooks", [])):
        command = str(handler.get("command", ""))
        executable = shlex.split(command)[0] if command else ""
        if os.path.basename(executable) == "dcg":
            removed_state_keys.append(
                f"{path}:pre_tool_use:{group_index}:{handler_index}"
            )
            continue
        handlers.append(handler)
    if handlers:
        updated = dict(group)
        updated["hooks"] = handlers
        pre_tool_use.append(updated)
if pre_tool_use:
    hooks["PreToolUse"] = pre_tool_use
else:
    hooks.pop("PreToolUse", None)

command = f"{shlex.quote(python_binary)} {shlex.quote(script)}"
stop_groups = []
found = False
for group in hooks.get("Stop", []):
    updated = dict(group)
    handlers = []
    for handler in group.get("hooks", []):
        handler = dict(handler)
        existing = str(handler.get("command", ""))
        if existing.endswith("stop-nanny.py") or script in existing:
            if found:
                continue
            handler = {"type": "command", "command": command, "timeout": 150}
            found = True
        handlers.append(handler)
    if handlers:
        updated["hooks"] = handlers
        stop_groups.append(updated)
if not found:
    stop_groups.append({
        "hooks": [{"type": "command", "command": command, "timeout": 150}]
    })
hooks["Stop"] = stop_groups

if json.dumps(data, sort_keys=True) == original:
    print(f"Unchanged: {path}")
    raise SystemExit(0)

if os.path.exists(path):
    backup = f"{path}.backup.{stamp}"
    shutil.copy2(path, backup)
    print(f"Backed up: {backup}")

directory = os.path.dirname(path)
os.makedirs(directory, exist_ok=True)
with tempfile.NamedTemporaryFile(
    mode="w", encoding="utf-8", dir=directory, delete=False
) as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
    temporary = handle.name
os.chmod(temporary, 0o600)
os.replace(temporary, path)
print(f"Installed Stop nanny hook: {path}")

if removed_state_keys and os.path.exists(config_path):
    with open(config_path, encoding="utf-8") as handle:
        config = handle.read()
    updated_config = config
    for key in removed_state_keys:
        escaped = re.escape(key)
        pattern = (
            rf'\n\[hooks\.state\."{escaped}"\]\n'
            rf'(?:[^\n]*\n)*?(?=\n\[|\Z)'
        )
        updated_config = re.sub(pattern, "\n", updated_config)
    if updated_config != config:
        tomllib.loads(updated_config)
        backup = f"{config_path}.backup.{stamp}"
        shutil.copy2(config_path, backup)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=os.path.dirname(config_path), delete=False
        ) as handle:
            handle.write(updated_config)
            temporary = handle.name
        os.chmod(temporary, 0o600)
        os.replace(temporary, config_path)
        print(f"Removed stale DCG trust state from: {config_path}")
PY

echo "After a hook-definition change, restart Codex and review it with /hooks."
