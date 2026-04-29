#!/usr/bin/env bats
# Validation contract for task_storage_list:
#   - 0 or 1 positional arg
#   - if 1, must be in canonical vocabulary: ready | in_progress | done | ""

load '../helpers/test_helper'

setup() {
  setup_isolated_tmpdir
  mkdir -p backlog/tasks
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

@test "task_storage_list accepts no argument" {
  run task_storage_list
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts empty string as no filter" {
  run task_storage_list ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts 'ready'" {
  run task_storage_list ready
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts 'in_progress'" {
  run task_storage_list in_progress
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts 'done'" {
  run task_storage_list done
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list rejects unknown status with exit 1" {
  run task_storage_list pizza
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "invalid status 'pizza'"
}

@test "task_storage_list rejects 2+ arguments with exit 1" {
  run task_storage_list ready extra
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "too many arguments"
}

@test "task_storage_list error message lists canonical statuses" {
  run task_storage_list pizza
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ready"
  echo "$output" | grep -q "in_progress"
  echo "$output" | grep -q "done"
}
