#!/bin/bash
# Shows nanny's rationale for rejected tool calls.
#
# WORKAROUND: Claude Code has no ToolRejected/PermissionDenied hook event.
# See: https://github.com/anthropics/claude-code/issues/14967
# When the user rejects a permission prompt, NO hook fires (not PostToolUse,
# not PostToolUseFailure, not Stop). So we use a pending-file trick:
#
# 1. PreToolUse (claude-nanny.sh) writes reason to ~/.claude/nanny-pending-<session_id> on "ask"
# 2. PostToolUse (nanny-clear-pending.sh) deletes it on approval
# 3. UserPromptSubmit (this script) checks: if file still exists = was rejected
#    → show the reason via systemMessage, then clean up
#
# This means the nanny's rationale is shown ONE MESSAGE DELAYED (on the user's
# next input after rejection). Not ideal but the best we can do.
#
# TODO: If Claude Code adds a ToolRejected hook event, move this logic there
# for instant display on rejection. Track the feature request above.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
PENDING_FILE="$HOME/.claude/nanny-pending-${SESSION_ID}"

if [ -f "$PENDING_FILE" ]; then
  MSG=$(cat "$PENDING_FILE" | sed 's/"/\\"/g')
  rm -f "$PENDING_FILE"
  echo "{\"systemMessage\": \"$MSG\"}"
fi
