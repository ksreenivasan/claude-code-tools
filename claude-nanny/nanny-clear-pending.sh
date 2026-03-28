#!/bin/bash
# Clears nanny-pending on successful tool use (means the ask was approved)
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
rm -f "$HOME/.claude/nanny-pending-${SESSION_ID}"
