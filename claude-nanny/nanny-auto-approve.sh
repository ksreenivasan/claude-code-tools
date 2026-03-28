#!/bin/bash
# PermissionRequest auto-approve — suppresses built-in heuristic dialogs
# when the nanny already allowed the action via PreToolUse.
#
# Logic:
#   pending file exists → nanny said "ask" → show the dialog
#   pending file absent → nanny said "allow" → suppress the dialog

LOGFILE="$HOME/.claude/nanny.log"
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
PENDING_FILE="$HOME/.claude/nanny-pending-${SESSION_ID}"

echo "[$(date '+%H:%M:%S')] [AutoApprove] Fired. pending_file=$PENDING_FILE exists=$([ -f "$PENDING_FILE" ] && echo yes || echo no)" >> "$LOGFILE"

if [ -f "$PENDING_FILE" ]; then
  # Nanny intentionally wants user confirmation — show the dialog
  echo "[$(date '+%H:%M:%S')] [AutoApprove] Pending found — showing dialog" >> "$LOGFILE"
  exit 0
fi

# Nanny already allowed this — suppress the built-in heuristic dialog
echo "[$(date '+%H:%M:%S')] [AutoApprove] No pending — auto-approving" >> "$LOGFILE"
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
