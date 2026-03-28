#!/bin/bash
# Claude Nanny — Unified safety layer for ALL tool calls.
#
# Native tools: Read/Glob/Grep passthrough (read-only). Write/Edit go to Opus.
# Bash: truly read-only commands get instant allow. Everything else goes to Opus.
# NEVER returns empty output — always returns an explicit decision.
# Fail-closed: if AI call fails, prompts user for manual approval.
# Logs all decisions to ~/.claude/nanny.log

LOGFILE="$HOME/.claude/nanny.log"

log() {
  echo "[$(date '+%H:%M:%S')] $1" >> "$LOGFILE"
  echo "$1" >&2
}

allow() {
  local LABEL="$1"
  local DESC="$2"
  log "[Nanny] ALLOW ($LABEL) :: $DESC"
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Nanny: $LABEL","additionalContext":"[Nanny sid=${SESSION_ID}] ALLOW ($LABEL) :: $DESC"}}
EOF
}

ask() {
  local LABEL="$1"
  local DESC="$2"
  local REASON="$3"
  log "[Nanny] ASK ($LABEL) :: $DESC :: $REASON"
  # Write pending ask so rejection can be detected later
  echo "[Nanny] ASK ($LABEL) :: $DESC :: $REASON" > $HOME/.claude/nanny-pending-${SESSION_ID}
  local ESC_REASON=$(echo "$REASON" | sed 's/"/\\"/g')
  local ESC_DESC=$(echo "$DESC" | sed 's/"/\\"/g')
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"CLAUDE NANNY: ${ESC_REASON}","additionalContext":"[Nanny sid=${SESSION_ID}] ASK ($LABEL) :: $ESC_DESC"}}
EOF
}

