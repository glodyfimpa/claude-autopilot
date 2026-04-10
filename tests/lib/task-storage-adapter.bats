#!/usr/bin/env bats
# Tests for lib/task-storage-adapter.sh
#
# Responsibility: dispatch task operations (fetch, list, create, updateStatus)
# to the configured task storage provider. The interface is stable across
# providers; the adapter just routes calls by provider name.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/task-storage-adapter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- task_storage_validate_provider --------

@test "task_storage_validate_provider accepts known providers" {
  run task_storage_validate_provider "local-file"
  assert_equal "0" "$status"
  run task_storage_validate_provider "chat-paste"
  assert_equal "0" "$status"
  run task_storage_validate_provider "notion"
  assert_equal "0" "$status"
  run task_storage_validate_provider "jira"
  assert_equal "0" "$status"
  run task_storage_validate_provider "linear"
  assert_equal "0" "$status"
  run task_storage_validate_provider "backlog"
  assert_equal "0" "$status"
}

@test "task_storage_validate_provider rejects unknown providers" {
  run task_storage_validate_provider "sqlite"
  assert_equal "1" "$status"
  run task_storage_validate_provider ""
  assert_equal "1" "$status"
}

# -------- task_storage_fetch --------

@test "task_storage_fetch fails when no provider is configured" {
  config_init
  run task_storage_fetch "task-1"
  assert_equal "1" "$status"
  assert_contains "$output" "no task_storage provider configured"
}

@test "task_storage_fetch delegates to local-file provider and returns JSON" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  cat > tasks/task-1.md <<'EOF'
---
id: task-1
title: Add login page
status: ready
---

## Description
Users need to log in via email and password.

## Acceptance Criteria
- Form validates email
- Error message shown on invalid credentials
- Redirect to dashboard on success
EOF
  run task_storage_fetch "tasks/task-1.md"
  assert_equal "0" "$status"
  # Parse the returned JSON
  local title criteria_count
  title="$(echo "$output" | jq -r '.title')"
  criteria_count="$(echo "$output" | jq -r '.acceptanceCriteria | length')"
  assert_equal "Add login page" "$title"
  assert_equal "3" "$criteria_count"
}

@test "task_storage_fetch returns stub message for non-local providers" {
  config_init
  config_set "task_storage.provider" "notion"
  run task_storage_fetch "abc123"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

# -------- task_storage_update_status --------

@test "task_storage_update_status updates the status field in a local-file task" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  cat > tasks/task-1.md <<'EOF'
---
id: task-1
title: Add login page
status: ready
---
body
EOF
  run task_storage_update_status "tasks/task-1.md" "in_progress"
  assert_equal "0" "$status"
  grep -q '^status: in_progress' tasks/task-1.md
}

# -------- task_storage_create --------

@test "task_storage_create writes a new task file with a deterministic id" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  run task_storage_create "Setup CI pipeline" "Add GitHub Actions workflow" "workflow runs on push,green on main"
  assert_equal "0" "$status"
  # A task file should exist under tasks/
  local files
  files=$(ls tasks/ | wc -l | tr -d ' ')
  assert_equal "1" "$files"
  local file
  file="$(ls tasks/)"
  grep -q "title: Setup CI pipeline" "tasks/$file"
  grep -q "status: ready" "tasks/$file"
}

# -------- task_storage_list --------

@test "task_storage_list returns all local-file tasks as a JSON array" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  cat > tasks/a.md <<'EOF'
---
id: a
title: First task
status: ready
---
body
EOF
  cat > tasks/b.md <<'EOF'
---
id: b
title: Second task
status: done
---
body
EOF
  run task_storage_list
  assert_equal "0" "$status"
  local count
  count="$(echo "$output" | jq 'length')"
  assert_equal "2" "$count"
}
