#!/bin/bash
# SessionStart hook - sprint context injection
#
# Writes sprint-context.md at the worktree root before Claude starts
# working on a task. Parallel subagents each get the same context.
#
# Reads the active task ref from ~/.claude/.autopilot-active-task.json.
# If no active task, writes a minimal context with project rules only.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
CONTEXT_FILE="sprint-context.md"

# Source libraries for task fetching
source "$PLUGIN_ROOT/lib/config.sh" 2>/dev/null
source "$PLUGIN_ROOT/lib/task-storage-adapter.sh" 2>/dev/null

# Read the active task ref
ACTIVE_TASK_FILE="$HOME/.claude/.autopilot-active-task.json"
ACTIVE_TASK=""
if [[ -f "$ACTIVE_TASK_FILE" ]]; then
  ACTIVE_TASK="$(jq -r '.active_task // ""' "$ACTIVE_TASK_FILE" 2>/dev/null)"
  # Cap ref length to prevent abuse from tampered state files
  ACTIVE_TASK="${ACTIVE_TASK:0:128}"
fi

# Detect project name from directory or config; sanitize to safe chars
PROJECT_NAME="$(basename "$(pwd)")"
if command -v config_get &>/dev/null; then
  configured_name="$(config_get 'project_name' 2>/dev/null)"
  [[ -n "$configured_name" ]] && PROJECT_NAME="$configured_name"
fi
PROJECT_NAME="$(printf '%s' "$PROJECT_NAME" | tr -cd 'a-zA-Z0-9 _.-')"

# Write the context file
{
  echo "# Sprint Context"
  echo ""
  echo "## Project"
  echo ""
  echo "**Project:** ${PROJECT_NAME}"
  echo ""

  # If we have CLAUDE.md or .claude/CLAUDE.md, reference it
  if [[ -f "CLAUDE.md" ]]; then
    echo "**Project rules:** see \`CLAUDE.md\` in repo root"
  elif [[ -f ".claude/CLAUDE.md" ]]; then
    echo "**Project rules:** see \`.claude/CLAUDE.md\`"
  fi
  echo ""

  if [[ -n "$ACTIVE_TASK" ]]; then
    # Fetch task details
    TASK_JSON="$(task_storage_fetch "$ACTIVE_TASK" 2>/dev/null)"

    if [[ $? -eq 0 ]] && [[ -n "$TASK_JSON" ]]; then
      TASK_TITLE="$(echo "$TASK_JSON" | jq -r '.title // ""' 2>/dev/null)"
      TASK_DESC="$(echo "$TASK_JSON" | jq -r '.description // ""' 2>/dev/null)"
      TASK_PRIORITY="$(echo "$TASK_JSON" | jq -r '.priority // ""' 2>/dev/null)"

      echo "## Current Task"
      echo ""
      echo "**ID:** ${ACTIVE_TASK}"
      echo "**Title:** ${TASK_TITLE}"
      [[ -n "$TASK_PRIORITY" ]] && echo "**Priority:** ${TASK_PRIORITY}"
      echo ""

      if [[ -n "$TASK_DESC" ]]; then
        echo "### Description"
        echo ""
        echo '```task-description'
        echo "$TASK_DESC"
        echo '```'
        echo ""
      fi

      # Acceptance criteria (fenced to prevent prompt injection from task content)
      CRITERIA_COUNT="$(echo "$TASK_JSON" | jq -r '.acceptanceCriteria | length' 2>/dev/null)"
      if [[ "$CRITERIA_COUNT" -gt 0 ]] 2>/dev/null; then
        echo "### Acceptance Criteria"
        echo ""
        echo '```task-criteria'
        i=0
        while [[ $i -lt $CRITERIA_COUNT ]]; do
          CRITERION="$(echo "$TASK_JSON" | jq -r ".acceptanceCriteria[$i]" 2>/dev/null)"
          echo "- [ ] ${CRITERION}"
          i=$((i + 1))
        done
        echo '```'
        echo ""
      fi

      echo "## References"
      echo ""
      echo "- Task ref: \`${ACTIVE_TASK}\`"
      [[ -f "CONTRIBUTING.md" ]] && echo "- Contributing guide: \`CONTRIBUTING.md\`"
      [[ -f "README.md" ]] && echo "- Project README: \`README.md\`"
    fi
  fi
} > "$CONTEXT_FILE"

exit 0