ask_opus() {
  local DESC="$1"
  local EVAL_TEXT="$2"

  log "[Nanny] Consulting Opus for: $DESC ..."

  TMPFILE=$(mktemp)
  trap "rm -f $TMPFILE" EXIT

  cat > "$TMPFILE" <<'HEADER'
You are a safety evaluator for an AI coding assistant. Output ONLY a raw JSON object (no markdown, no code blocks).

Err on the side of ALLOWING commands. The user is actively working on a task with an AI assistant, and most commands are necessary for task completion. Only flag something as RISKY if it is genuinely dangerous, destructive, or externally visible to other people.

SAFE (allow these — not exhaustive): running scripts, building, testing, text processing, installing packages, reading, writing, editing projects and artifacts, git operations that stay local (including checkout, reset, rebase, merge) or even other ones that seem necessary for the task at hand, shell expansion, piping commands together, running dev tools etc. Skills, agents, subagents, code review tools and review loops are almost always SAFE.

RISKY (flag these — not exhaustive): git force push, deleting important source directories (rm -rf on project roots), system-level changes (apt/systemctl), overwriting safety config files (~/.claude/settings*, ~/.config/dcg/*), sending messages to other people (Slack, email), deploying to production etc.

When in doubt, SAFE. The cost of a false block (interrupting the user's flow) is higher than the cost of allowing a borderline-safe command. Do NOT flag things just because they are "externally visible" — git push, creating PRs, and similar actions are normal parts of a dev workflow. However, these externally-visible actions (push, PR creation, deployments) should only be allowed if the user explicitly asked for them to be done in this interaction.

Action to evaluate:
HEADER
  echo "$EVAL_TEXT" >> "$TMPFILE"
  if [ -n "$LAST_USER_MSG" ]; then
    echo "" >> "$TMPFILE"
    echo "User's recent messages (most recent last):" >> "$TMPFILE"
    echo "$LAST_USER_MSG" >> "$TMPFILE"
  else
    echo "" >> "$TMPFILE"
    echo "User's recent messages: (not available)" >> "$TMPFILE"
  fi
  log "[Nanny/ctx] user_msg_len=${#LAST_USER_MSG} preview=${LAST_USER_MSG:0:120}"
  cat >> "$TMPFILE" <<'FOOTER'

Output ONLY: {"verdict":"SAFE","reason":"brief reason why it's safe"} or {"verdict":"RISKY","reason":"brief reason why it's risky"}
FOOTER

  RAW=$(claude -p --model opus --output-format json --no-session-persistence --max-budget-usd 999 < "$TMPFILE" 2>/dev/null)

  RESULT_TEXT=$(echo "$RAW" | jq -r '.result // empty' 2>/dev/null)
  CLEAN=$(echo "$RESULT_TEXT" | sed 's/^```[a-z]*//;s/^```//;s/```$//' | tr -d '\n' | sed 's/^[[:space:]]*//')
  SAFE_CHECK=$(echo "$CLEAN" | jq -r '.verdict // empty' 2>/dev/null)

  if [ "$SAFE_CHECK" = "SAFE" ]; then
    SAFE_REASON=$(echo "$CLEAN" | jq -r '.reason // ""' 2>/dev/null)
    if [ -n "$SAFE_REASON" ]; then
      allow "Opus: $SAFE_REASON" "$DESC"
    else
      allow "Opus approved" "$DESC"
    fi
  elif [ "$SAFE_CHECK" = "RISKY" ]; then
    REASON=$(echo "$CLEAN" | jq -r '.reason // "Flagged as risky by AI safety check"' 2>/dev/null)
    ask "Opus flagged" "$DESC" "$REASON"
  else
    ask "Opus unreachable" "$DESC" "Could not evaluate safety. Please review manually."
  fi
}

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
GSD_FILE="$HOME/.claude/nanny-gsd-${SESSION_ID}"


# Extract last 3 user messages from transcript for Opus context (best-effort)
# User-typed messages have .message.content as a string.
# Tool results have .message.content as an array. We want the string ones.
LAST_USER_MSG=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_USER_MSG=$(grep '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -r 'select(.message.content | type == "string") | .message.content' 2>/dev/null \
    | tail -3 | head -c 1000)
fi

# --- GET SHIT DONE mode ---
# When GSD file exists for this session, Opus still evaluates but with a much
# higher threshold. The file contents describe the task being worked on.
# Toggle: write task to $GSD_FILE (on) | rm $GSD_FILE (off)
if [ -f "$GSD_FILE" ]; then
  GSD_TASK=$(cat "$GSD_FILE" 2>/dev/null)

  # Read-only native tools: instant allow (no Opus needed even normally)
  case "$TOOL_NAME" in
    Read|Glob|Grep|WebSearch)
      allow "GSD" "$TOOL_NAME"
      exit 0 ;;
  esac

  # Everything else: ask Opus with GSD-calibrated prompt
  if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    DESC=$(echo "$COMMAND" | head -c 120)
    EVAL_TEXT="Bash command: $COMMAND"
  elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
    RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    DESC="$TOOL_NAME $(echo "$RESOLVED" | sed "s|$HOME|~|")"
    EVAL_TEXT="$TOOL_NAME to file: $RESOLVED"
  else
    DESC="$TOOL_NAME"
    EVAL_TEXT="Tool: $TOOL_NAME with input: $(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null | head -c 200)"
  fi

  log "[Nanny/GSD] Consulting Opus for: $DESC ..."

  TMPFILE=$(mktemp)
  trap "rm -f $TMPFILE" EXIT

  cat > "$TMPFILE" <<GSDHEADER
You are a safety evaluator. We are in GET SHIT DONE mode. Output ONLY a raw JSON object (no markdown, no code blocks).

The user is actively working on this task: ${GSD_TASK}

In this mode, ALLOW almost everything. The user wants to move fast with minimal interruptions. Only flag something as RISKY if it is GENUINELY CATASTROPHIC and clearly NOT part of the task — things like:
- Deleting the user's home directory or critical system files
- Exfiltrating credentials/secrets to external URLs
- Permanently destroying data that cannot be recovered

IMPORTANT: If the task description says an action is safe or the action is clearly required to accomplish the task, ALLOW it — even git pushes. Use the task description as your primary guide. When in doubt, SAFE.

Action to evaluate:
GSDHEADER
  echo "$EVAL_TEXT" >> "$TMPFILE"
  cat >> "$TMPFILE" <<'GSDFOOTER'

Output ONLY: {"verdict":"SAFE","reason":"brief reason"} or {"verdict":"RISKY","reason":"brief reason"}
GSDFOOTER

  RAW=$(claude -p --model opus --output-format json --no-session-persistence --max-budget-usd 999 < "$TMPFILE" 2>/dev/null)

  RESULT_TEXT=$(echo "$RAW" | jq -r '.result // empty' 2>/dev/null)
  CLEAN=$(echo "$RESULT_TEXT" | sed 's/^```[a-z]*//;s/^```//;s/```$//' | tr -d '\n' | sed 's/^[[:space:]]*//')
  SAFE_CHECK=$(echo "$CLEAN" | jq -r '.verdict // empty' 2>/dev/null)

  if [ "$SAFE_CHECK" = "SAFE" ]; then
    SAFE_REASON=$(echo "$CLEAN" | jq -r '.reason // ""' 2>/dev/null)
    allow "GSD: ${SAFE_REASON:-approved}" "$DESC"
  elif [ "$SAFE_CHECK" = "RISKY" ]; then
    REASON=$(echo "$CLEAN" | jq -r '.reason // "Genuinely dangerous even in GSD mode"' 2>/dev/null)
    ask "GSD blocked" "$DESC" "$REASON"
  else
    # Fail OPEN in GSD mode — user wants to move fast
    allow "GSD: Opus unreachable, fail-open" "$DESC"
  fi
  exit 0
fi

# --- Read-only native tools: passthrough ---
case "$TOOL_NAME" in
  Read|Glob|Grep|WebSearch)
    allow "read-only" "$TOOL_NAME"
    exit 0 ;;
