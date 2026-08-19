#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/stop-nanny.py"
INPUT='{"session_id":"test","cwd":"/tmp","stop_hook_active":false,"last_assistant_message":"Work is partly done."}'

complete=$(CODEX_STOP_NANNY_TEST_RESULT='{"verdict":"COMPLETE","reason":"done"}' "$HOOK" <<<"$INPUT")
[ "$complete" = '{}' ] || { echo "COMPLETE fixture failed: $complete" >&2; exit 1; }

premature=$(CODEX_STOP_NANNY_TEST_RESULT='{"verdict":"PREMATURE","reason":"tests remain"}' "$HOOK" <<<"$INPUT")
python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["decision"] == "block"; assert "tests remain" in data["reason"]' <<<"$premature"

active=$(CODEX_STOP_NANNY_TEST_RESULT='{"verdict":"PREMATURE","reason":"ignored"}' "$HOOK" <<<'{"session_id":"test","stop_hook_active":true}')
[ "$active" = '{}' ] || { echo "loop prevention fixture failed: $active" >&2; exit 1; }

echo "Stop nanny tests passed."
