#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${CODEX_SETUP_HOME:-$HOME}"
CODEX_DIR="$TARGET_HOME/.codex"
RULES_DIR="$CODEX_DIR/rules"
CONFIG="$CODEX_DIR/config.toml"
STAMP="$(date '+%Y%m%d-%H%M%S')"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to merge config.toml safely." >&2
  exit 1
fi

echo "Codex setup"
echo "==========="
echo "Target: $CODEX_DIR"
echo

mkdir -p "$RULES_DIR"

backup_symlink() {
  local destination="$1"
  local backup="$2"
  mkdir -p "$(dirname "$backup")"
  if ! cp -P "$destination" "$backup"; then
    echo "ERROR: could not back up symlink $destination" >&2
    return 1
  fi
  echo "Backed up symlink: $backup"
}

install_with_backup() {
  local source="$1"
  local destination="$2"

  if [ -e "$destination" ] && cmp -s "$source" "$destination"; then
    echo "Unchanged: $destination"
    return
  fi

  if [ -L "$destination" ]; then
    local backup="${destination}.backup.${STAMP}"
    backup_symlink "$destination" "$backup"
    rm "$destination"
  elif [ -e "$destination" ]; then
    local backup="${destination}.backup.${STAMP}"
    cp -p "$destination" "$backup"
    echo "Backed up: $backup"
  fi

  cp "$source" "$destination"
  chmod 0644 "$destination"
  echo "Installed: $destination"
}

replace_symlink_with_backup() {
  local destination="$1"
  local backup="$2"
  if [ ! -L "$destination" ]; then
    return
  fi
  backup_symlink "$destination" "$backup"
  rm "$destination"
}

materialize_symlink_with_backup() {
  local destination="$1"
  local backup="$2"
  if [ ! -L "$destination" ]; then
    return
  fi
  if [ ! -e "$destination" ]; then
    backup_symlink "$destination" "$backup"
    rm "$destination"
    return
  fi
  local materialized
  materialized=$(mktemp "$CODEX_DIR/.config.toml.materialized.XXXXXX")
  if ! cp -pL "$destination" "$materialized"; then
    rm -f "$materialized"
    echo "ERROR: could not materialize symlink $destination" >&2
    return 1
  fi
  if ! backup_symlink "$destination" "$backup"; then
    rm -f "$materialized"
    return 1
  fi
  if ! rm "$destination"; then
    rm -f "$materialized"
    return 1
  fi
  if ! mv "$materialized" "$destination"; then
    cp -P "$backup" "$destination" || true
    rm -f "$materialized"
    return 1
  fi
}

install_with_backup "$SCRIPT_DIR/AGENTS.md" "$CODEX_DIR/AGENTS.md"
install_with_backup "$SCRIPT_DIR/default.rules" "$RULES_DIR/default.rules"
TMUX_NANNY_DIR="$CODEX_DIR/skills/tmux-nanny"
TMUX_NANNY_BACKUP_DIR="$CODEX_DIR/backups/tmux-nanny"
replace_symlink_with_backup "$TMUX_NANNY_DIR" "$TMUX_NANNY_BACKUP_DIR/directory.backup.$STAMP"
mkdir -p "$TMUX_NANNY_DIR/agents"
replace_symlink_with_backup "$TMUX_NANNY_DIR/SKILL.md" "$TMUX_NANNY_BACKUP_DIR/SKILL.md.backup.$STAMP"
replace_symlink_with_backup "$TMUX_NANNY_DIR/agents/openai.yaml" "$TMUX_NANNY_BACKUP_DIR/openai.yaml.backup.$STAMP"
install_with_backup "$SCRIPT_DIR/../skills/tmux-nanny/SKILL.md" "$TMUX_NANNY_DIR/SKILL.md"
install_with_backup "$SCRIPT_DIR/../skills/tmux-nanny/agents/openai.yaml" "$TMUX_NANNY_DIR/agents/openai.yaml"
materialize_symlink_with_backup "$CONFIG" "$CODEX_DIR/backups/config.toml.symlink.backup.$STAMP"

python3 - "$CONFIG" "$STAMP" <<'PY'
import os
import re
import shutil
import sys
import tempfile
import tomllib

path, stamp = sys.argv[1:]
settings = {
    "approval_policy": '"on-request"',
    "sandbox_mode": '"workspace-write"',
    "approvals_reviewer": '"auto_review"',
}

if os.path.exists(path):
    with open(path, encoding="utf-8") as handle:
        original = handle.read()
    try:
        tomllib.loads(original)
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit(f"ERROR: refusing to edit invalid TOML at {path}: {exc}")
else:
    original = ""

lines = original.splitlines(keepends=True)
seen = set()
output = []
inserted_missing = False
in_top_level = True

def insert_missing() -> None:
    global inserted_missing
    if inserted_missing:
        return
    missing = [key for key in settings if key not in seen]
    if missing and output and output[-1].strip():
        output.append("\n")
    output.extend(f"{key} = {settings[key]}\n" for key in missing)
    if missing and lines:
        output.append("\n")
    inserted_missing = True

for line in lines:
    if in_top_level and re.match(r"^\s*\[", line):
        insert_missing()
        in_top_level = False

    replaced = False
    if in_top_level:
        for key, value in settings.items():
            if re.match(rf"^\s*{re.escape(key)}\s*=", line):
                if key in seen:
                    raise SystemExit(
                        f"ERROR: duplicate top-level {key!r} in {path}; fix it manually"
                    )
                output.append(f"{key} = {value}\n")
                seen.add(key)
                replaced = True
                break
    if not replaced:
        output.append(line)

if in_top_level:
    insert_missing()

updated = "".join(output)
try:
    tomllib.loads(updated)
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(f"ERROR: merged config did not validate: {exc}")

if updated == original:
    print(f"Unchanged: {path}")
    raise SystemExit(0)

if original:
    backup = f"{path}.backup.{stamp}"
    shutil.copy2(path, backup)
    print(f"Backed up: {backup}")

directory = os.path.dirname(path)
with tempfile.NamedTemporaryFile(
    mode="w", encoding="utf-8", dir=directory, delete=False
) as handle:
    handle.write(updated)
    temporary = handle.name
os.chmod(temporary, 0o600)
os.replace(temporary, path)
print(f"Merged: {path}")
PY

echo
echo "Validating rules, tmux-nanny skill, and Stop behavior..."
"$SCRIPT_DIR/test-rules.sh"
"$SCRIPT_DIR/../setup/test-tmux-nanny.sh"
"$SCRIPT_DIR/test-stop-nanny.sh"

if [ "$TARGET_HOME" = "$HOME" ]; then
  if command -v codex >/dev/null 2>&1; then
    codex --strict-config --version
  elif [ -x "/Applications/ChatGPT.app/Contents/Resources/codex" ]; then
    /Applications/ChatGPT.app/Contents/Resources/codex \
      --strict-config --version
  fi
fi

echo
echo "Core setup complete. Stop nanny remains available but is not installed."

if [ "${CODEX_SETUP_SKIP_MORAINE:-0}" != "1" ]; then
  "$SCRIPT_DIR/../setup/install-moraine.sh" codex
fi

echo
echo "Setup complete. Moraine will start at login through launchd."
