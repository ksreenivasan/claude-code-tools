#!/bin/bash
# Nanny Display — PostToolUse hook that shows the nanny's last decision via systemMessage

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
LOGFILE="$HOME/.claude/nanny-${SESSION_ID}.log"

if [ ! -f "$LOGFILE" ]; then
  exit 0
fi

LAST_LINE=$(tail -1 "$LOGFILE" 2>/dev/null)

if [ -n "$LAST_LINE" ]; then
  # Escape quotes for JSON
  ESCAPED=$(echo "$LAST_LINE" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"systemMessage\": \"$ESCAPED\"}"
fi
