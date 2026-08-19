#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ROOT="$REPO_DIR/skills"
TMP_ROOT="$(mktemp -d /tmp/portable-skills-test.XXXXXX)"

cleanup() {
  case "$(realpath "$TMP_ROOT")" in
    /private/tmp/portable-skills-test.*|/tmp/portable-skills-test.*) rm -rf -- "$TMP_ROOT" ;;
    *) echo "ERROR: refusing to clean unexpected test path: $TMP_ROOT" >&2; return 1 ;;
  esac
}
trap cleanup EXIT

CODEX_SKILLS="$TMP_ROOT/codex/skills"
CODEX_BACKUPS="$TMP_ROOT/codex/backups"
PI_SKILLS="$TMP_ROOT/pi/skills"
PI_BACKUPS="$TMP_ROOT/pi/backups"
mkdir -p "$CODEX_SKILLS/codebase-recon" "$PI_SKILLS" "$TMP_ROOT/legacy-skill"
printf 'old codex skill\n' > "$CODEX_SKILLS/codebase-recon/stale.txt"
printf 'old pi skill\n' > "$TMP_ROOT/legacy-skill/stale.txt"
ln -s "$TMP_ROOT/legacy-skill" "$PI_SKILLS/skill-evaluator"

"$SCRIPT_DIR/install-shared-skills.sh" "$SOURCE_ROOT" "$CODEX_SKILLS" "$CODEX_BACKUPS" codex-test >/dev/null
"$SCRIPT_DIR/install-shared-skills.sh" "$SOURCE_ROOT" "$PI_SKILLS" "$PI_BACKUPS" pi-test >/dev/null

python3 - "$SOURCE_ROOT" "$CODEX_SKILLS" "$PI_SKILLS" <<'PY'
from pathlib import Path
import re
import sys

source_root, codex_root, pi_root = map(Path, sys.argv[1:])
expected_new = {
    "caveman",
    "codebase-recon",
    "fresheyes",
    "grill-me",
    "mcp-builder",
    "skill-evaluator",
}
found = {p.name for p in source_root.iterdir() if p.is_dir() and (p / "SKILL.md").is_file()}
missing = expected_new - found
assert not missing, f"missing canonical portable skills: {sorted(missing)}"

for name in sorted(found):
    text = (source_root / name / "SKILL.md").read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    assert match, f"invalid frontmatter: {name}"
    declared = re.search(r"(?m)^name:\s*([^\s]+)\s*$", match.group(1))
    assert declared and declared.group(1) == name, f"skill name mismatch: {name}"
    assert (codex_root / name / "SKILL.md").is_file(), f"missing Codex install: {name}"
    assert (pi_root / name / "SKILL.md").is_file(), f"missing Pi install: {name}"

for name in expected_new:
    frontmatter = (source_root / name / "SKILL.md").read_text(encoding="utf-8").split("---", 2)[1]
    assert "disable-model-invocation" not in frontmatter
    assert "allow_implicit_invocation" not in frontmatter
PY

for source in "$SOURCE_ROOT"/*; do
  [ -f "$source/SKILL.md" ] || continue
  name="$(basename "$source")"
  diff -qr "$source" "$CODEX_SKILLS/$name" >/dev/null
  diff -qr "$source" "$PI_SKILLS/$name" >/dev/null
done

test -f "$CODEX_BACKUPS/codebase-recon/codebase-recon.backup.codex-test/stale.txt"
test "$(cat "$CODEX_BACKUPS/codebase-recon/codebase-recon.backup.codex-test/stale.txt")" = "old codex skill"
test -L "$PI_BACKUPS/skill-evaluator/skill-evaluator.backup.pi-test"
test "$(readlink "$PI_BACKUPS/skill-evaluator/skill-evaluator.backup.pi-test")" = "$TMP_ROOT/legacy-skill"
test ! -e "$CODEX_SKILLS/.system"
test ! -e "$PI_SKILLS/.system"

grep -Fq 'setup/install-shared-skills.sh"' "$REPO_DIR/codex/install.sh"
grep -Fq 'setup/install-shared-skills.sh"' "$REPO_DIR/pi/install.sh"
grep -Fq '"$SCRIPT_DIR/../skills"' "$REPO_DIR/codex/install.sh"
grep -Fq '"$REPO_DIR/skills"' "$REPO_DIR/pi/install.sh"

echo "Portable skill installer and parity tests passed."
