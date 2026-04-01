#!/bin/bash
# Nanny Stop Monitor — evaluates whether the agent stopped prematurely.
#
# Fires on every Stop event. Uses Opus to determine if the agent completed
# the user's request or stopped mid-task.
#
# Three-tier goal awareness:
#   1. Task state (TaskCreate/TaskUpdate from transcript)
#   2. User messages (last 5 from transcript)
#   3. Enriched re-evaluation on UNCERTAIN (git diff, plan files, deeper history)
#
# Loop prevention: counter-based, max 10 nudges per user turn.
# Counter reset happens in nanny-show-rejection.sh on UserPromptSubmit.
#
# Opus failure: retry once, then assume PREMATURE (max counter protects against loops).

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ]; then
  # No session ID — can't track state, allow stop
  echo '{"systemMessage": "[Nanny] No session ID — allowing stop."}'
  exit 0
fi
LOGFILE="$HOME/.claude/nanny-${SESSION_ID}.log"
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // "false"' 2>/dev/null)
LAST_ASST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# --- Configuration ---
MAX_NUDGES=10
COUNTER_FILE="$HOME/.claude/nanny-stop-count-${SESSION_ID}"
GSD_FILE="$HOME/.claude/nanny-gsd-${SESSION_ID}"

log() {
  echo "[$(date '+%H:%M:%S')] [Nanny] $1" >> "$LOGFILE"
  echo "[Nanny] $1" >&2
}

# --- Loop prevention ---
# If already continuing from a prior nudge AND counter is high, don't nudge again
CURRENT_COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  CURRENT_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi

if [ "$STOP_HOOK_ACTIVE" = "true" ] && [ "$CURRENT_COUNT" -ge 1 ]; then
  log "stop_hook_active=true with count=$CURRENT_COUNT. Allowing stop to prevent rapid re-nudge."
  jq -n --arg msg "[Nanny] Already nudged this cycle. Allowing stop." '{"systemMessage": $msg}'
  exit 0
fi

if [ "$CURRENT_COUNT" -ge "$MAX_NUDGES" ]; then
  log "Max nudges ($MAX_NUDGES) reached. Allowing stop."
  jq -n --arg msg "[Nanny] Max nudges ($MAX_NUDGES) reached. Allowing stop." '{"systemMessage": $msg}'
  exit 0
fi

# --- Fail-open: no transcript = no context to evaluate ---
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "No transcript available. Allowing stop."
  jq -n '{"systemMessage": "[Nanny] No transcript — allowing stop."}'
  exit 0
fi

