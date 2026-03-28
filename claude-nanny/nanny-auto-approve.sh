#!/bin/bash
# PermissionRequest auto-approve — suppresses built-in heuristic dialogs
# when the nanny already allowed the action via PreToolUse.
#
# Logic:
#   /tmp/nanny-pending exists → nanny said "ask" → show the dialog
#   /tmp/nanny-pending absent → nanny said "allow" → suppress the dialog

if [ -f /tmp/nanny-pending ]; then
  # Nanny intentionally wants user confirmation — show the dialog
  exit 0
fi

# Nanny already allowed this — suppress the built-in heuristic dialog
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