esac

# --- Write/Edit: send to Opus ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
  RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
  SHORT_PATH=$(echo "$RESOLVED" | sed "s|$HOME|~|")
  ask_opus "$TOOL_NAME $SHORT_PATH" "$TOOL_NAME to file: $RESOLVED"
  exit 0
fi

# --- WebFetch: send to Opus (could exfiltrate) ---
if [ "$TOOL_NAME" = "WebFetch" ]; then
  URL=$(echo "$INPUT" | jq -r '.tool_input.url // empty' 2>/dev/null)
  ask_opus "WebFetch $URL" "Fetching URL: $URL"
  exit 0
fi

# --- Non-Bash tools we don't recognize: send to Opus ---
if [ "$TOOL_NAME" != "Bash" ]; then
  TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null | head -c 200)
  ask_opus "$TOOL_NAME" "Tool: $TOOL_NAME with input: $TOOL_INPUT"
  exit 0
fi

# --- Bash: extract command ---
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  allow "no command" "Bash (empty)"
  exit 0
fi

SHORT_CMD=$(echo "$COMMAND" | head -c 120)

# Strip leading comment lines and blank lines to find the real first command
STRIPPED_CMD=$(echo "$COMMAND" | sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d')
FIRST_WORD=$(echo "$STRIPPED_CMD" | awk '{print $1}')

# Fast-path: read-only commands
case "$FIRST_WORD" in
  ls|tree|cat|head|tail|wc|file|which|whoami|pwd|echo|printenv|stat|du|df|readlink|realpath|diff|sort|uniq|cut|tr|jq|less|more|strings|xxd|od|hexdump|ldd|nm|objdump|date|cal|bc|expr|seq|nproc|uname|hostname|id|groups|locale|lsb_release|test|\[|true|false|grep|rg|find|cd|chmod|mkdir|touch|cp|mv)
    allow "fast-path" "$SHORT_CMD"; exit 0 ;;
esac

# Fast-path: git read-only subcommands
if [ "$FIRST_WORD" = "git" ] || [ "$FIRST_WORD" = "cd" ]; then
  # Extract the git subcommand (handles "cd /foo && git status" and plain "git status")
  GIT_SUB=$(echo "$STRIPPED_CMD" | grep -oE 'git\s+\S+' | head -1 | awk '{print $2}')
  case "$GIT_SUB" in
    status|log|diff|branch|remote|show|rev-parse|fetch|stash|tag|shortlog|describe|ls-files|ls-tree|cat-file|name-rev|blame|reflog|worktree)
      allow "fast-path git" "$SHORT_CMD"; exit 0 ;;
  esac
fi

# Everything else: Opus evaluates
ask_opus "$SHORT_CMD" "Bash command: $COMMAND"
