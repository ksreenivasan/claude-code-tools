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

node "$SCRIPT_DIR/tests/extensions.test.ts"
"$SCRIPT_DIR/../setup/test-portable-skills.sh"
"$SCRIPT_DIR/../setup/test-tmux-nanny.sh"