# --- Extract last assistant message (fallback to transcript if not in input) ---
if [ -z "$LAST_ASST_MSG" ]; then
  LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 100)
  if [ -n "$LAST_LINES" ]; then
    LAST_ASST_MSG=$(echo "$LAST_LINES" | jq -rs '
      map(.message.content[]? | select(.type == "text") | .text) | last // ""
    ' 2>/dev/null | head -c 3000)
  fi
fi

if [ -z "$LAST_ASST_MSG" ]; then
  log "No assistant message found. Allowing stop."
  jq -n '{"systemMessage": "[Nanny] No assistant message — allowing stop."}'
  exit 0
fi

# --- Extract last 5 user messages from transcript ---
LAST_USER_MSGS=""
if [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_USER_MSGS=$(grep '"role":"user"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -r 'select(.message.content | type == "string") | .message.content' 2>/dev/null \
    | tail -5 | head -c 2000)
fi

# --- Extract task state from transcript (best-effort) ---
TASK_INFO=""
if [ -f "$TRANSCRIPT_PATH" ]; then
  # Look for TaskCreate/TaskUpdate tool uses in assistant messages
  TASK_INFO=$(grep -E '"TaskCreate"|"TaskUpdate"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -r '.message.content[]? | select(.type == "tool_use") | select(.name == "TaskCreate" or .name == "TaskUpdate") | .input | tojson' 2>/dev/null \
    | tail -10 | head -c 1500)
fi

# --- GSD task context ---
GSD_TASK=""
if [ -f "$GSD_FILE" ]; then
  GSD_TASK=$(cat "$GSD_FILE" 2>/dev/null)
fi

# --- Build Opus evaluation prompt ---
build_prompt() {
  local USER_MSGS="$1"
  local TASKS="$2"
  local ASST_MSG="$3"
  local EXTRA_CONTEXT="$4"

  TMPFILE=$(mktemp)

  if [ -n "$GSD_TASK" ]; then
    cat > "$TMPFILE" <<GSDHEADER
You are a task completion evaluator for an AI coding assistant. We are in GET SHIT DONE mode.
The user's task: ${GSD_TASK}

In GSD mode, lean STRONGLY toward PREMATURE. The user wants maximum work output per interaction.
Only classify as COMPLETE if the task described above is clearly and fully done.

Output ONLY a raw JSON object (no markdown, no code blocks).
GSDHEADER
  else
    cat > "$TMPFILE" <<'HEADER'
You are a task completion evaluator for an AI coding assistant. The agent has stopped.
Determine if the agent completed the user's request or stopped prematurely.

Output ONLY a raw JSON object (no markdown, no code blocks).
HEADER
  fi

  echo "" >> "$TMPFILE"
  echo "=== RECENT USER MESSAGES (most recent last) ===" >> "$TMPFILE"
  if [ -n "$USER_MSGS" ]; then
    echo "$USER_MSGS" >> "$TMPFILE"
  else
    echo "(none available)" >> "$TMPFILE"
  fi

  echo "" >> "$TMPFILE"
  echo "=== TASK STATE (if available) ===" >> "$TMPFILE"
  if [ -n "$TASKS" ]; then
    echo "$TASKS" >> "$TMPFILE"
  else
    echo "(no tasks tracked)" >> "$TMPFILE"
  fi

  echo "" >> "$TMPFILE"
  echo "=== LAST ASSISTANT MESSAGE ===" >> "$TMPFILE"
  echo "$ASST_MSG" >> "$TMPFILE"

  if [ -n "$EXTRA_CONTEXT" ]; then
    echo "" >> "$TMPFILE"
    echo "=== ADDITIONAL CONTEXT ===" >> "$TMPFILE"
    echo "$EXTRA_CONTEXT" >> "$TMPFILE"
  fi

  cat >> "$TMPFILE" <<'FOOTER'

IMPORTANT: Weight the LAST user message most heavily. Prior messages provide context,
but the user's most recent message defines the current intent.

Evaluate:
1. Did the assistant complete what the user asked for in their LAST message?
2. Did it end with a clear conclusion, or trail off mid-task?
3. Are there obvious next steps it should have taken but didn't?
4. Is it correctly waiting for user input (asked a question)? → COMPLETE
5. Did the user's LAST message ask the agent to pause/wait/hold on (e.g. "wait",
   "hold on", "take a beat", "one sec", "give me a moment")? → COMPLETE (user wants a pause)

Classification:
- COMPLETE: Request fully addressed, correctly waiting for user input, OR user asked to pause
- PREMATURE: Clearly stopped mid-task with unfinished work that was requested
- UNCERTAIN: Cannot determine — scope is ambiguous

Bias: Lean toward PREMATURE when in doubt. An unnecessary nudge (agent does
a bit more work) costs less than a premature stop (user has to re-prompt).

Output ONLY: {"verdict":"COMPLETE","reason":"..."} or {"verdict":"PREMATURE","reason":"what remains"} or {"verdict":"UNCERTAIN","reason":"why unclear"}
FOOTER

  echo "$TMPFILE"
}

# --- Call Opus and parse result ---
call_opus() {
  local PROMPT_FILE="$1"
  local RAW
  local RESULT_TEXT
  local CLEAN

  RAW=$(claude -p --model opus --output-format json --no-session-persistence --max-budget-usd 999 < "$PROMPT_FILE" 2>/dev/null)
  RESULT_TEXT=$(echo "$RAW" | jq -r '.result // empty' 2>/dev/null)
  CLEAN=$(echo "$RESULT_TEXT" | sed 's/^```[a-z]*//;s/^```//;s/```$//' | tr -d '\n' | sed 's/^[[:space:]]*//')

  echo "$CLEAN"
}

parse_verdict() {
  local CLEAN="$1"
  echo "$CLEAN" | jq -r '.verdict // empty' 2>/dev/null
}

parse_reason() {
  local CLEAN="$1"
  echo "$CLEAN" | jq -r '.reason // empty' 2>/dev/null
}

# --- Nudge: block the stop ---
nudge() {
  local VERDICT="$1"
  local REASON="$2"
  local NEW_COUNT=$((CURRENT_COUNT + 1))

  echo "$NEW_COUNT" > "$COUNTER_FILE"
  log "Nudge $NEW_COUNT/$MAX_NUDGES ($VERDICT): $REASON"

  local NUDGE_REASON
  case "$VERDICT" in
    PREMATURE)
      NUDGE_REASON="You stopped before completing the task. Remaining work: ${REASON}. Please continue."
      ;;
    UNCERTAIN)
      NUDGE_REASON="It's unclear whether the task is complete. Ask the user if there's anything else they need before stopping."
      ;;
    *)
      NUDGE_REASON="The stop monitor detected you may have stopped prematurely. ${REASON}. Please continue or ask the user."
      ;;
  esac

  local ESC_REASON=$(echo "$NUDGE_REASON" | sed 's/"/\\"/g')
  local ESC_MSG=$(echo "[Nanny] Nudge $NEW_COUNT/$MAX_NUDGES: $REASON" | sed 's/"/\\"/g')

  jq -n \
    --arg reason "$NUDGE_REASON" \
    --arg msg "[Nanny] Nudge $NEW_COUNT/$MAX_NUDGES: $REASON" \
    '{
      "decision": "block",
      "reason": $reason,
      "systemMessage": $msg
    }'
}

# =====================
# MAIN EVALUATION FLOW
# =====================

log "Evaluating stop. count=$CURRENT_COUNT/$MAX_NUDGES stop_hook_active=$STOP_HOOK_ACTIVE"

