#!/bin/bash
# Stop hook - deterministic quality gate
# Exit 0 = Claude can stop
# JSON output with "decision":"block" = Claude must continue working
# JSON output with "decision":"approve" = Claude can stop (with optional systemMessage)

# 1. Read input from stdin
HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')

# 2. Check if autopilot is active
if [[ ! -f "$HOME/.claude/.autopilot-enabled" ]]; then
  exit 0
fi

# 3. Ralph Loop coexistence: if Ralph is active in THIS session, defer
if [[ -f ".claude/ralph-loop.local.md" ]]; then
  RALPH_SESSION=$(grep '^session_id:' .claude/ralph-loop.local.md 2>/dev/null | sed 's/session_id: *//')
  if [[ "$RALPH_SESSION" == "$SESSION_ID" ]]; then
    exit 0  # Ralph owns this session
  fi
fi

# 4. Check per-session iterations (max 5)
STATE_FILE="$HOME/.claude/.autopilot-${SESSION_ID}.json"
if [[ -f "$STATE_FILE" ]]; then
  COUNT=$(jq -r '.iterations // 0' "$STATE_FILE")
else
  COUNT=0
fi

if [[ "$COUNT" -ge 5 ]]; then
  # Limit reached: let Claude stop with a message
  echo '{"decision":"approve","systemMessage":"AUTOPILOT: 5-iteration limit reached. Gates still failing. Explain the problem to the user and ask for help."}'
  rm -f "$STATE_FILE"
  exit 0
fi

# 5. Check if there are changes to verify
CHANGES=$(git diff --name-only 2>/dev/null)
STAGED=$(git diff --cached --name-only 2>/dev/null)
if [[ -z "$CHANGES" ]] && [[ -z "$STAGED" ]]; then
  rm -f "$STATE_FILE"
  exit 0  # No changes, nothing to verify
fi

# 6. Detect stack
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_JSON=$(bash "$SCRIPT_DIR/detect-stack.sh")
STACK=$(echo "$STACK_JSON" | jq -r '.stack')

if [[ "$STACK" == "unknown" ]]; then
  # Unrecognized stack: pass without gates
  exit 0
fi

# 7. Run gates sequentially
ERRORS=""

# Gate: Test
TEST_CMD=$(echo "$STACK_JSON" | jq -r '.test')
if [[ -n "$TEST_CMD" ]]; then
  TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
  if [[ $? -ne 0 ]]; then
    ERRORS="${ERRORS}TESTS FAILED:\n${TEST_OUTPUT}\n\n"
  fi
fi

# Gate: Lint
LINT_CMD=$(echo "$STACK_JSON" | jq -r '.lint')
if [[ -n "$LINT_CMD" ]]; then
  LINT_OUTPUT=$(eval "$LINT_CMD" 2>&1)
  if [[ $? -ne 0 ]]; then
    ERRORS="${ERRORS}LINT FAILED:\n${LINT_OUTPUT}\n\n"
  fi
fi

# Gate: Types
TYPES_CMD=$(echo "$STACK_JSON" | jq -r '.types')
if [[ -n "$TYPES_CMD" ]]; then
  TYPES_OUTPUT=$(eval "$TYPES_CMD" 2>&1)
  if [[ $? -ne 0 ]]; then
    ERRORS="${ERRORS}TYPE CHECK FAILED:\n${TYPES_OUTPUT}\n\n"
  fi
fi

# Gate: Build
BUILD_CMD=$(echo "$STACK_JSON" | jq -r '.build')
if [[ -n "$BUILD_CMD" ]]; then
  BUILD_OUTPUT=$(eval "$BUILD_CMD" 2>&1)
  if [[ $? -ne 0 ]]; then
    ERRORS="${ERRORS}BUILD FAILED:\n${BUILD_OUTPUT}\n\n"
  fi
fi

# 8. Decision
if [[ -n "$ERRORS" ]]; then
  # Increment counter
  NEW_COUNT=$((COUNT + 1))
  echo "{\"iterations\": $NEW_COUNT}" > "$STATE_FILE"

  # Truncate errors to avoid JSON issues (max 100 lines)
  TRUNCATED_ERRORS=$(echo -e "$ERRORS" | head -100)

  # Output block decision with errors in systemMessage
  # Using jq to safely encode the error output as JSON
  jq -n \
    --arg reason "Quality gates failed. Fix the errors and retry." \
    --arg msg "AUTOPILOT iteration $NEW_COUNT/5. Errors:
$TRUNCATED_ERRORS" \
    '{"decision":"block","reason":$reason,"systemMessage":$msg}'
  exit 0
fi

# All gates passed: reset iteration counter.
rm -f "$STATE_FILE"

# Task-complete marker: the skill writes this file when every acceptance
# criterion is satisfied and security review is clean. Its presence tells the
# outer loop (/autopilot-task) to proceed with commit + push + PR.
TASK_COMPLETE_MARKER="$HOME/.claude/.autopilot-task-complete"
if [[ -f "$TASK_COMPLETE_MARKER" ]]; then
  rm -f "$TASK_COMPLETE_MARKER"
  echo '{"decision":"approve","systemMessage":"AUTOPILOT: Task complete. All gates passed AND acceptance criteria satisfied. The outer loop will now commit, push, and open the PR via the configured pr_target provider."}'
  exit 0
fi

# Gates passed but no task-complete marker: this is an intermediate iteration.
# The skill keeps working until all acceptance criteria are met and security
# review is clean; only then does it write the marker.
echo '{"decision":"approve","systemMessage":"AUTOPILOT: All quality gates passed (test, lint, types, build). If every acceptance criterion is now satisfied, run the security-reviewer subagent and then write the task-complete marker (touch ~/.claude/.autopilot-task-complete) so the outer loop can open the PR."}'
exit 0
