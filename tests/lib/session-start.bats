#!/usr/bin/env bats
# Tests for hooks/session-start.sh
#
# The SessionStart hook writes a sprint-context.md at the worktree root
# before Claude begins working on a task. It reads the active task ref
# from the autopilot state and produces context for the session.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  make_fake_git_repo
  # Source config so the hook can read pipeline settings
  source "$LIB_DIR/config.sh"
  config_init
  config_set "task_storage.provider" "backlog"

  # Create a sample backlog task
  mkdir -p backlog/tasks
  printf '%s\n' "---" \
    "id: TASK-1.3" \
    "title: SessionStart hook with sprint-context injection" \
    "status: In Progress" \
    "assignee: []" \
    "created_date: '2026-04-10 12:58'" \
    "labels:" \
    "  - hooks" \
    "dependencies: []" \
    "parent_task_id: TASK-1" \
    "priority: medium" \
    "---" \
    "" \
    "## Description" \
    "" \
    "<!-- SECTION:DESCRIPTION:BEGIN -->" \
    "Add a SessionStart hook that writes sprint-context.md." \
    "<!-- SECTION:DESCRIPTION:END -->" \
    "" \
    "## Acceptance Criteria" \
    "<!-- AC:BEGIN -->" \
    "- [ ] #1 First criterion" \
    "- [ ] #2 Second criterion" \
    "<!-- AC:END -->" > "backlog/tasks/task-1.3 - SessionStart-hook.md"
}

teardown() {
  teardown_isolated_tmpdir
}

# Helper: set active task ref in autopilot state
_set_active_task() {
  local task_ref="$1"
  mkdir -p "$HOME/.claude"
  echo "{\"active_task\": \"${task_ref}\"}" > "$HOME/.claude/.autopilot-active-task.json"
}

_clear_active_task() {
  rm -f "$HOME/.claude/.autopilot-active-task.json"
}

# -------- Active task --------

@test "session-start writes sprint-context.md when active task is set" {
  _set_active_task "TASK-1.3"
  run bash "$PLUGIN_ROOT/hooks/session-start.sh"
  assert_equal "0" "$status"
  assert_file_exists "sprint-context.md"
}

@test "sprint-context.md includes the task title" {
  _set_active_task "TASK-1.3"
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  grep -q "SessionStart hook with sprint-context injection" sprint-context.md
}

@test "sprint-context.md includes acceptance criteria" {
  _set_active_task "TASK-1.3"
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  grep -q "First criterion" sprint-context.md
  grep -q "Second criterion" sprint-context.md
}

@test "sprint-context.md includes a project summary section" {
  _set_active_task "TASK-1.3"
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  grep -qi "project" sprint-context.md
}

# -------- No active task --------

@test "session-start writes minimal context when no active task is set" {
  _clear_active_task
  run bash "$PLUGIN_ROOT/hooks/session-start.sh"
  assert_equal "0" "$status"
  assert_file_exists "sprint-context.md"
}

@test "minimal context does not include task-specific sections" {
  _clear_active_task
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  ! grep -q "Acceptance Criteria" sprint-context.md
}

# -------- Malformed task JSON --------

@test "session-start handles malformed active task JSON gracefully" {
  mkdir -p "$HOME/.claude"
  echo "not valid json" > "$HOME/.claude/.autopilot-active-task.json"
  run bash "$PLUGIN_ROOT/hooks/session-start.sh"
  assert_equal "0" "$status"
  assert_file_exists "sprint-context.md"
}

# -------- Active task file lifecycle (contract with autopilot-task command) --------

@test "active task JSON written by autopilot-task command is readable by session-start" {
  # Simulate what autopilot-task step 5 writes
  local task_ref="TASK-1.3"
  mkdir -p "$HOME/.claude"
  echo "{\"active_task\": \"$task_ref\"}" > "$HOME/.claude/.autopilot-active-task.json"

  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  grep -q "TASK-1.3" sprint-context.md
}

@test "active task JSON uses the key that session-start expects" {
  # session-start reads .active_task via jq — verify the field name matters
  mkdir -p "$HOME/.claude"
  echo '{"active_task": "TASK-1.3"}' > "$HOME/.claude/.autopilot-active-task.json"

  local ref
  ref="$(jq -r '.active_task // ""' "$HOME/.claude/.autopilot-active-task.json")"
  assert_equal "TASK-1.3" "$ref"
}

@test "removing active task file causes session-start to fall back to minimal context" {
  # Simulate step 5: write the file
  _set_active_task "TASK-1.3"
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  grep -q "TASK-1.3" sprint-context.md

  # Simulate step 9: remove the file
  _clear_active_task
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  ! grep -q "TASK-1.3" sprint-context.md
  ! grep -q "Acceptance Criteria" sprint-context.md
}

@test "active task file with empty ref produces minimal context" {
  mkdir -p "$HOME/.claude"
  echo '{"active_task": ""}' > "$HOME/.claude/.autopilot-active-task.json"
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  ! grep -q "Current Task" sprint-context.md
}

# -------- Overwrite behavior --------

@test "session-start overwrites existing sprint-context.md" {
  echo "old content" > sprint-context.md
  _set_active_task "TASK-1.3"
  bash "$PLUGIN_ROOT/hooks/session-start.sh"
  ! grep -q "old content" sprint-context.md
}
