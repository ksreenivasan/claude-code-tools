#!/bin/bash
# PermissionRequest auto-approve — suppresses built-in heuristic dialogs
# when the nanny already allowed the action via PreToolUse.
#
# Logic:
#   /tmp/nanny-pending-<session> exists → nanny said "ask" → show the dialog
#   /tmp/nanny-pending-<session> absent → nanny said "allow" → suppress the dialog

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
PENDING_FILE="/tmp/nanny-pending-${SESSION_ID}"

if [ -f "$PENDING_FILE" ]; then
  # Nanny intentionally wants user confirmation — show the dialog
  exit 0
fi

# Nanny already allowed this — suppress the built-in heuristic dialog
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
