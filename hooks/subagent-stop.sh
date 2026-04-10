#!/bin/bash
# SubagentStop hook - runs when a Task subagent finishes.
#
# Responsibility: track per-task state during parallel sprint execution.
# When `/autopilot-sprint` spawns N parallel subagents via worktree isolation,
# each one writes its final status to a shared state file so the orchestrator
# can report a consolidated summary at the end.
#
# The hook is intentionally minimal: the orchestrator (Claude running
# /autopilot-sprint) reads subagent results directly from the Task tool's
# return value, so this hook only exists for observability.
#
# Exit 0 = allow the subagent to stop.

# Read hook input from stdin (not used for now, but kept for future extension).
HOOK_INPUT=$(cat 2>/dev/null || true)

# Only act when autopilot is active.
if [[ ! -f "$HOME/.claude/.autopilot-enabled" ]]; then
  exit 0
fi

# Append a minimal log line if the sprint state file exists.
SPRINT_LOG="$HOME/.claude/.autopilot-sprint.log"
if [[ -f "$HOME/.claude/.autopilot-sprint-active" ]]; then
  # Portable timestamp: date -u works on both BSD and GNU.
  TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
  printf '[%s] subagent_stop session=%s\n' "$TS" "$SESSION_ID" >> "$SPRINT_LOG"
fi

exit 0
