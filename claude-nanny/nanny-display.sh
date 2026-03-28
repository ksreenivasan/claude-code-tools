#!/bin/bash
# Nanny Display — PostToolUse hook that shows the nanny's last decision via systemMessage

LOGFILE="$HOME/.claude/nanny.log"

if [ ! -f "$LOGFILE" ]; then
  exit 0
fi

LAST_LINE=$(tail -1 "$LOGFILE" 2>/dev/null)

if [ -n "$LAST_LINE" ]; then
  # Escape quotes for JSON
  ESCAPED=$(echo "$LAST_LINE" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"systemMessage\": \"$ESCAPED\"}"
fi