# --- First pass: standard evaluation ---
PROMPT_FILE=$(build_prompt "$LAST_USER_MSGS" "$TASK_INFO" "$LAST_ASST_MSG" "")
RESULT=$(call_opus "$PROMPT_FILE")
rm -f "$PROMPT_FILE"

VERDICT=$(parse_verdict "$RESULT")
REASON=$(parse_reason "$RESULT")

log "First pass: verdict=$VERDICT reason=$REASON"

# --- Handle verdict ---
case "$VERDICT" in
  COMPLETE)
    log "COMPLETE: $REASON"
    jq -n --arg msg "[Nanny] COMPLETE: $REASON" '{"systemMessage": $msg}'
    exit 0
    ;;

  PREMATURE)
    nudge "PREMATURE" "$REASON"
    exit 0
    ;;

  UNCERTAIN)
    # --- Tier 3: Enriched re-evaluation ---
    log "UNCERTAIN — gathering enriched context for second pass..."

    EXTRA=""

    # Git diff (what work was actually done)
    if [ -n "$CWD" ] && [ -d "$CWD/.git" ]; then
      GIT_DIFF=$(cd "$CWD" && git diff --stat 2>/dev/null | head -c 1000)
      if [ -n "$GIT_DIFF" ]; then
        EXTRA="${EXTRA}\n--- Git diff --stat (work done) ---\n${GIT_DIFF}"
      fi
    fi

    # Active plan file
    PLAN_DIR="$HOME/.claude/plans"
    if [ -d "$PLAN_DIR" ]; then
      LATEST_PLAN=$(ls -t "$PLAN_DIR"/*.md 2>/dev/null | head -1)
      if [ -n "$LATEST_PLAN" ]; then
        PLAN_CONTENT=$(head -c 2000 "$LATEST_PLAN" 2>/dev/null)
        EXTRA="${EXTRA}\n--- Active plan file ---\n${PLAN_CONTENT}"
      fi
    fi

    # Deeper transcript (last 10 user messages)
    DEEP_USER_MSGS=""
    if [ -f "$TRANSCRIPT_PATH" ]; then
      DEEP_USER_MSGS=$(grep '"role":"user"' "$TRANSCRIPT_PATH" 2>/dev/null \
        | jq -r 'select(.message.content | type == "string") | .message.content' 2>/dev/null \
        | tail -10 | head -c 3000)
    fi

    EXTRA="${EXTRA}\n--- Extended user message history ---\n${DEEP_USER_MSGS}"

    PROMPT_FILE2=$(build_prompt "$DEEP_USER_MSGS" "$TASK_INFO" "$LAST_ASST_MSG" "$(echo -e "$EXTRA")")
    RESULT2=$(call_opus "$PROMPT_FILE2")
    rm -f "$PROMPT_FILE2"

    VERDICT2=$(parse_verdict "$RESULT2")
    REASON2=$(parse_reason "$RESULT2")

    log "Second pass (enriched): verdict=$VERDICT2 reason=$REASON2"

    case "$VERDICT2" in
      COMPLETE)
        log "Enriched eval: COMPLETE: $REASON2"
        jq -n --arg msg "[Nanny] COMPLETE (enriched): $REASON2" '{"systemMessage": $msg}'
        exit 0
        ;;
      PREMATURE)
        nudge "PREMATURE" "$REASON2"
        exit 0
        ;;
      *)
        # Still UNCERTAIN or failed — nudge with "ask the user"
        nudge "UNCERTAIN" "${REASON2:-Scope is ambiguous after enriched evaluation}"
        exit 0
        ;;
    esac
    ;;

  *)
    # --- Opus failure: retry once, then assume PREMATURE ---
    log "Opus returned no verdict. Retrying..."

    PROMPT_FILE_RETRY=$(build_prompt "$LAST_USER_MSGS" "$TASK_INFO" "$LAST_ASST_MSG" "")
    RESULT_RETRY=$(call_opus "$PROMPT_FILE_RETRY")
    rm -f "$PROMPT_FILE_RETRY"

    VERDICT_RETRY=$(parse_verdict "$RESULT_RETRY")
    REASON_RETRY=$(parse_reason "$RESULT_RETRY")

    log "Retry: verdict=$VERDICT_RETRY reason=$REASON_RETRY"

    case "$VERDICT_RETRY" in
      COMPLETE)
        log "Retry: COMPLETE: $REASON_RETRY"
        jq -n --arg msg "[Nanny] COMPLETE (retry): $REASON_RETRY" '{"systemMessage": $msg}'
        exit 0
        ;;
      PREMATURE)
        nudge "PREMATURE" "$REASON_RETRY"
        exit 0
        ;;
      UNCERTAIN)
        nudge "UNCERTAIN" "${REASON_RETRY:-Could not determine completion status}"
        exit 0
        ;;
      *)
        # Second failure — assume premature
        log "Opus failed twice. Assuming PREMATURE."
        nudge "PREMATURE" "Opus evaluation failed. Assuming work remains — please continue or confirm completion."
        exit 0
        ;;
    esac
    ;;
esac
