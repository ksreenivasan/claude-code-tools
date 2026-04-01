#!/bin/bash
# PermissionRequest auto-approve — suppresses built-in heuristic dialogs
# when the nanny already allowed the action via PreToolUse.
#
# Logic:
#   pending file exists → nanny said "ask" → show the dialog
#   pending file absent → nanny said "allow" → suppress the dialog

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
LOGFILE="$HOME/.claude/nanny-${SESSION_ID}.log"
PENDING_FILE="$HOME/.claude/nanny-pending-${SESSION_ID}"
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

echo "[$(date '+%H:%M:%S')] [AutoApprove] Fired. tool=$TOOL_NAME pending_file=$PENDING_FILE exists=$([ -f "$PENDING_FILE" ] && echo yes || echo no)" >> "$LOGFILE"

# Interactive tools need native dialog — never auto-approve
case "$TOOL_NAME" in
  AskUserQuestion|EnterPlanMode|ExitPlanMode)
    echo "[$(date '+%H:%M:%S')] [AutoApprove] Interactive tool $TOOL_NAME — showing native dialog" >> "$LOGFILE"
    exit 0 ;;
esac

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
