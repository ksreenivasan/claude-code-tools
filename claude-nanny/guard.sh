#!/bin/bash
# Config Guard — PreToolUse hook for Write/Edit
# Prompts user when agent tries to modify DCG config or Claude settings files.

INPUT=$(cat)

# Extract file_path from the tool input JSON
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Resolve to absolute path
RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# Protected paths
PROTECTED_PATTERNS=(
  "$HOME/.config/dcg/"
  "$HOME/.claude/settings.json"
  "$HOME/.claude/settings.local.json"
)

for PATTERN in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$RESOLVED" == "$PATTERN"* || "$RESOLVED" == "$PATTERN" ]]; then
    echo "[$(date '+%H:%M:%S')] [Config Guard] ASK :: Protected file: $RESOLVED" >> "$HOME/.claude/nanny.log"
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"CONFIG GUARD: Agent is modifying protected file: $RESOLVED — Review carefully!"}}
EOF
    exit 0
  fi
done
