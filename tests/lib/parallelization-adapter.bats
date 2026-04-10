#!/usr/bin/env bats
# Tests for lib/parallelization-adapter.sh
#
# Responsibility: decide how a batch of tasks should be executed (sequential
# or parallel), respecting:
#   - strategy: adaptive | always-sequential | always-parallel
#   - max_concurrency: hard cap
#   - dependency hints: tasks sharing a module path should not run concurrently
#
# Input: JSON array of tasks (each enriched with a `complexity` object from
# the complexity-estimator).
#
# Output: JSON
#   { strategy: "sequential"|"parallel",
#     maxConcurrency: <int>,
#     groups: [[task_id,...], [task_id,...], ...] }
#
# Each group runs sequentially internally; groups run in parallel up to
# maxConcurrency. For always-sequential strategy, each task is its own group
# and maxConcurrency is 1.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/parallelization-adapter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# Helper to build a task JSON with id and complexity tier.
_task() {
  local id="$1" tier="$2"
  local files_json="${3:-[]}"
  jq -n --arg id "$id" --arg tier "$tier" --argjson files "$files_json" \
    '{id:$id, title:$id, description:"", status:"ready", parent:null,
      acceptanceCriteria:[],
      complexity:{tier:$tier, score:10, signals:{criteriaCount:1, descriptionWords:5}},
      files:$files}'
}

_tasks_array() {
  printf '%s\n' "$@" | jq -s '.'
}

# -------- always-sequential strategy --------

@test "plan_execution respects always-sequential strategy" {
  config_init
  config_set "parallelization.strategy" "always-sequential"
  local a b c
  a="$(_task t1 standard)"
  b="$(_task t2 standard)"
  c="$(_task t3 standard)"
  local tasks
  tasks="$(_tasks_array "$a" "$b" "$c")"

  run plan_execution "$tasks"
  assert_equal "0" "$status"
  local strategy groups_len max
  strategy="$(echo "$output" | jq -r '.strategy')"
  groups_len="$(echo "$output" | jq -r '.groups | length')"
  max="$(echo "$output" | jq -r '.maxConcurrency')"
  assert_equal "sequential" "$strategy"
  assert_equal "3" "$groups_len"
  assert_equal "1" "$max"
}

# -------- always-parallel strategy --------

@test "plan_execution respects always-parallel up to max_concurrency" {
  config_init
  config_set "parallelization.strategy" "always-parallel"
  config_set "parallelization.max_concurrency" "2"
  local a b c d
  a="$(_task t1 standard)"
  b="$(_task t2 standard)"
  c="$(_task t3 standard)"
  d="$(_task t4 standard)"
  local tasks
  tasks="$(_tasks_array "$a" "$b" "$c" "$d")"

  run plan_execution "$tasks"
  assert_equal "0" "$status"
  local strategy max groups_len
  strategy="$(echo "$output" | jq -r '.strategy')"
  max="$(echo "$output" | jq -r '.maxConcurrency')"
  groups_len="$(echo "$output" | jq -r '.groups | length')"
  assert_equal "parallel" "$strategy"
  assert_equal "2" "$max"
  # Each group still holds exactly one task; concurrency is the runner's concern.
  assert_equal "4" "$groups_len"
}

# -------- adaptive strategy --------

@test "plan_execution adaptive: all trivial tasks go sequential" {
  config_init
  config_set "parallelization.strategy" "adaptive"
  config_set "parallelization.max_concurrency" "3"
  local a b
  a="$(_task t1 trivial)"
  b="$(_task t2 trivial)"
  local tasks
  tasks="$(_tasks_array "$a" "$b")"

  run plan_execution "$tasks"
  assert_equal "0" "$status"
  local strategy
  strategy="$(echo "$output" | jq -r '.strategy')"
  assert_equal "sequential" "$strategy"
}

@test "plan_execution adaptive: complex tasks force sequential" {
  config_init
  config_set "parallelization.strategy" "adaptive"
  config_set "parallelization.max_concurrency" "3"
  local a b c
  a="$(_task t1 standard)"
  b="$(_task t2 complex)"
  c="$(_task t3 standard)"
  local tasks
  tasks="$(_tasks_array "$a" "$b" "$c")"

  run plan_execution "$tasks"
  assert_equal "0" "$status"
  local strategy
  strategy="$(echo "$output" | jq -r '.strategy')"
  assert_equal "sequential" "$strategy"
}

@test "plan_execution adaptive: all-standard batch runs parallel" {
  config_init
  config_set "parallelization.strategy" "adaptive"
  config_set "parallelization.max_concurrency" "3"
  local a b c
  a="$(_task t1 standard)"
  b="$(_task t2 standard)"
  c="$(_task t3 standard)"
  local tasks
  tasks="$(_tasks_array "$a" "$b" "$c")"

  run plan_execution "$tasks"
  assert_equal "0" "$status"
  local strategy
  strategy="$(echo "$output" | jq -r '.strategy')"
  assert_equal "parallel" "$strategy"
}

# -------- dependency detection via shared file paths --------

@test "plan_execution groups tasks that touch the same files" {
  config_init
  config_set "parallelization.strategy" "always-parallel"
  config_set "parallelization.max_concurrency" "3"
  local a b c
  a="$(_task t1 standard '["src/auth.ts"]')"
  b="$(_task t2 standard '["src/auth.ts", "src/login.ts"]')"
  c="$(_task t3 standard '["src/unrelated.ts"]')"
  local tasks
  tasks="$(_tasks_array "$a" "$b" "$c")"

  run plan_execution "$tasks"
  assert_equal "0" "$status"
  # t1 and t2 share src/auth.ts -> same group.
  # t3 is independent -> its own group.
  local groups_len first_group_len
  groups_len="$(echo "$output" | jq -r '.groups | length')"
  first_group_len="$(echo "$output" | jq -r '.groups[0] | length')"
  assert_equal "2" "$groups_len"
  # Group containing t1 must also contain t2.
  local t1_group
  t1_group="$(echo "$output" | jq -r '.groups | map(select(index("t1") != null)) | .[0] | length')"
  assert_equal "2" "$t1_group"
}

# -------- input validation --------

@test "plan_execution fails on invalid JSON" {
  config_init
  config_set "parallelization.strategy" "adaptive"
  run plan_execution "not json"
  assert_equal "1" "$status"
  assert_contains "$output" "invalid"
}

@test "plan_execution returns empty plan for empty task array" {
  config_init
  config_set "parallelization.strategy" "adaptive"
  run plan_execution "[]"
  assert_equal "0" "$status"
  local groups_len
  groups_len="$(echo "$output" | jq -r '.groups | length')"
  assert_equal "0" "$groups_len"
}
