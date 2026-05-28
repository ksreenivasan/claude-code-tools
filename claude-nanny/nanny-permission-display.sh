#!/bin/bash
# Nanny Permission Display — shows nanny's rationale when a permission dialog appears.
# Fires on PermissionRequest, reads the last nanny ASK entry from the log.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
LOGFILE="$HOME/.claude/nanny-${SESSION_ID}.log"

if [ ! -f "$LOGFILE" ]; then
  exit 0
fi

# Get the last ASK line from the log
LAST_ASK=$(grep '\[Nanny\] ASK' "$LOGFILE" | tail -1 2>/dev/null)

if [ -n "$LAST_ASK" ]; then
  ESCAPED=$(echo "$LAST_ASK" | sed 's/"/\\"/g')
  echo "{\"systemMessage\": \"$ESCAPED\"}"
fi
