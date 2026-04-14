#!/usr/bin/env bats
# Tests for lib/task-storage-providers/backlog.sh
#
# The backlog provider reads tasks from the backlog/tasks/ directory,
# where files are named "task-ID - Title-slug.md" and use a richer
# YAML frontmatter than local-file (labels, dependencies, priority,
# parent_task_id, dates, acceptance criteria with checkboxes).

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/task-storage-adapter.sh"
  config_init
  config_set "task_storage.provider" "backlog"
}

teardown() {
  teardown_isolated_tmpdir
}

# Helper: create a backlog task file matching the real naming convention
_create_backlog_task() {
  local id="$1" title_slug="$2" status="${3:-To Do}" priority="${4:-medium}"
  local id_upper
  id_upper="$(echo "$id" | tr '[:lower:]' '[:upper:]')"
  local title
  title="$(echo "$title_slug" | tr '-' ' ')"
  mkdir -p backlog/tasks
  local file="backlog/tasks/${id} - ${title_slug}.md"
  printf '%s\n' "---" \
    "id: ${id_upper}" \
    "title: ${title}" \
    "status: ${status}" \
    "assignee: []" \
    "created_date: '2026-04-10 12:58'" \
    "labels:" \
    "  - test-label" \
    "dependencies: []" \
    "parent_task_id: TASK-1" \
    "priority: ${priority}" \
    "---" \
    "" \
    "## Description" \
    "" \
    "<!-- SECTION:DESCRIPTION:BEGIN -->" \
    "Test description for ${id}." \
    "<!-- SECTION:DESCRIPTION:END -->" \
    "" \
    "## Acceptance Criteria" \
    "<!-- AC:BEGIN -->" \
    "- [ ] #1 First criterion" \
    "- [ ] #2 Second criterion" \
    "- [ ] #3 Third criterion" \
    "<!-- AC:END -->" > "$file"
  printf '%s' "$file"
}

# -------- fetch --------

@test "backlog fetch returns JSON for a valid task ID" {
  _create_backlog_task "task-1.3" "SessionStart-hook"
  run task_storage_fetch "TASK-1.3"
  assert_equal "0" "$status"
  local title
  title="$(echo "$output" | jq -r '.title')"
  assert_equal "SessionStart hook" "$title"
}

@test "backlog fetch parses acceptance criteria from checkbox format" {
  _create_backlog_task "task-1.3" "SessionStart-hook"
  run task_storage_fetch "TASK-1.3"
  assert_equal "0" "$status"
  local count
  count="$(echo "$output" | jq -r '.acceptanceCriteria | length')"
  assert_equal "3" "$count"
}

@test "backlog fetch includes priority and parent fields" {
  _create_backlog_task "task-1.3" "SessionStart-hook" "To Do" "high"
  run task_storage_fetch "TASK-1.3"
  assert_equal "0" "$status"
  local priority parent
  priority="$(echo "$output" | jq -r '.priority')"
  parent="$(echo "$output" | jq -r '.parent')"
  assert_equal "high" "$priority"
  assert_equal "TASK-1" "$parent"
}

@test "backlog fetch normalizes status To Do to ready" {
  _create_backlog_task "task-1.3" "SessionStart-hook" "To Do"
  run task_storage_fetch "TASK-1.3"
  assert_equal "0" "$status"
  local task_status
  task_status="$(echo "$output" | jq -r '.status')"
  assert_equal "ready" "$task_status"
}

@test "backlog fetch fails with exit 1 for unknown task ID" {
  mkdir -p backlog/tasks
  run task_storage_fetch "TASK-999"
  assert_equal "1" "$status"
  assert_contains "$output" "not found"
}

@test "backlog fetch is case-insensitive on task ID" {
  _create_backlog_task "task-1.3" "SessionStart-hook"
  run task_storage_fetch "task-1.3"
  assert_equal "0" "$status"
  local title
  title="$(echo "$output" | jq -r '.title')"
  assert_equal "SessionStart hook" "$title"
}

# -------- update_status --------

@test "backlog update_status changes the status field in the file" {
  local file
  file="$(_create_backlog_task "task-1.3" "SessionStart-hook" "To Do")"
  run task_storage_update_status "TASK-1.3" "in_progress"
  assert_equal "0" "$status"
  grep -q '^status: In Progress' "$file"
}

@test "backlog update_status maps in_progress to In Progress" {
  local file
  file="$(_create_backlog_task "task-1.3" "SessionStart-hook" "To Do")"
  run task_storage_update_status "TASK-1.3" "in_progress"
  assert_equal "0" "$status"
  grep -q '^status: In Progress' "$file"
}

@test "backlog update_status maps done to Done" {
  local file
  file="$(_create_backlog_task "task-1.3" "SessionStart-hook" "To Do")"
  run task_storage_update_status "TASK-1.3" "done"
  assert_equal "0" "$status"
  grep -q '^status: Done' "$file"
}

@test "backlog update_status fails for unknown task" {
  mkdir -p backlog/tasks
  run task_storage_update_status "TASK-999" "done"
  assert_equal "1" "$status"
}

# -------- list --------

@test "backlog list returns all tasks as JSON array" {
  _create_backlog_task "task-1" "First-task"
  _create_backlog_task "task-2" "Second-task"
  run task_storage_list
  assert_equal "0" "$status"
  local count
  count="$(echo "$output" | jq 'length')"
  assert_equal "2" "$count"
}

@test "backlog list returns empty array when no tasks exist" {
  mkdir -p backlog/tasks
  run task_storage_list
  assert_equal "0" "$status"
  local count
  count="$(echo "$output" | jq 'length')"
  assert_equal "0" "$count"
}

@test "backlog list returns empty array when backlog dir missing" {
  run task_storage_list
  assert_equal "0" "$status"
  assert_equal "[]" "$output"
}

# -------- create --------

@test "backlog create writes a new task file under backlog/tasks" {
  run task_storage_create "New feature" "Build something" "criterion one,criterion two"
  assert_equal "0" "$status"
  local files
  files=$(ls backlog/tasks/ 2>/dev/null | wc -l | tr -d ' ')
  assert_equal "1" "$files"
  local file
  file="$(ls backlog/tasks/)"
  grep -q "title: New feature" "backlog/tasks/$file"
  grep -q "status: To Do" "backlog/tasks/$file"
}
