#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_DIR/skills/tmux-nanny/SKILL.md"
METADATA="$REPO_DIR/skills/tmux-nanny/agents/openai.yaml"

python3 - "$SKILL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
frontmatter = (
    "---\n"
    "name: tmux-nanny\n"
    "description: Supervise coding agents running in tmux by identifying pane assignments, maintaining a live ledger, monitoring progress, intervening minimally, coordinating panes, and verifying completion. Use when the user asks to watch, nanny, coordinate, or supervise agents or tmux panes.\n"
    "compatibility: Requires tmux and permission to inspect and interact with the selected tmux session.\n"
    "---\n\n"
)
if not text.startswith(frontmatter):
    raise SystemExit(f"ERROR: invalid tmux-nanny skill frontmatter: {path}")
required = [
    "## Stay in the control plane",
    "Substantive coding, editing, testing, documentation, research, repository maintenance, and Git operations must be delegated to agents in the supervised panes.",
    "Delegate implementation and verification to pane agents; personally inspect their evidence without taking over the work.",
    "Substantive work on the nanny itself must also be delegated to a pane agent.",
    "Before dispatch, record each pane's task, repository, exact checkout, branch or worktree, and file ownership.",
    "Default concurrent write work in the same repository to separate worktrees.",
    "A shared checkout is acceptable only for read-only work or explicitly non-overlapping writes with a named integration owner.",
    "Detect overlapping ownership or edit activity and stop the conflicting work before either agent overwrites the other.",
]
for phrase in required:
    if phrase not in text:
        raise SystemExit(f"ERROR: tmux-nanny control-plane requirement missing: {phrase}")
PY

test -f "$METADATA"
grep -Fq 'default_prompt: "Use $tmux-nanny ' "$METADATA"
grep -Fq 'TMUX_NANNY_BACKUP_DIR="$CODEX_DIR/backups/tmux-nanny"' "$REPO_DIR/codex/install.sh"
grep -Fq 'replace_symlink_with_backup "$TMUX_NANNY_DIR"' "$REPO_DIR/codex/install.sh"
grep -Fq 'install_with_backup "$SCRIPT_DIR/../skills/tmux-nanny/SKILL.md"' "$REPO_DIR/codex/install.sh"
grep -Fq 'install_with_backup "$SCRIPT_DIR/../skills/tmux-nanny/agents/openai.yaml"' "$REPO_DIR/codex/install.sh"
grep -Fq 'TMUX_NANNY_BACKUP="$PI_DIR/backups/tmux-nanny/' "$REPO_DIR/pi/install.sh"
grep -Fq 'install_dir "$TMUX_NANNY_SOURCE" "$TMUX_NANNY_DESTINATION"' "$REPO_DIR/pi/install.sh"
grep -Fq 'SKILL_BACKUP="$TARGET_HOME/.codex/backups/moraine-history/' "$REPO_DIR/setup/install-moraine.sh"
grep -Fq 'MORAINE_SKILL_BACKUP="$PI_DIR/backups/moraine-history/' "$REPO_DIR/pi/install.sh"
test ! -e "$REPO_DIR/codex/skills/tmux-nanny/SKILL.md"
test ! -e "$REPO_DIR/pi/skills/tmux-nanny/SKILL.md"

echo "Tmux-nanny canonical skill and installer tests passed."
