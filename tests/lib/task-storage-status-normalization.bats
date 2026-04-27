#!/usr/bin/env bats
# Tests for canonical status normalization at the task-storage adapter layer.
#
# Canonical vocabulary: ready | in_progress | done
#
# Each provider must expose a `task_storage_<provider>_status_map` function
# that echoes a JSON object mapping its native status values to the canonical
# ones, e.g.:
#   { "To Do": "ready", "In Progress": "in_progress", "Done": "done" }
#
# The adapter exposes:
#   normalize_status_value <provider> <native_value>      -> echoes canonical (or native if no mapping)
#   denormalize_status_value <provider> <canonical_value> -> echoes native (or canonical if no mapping)
#
# task_storage_list and task_storage_fetch run their output through
# normalize on the way out. task_storage_update_status accepts canonical
# values and translates to native before calling the provider.

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

# ---------- status_map functions exist for all providers ----------

@test "backlog provider exposes status_map" {
  source "$LIB_DIR/task-storage-providers/backlog.sh"
  run task_storage_backlog_status_map
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.["To Do"] == "ready"' >/dev/null
  echo "$output" | jq -e '.["In Progress"] == "in_progress"' >/dev/null
  echo "$output" | jq -e '.["Done"] == "done"' >/dev/null
}

@test "local-file provider exposes status_map (identity for canonical values)" {
  source "$LIB_DIR/task-storage-providers/local-file.sh"
  run task_storage_local_file_status_map
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == "ready"' >/dev/null
  echo "$output" | jq -e '.in_progress == "in_progress"' >/dev/null
  echo "$output" | jq -e '.done == "done"' >/dev/null
}

@test "chat-paste provider exposes status_map (identity)" {
  source "$LIB_DIR/task-storage-providers/chat-paste.sh"
  run task_storage_chat_paste_status_map
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == "ready"' >/dev/null
}

@test "jira provider exposes status_map (config-aware defaults)" {
  source "$LIB_DIR/task-storage-providers/jira.sh"
  run task_storage_jira_status_map
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.["To Do"] == "ready"' >/dev/null
  echo "$output" | jq -e '.["In Progress"] == "in_progress"' >/dev/null
  echo "$output" | jq -e '.["Done"] == "done"' >/dev/null
}

@test "linear provider exposes status_map" {
  source "$LIB_DIR/task-storage-providers/linear.sh"
  run task_storage_linear_status_map
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.["Todo"] == "ready"' >/dev/null
  echo "$output" | jq -e '.["In Progress"] == "in_progress"' >/dev/null
  echo "$output" | jq -e '.["Done"] == "done"' >/dev/null
}

@test "notion provider exposes status_map" {
  source "$LIB_DIR/task-storage-providers/notion.sh"
  run task_storage_notion_status_map
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.["Ready"] == "ready"' >/dev/null
  echo "$output" | jq -e '.["In Progress"] == "in_progress"' >/dev/null
  echo "$output" | jq -e '.["Done"] == "done"' >/dev/null
}

# ---------- normalize_status_value / denormalize_status_value ----------

@test "normalize_status_value: backlog 'To Do' -> 'ready'" {
  run normalize_status_value backlog "To Do"
  [ "$status" -eq 0 ]
  [ "$output" = "ready" ]
}

@test "normalize_status_value: backlog 'In Progress' -> 'in_progress'" {
  run normalize_status_value backlog "In Progress"
  [ "$status" -eq 0 ]
  [ "$output" = "in_progress" ]
}

@test "normalize_status_value: backlog 'Done' -> 'done'" {
  run normalize_status_value backlog "Done"
  [ "$status" -eq 0 ]
  [ "$output" = "done" ]
}

@test "normalize_status_value: backlog already-canonical 'ready' passes through" {
  run normalize_status_value backlog "ready"
  [ "$status" -eq 0 ]
  [ "$output" = "ready" ]
}

@test "normalize_status_value: linear 'Todo' -> 'ready'" {
  run normalize_status_value linear "Todo"
  [ "$status" -eq 0 ]
  [ "$output" = "ready" ]
}

@test "normalize_status_value: notion 'Ready' -> 'ready'" {
  run normalize_status_value notion "Ready"
  [ "$status" -eq 0 ]
  [ "$output" = "ready" ]
}

@test "normalize_status_value: unknown value passes through unchanged" {
  run normalize_status_value backlog "Mystery"
  [ "$status" -eq 0 ]
  [ "$output" = "Mystery" ]
}

@test "denormalize_status_value: backlog 'ready' -> 'To Do'" {
  run denormalize_status_value backlog "ready"
  [ "$status" -eq 0 ]
  [ "$output" = "To Do" ]
}

@test "denormalize_status_value: backlog 'in_progress' -> 'In Progress'" {
  run denormalize_status_value backlog "in_progress"
  [ "$status" -eq 0 ]
  [ "$output" = "In Progress" ]
}

@test "denormalize_status_value: backlog 'done' -> 'Done'" {
  run denormalize_status_value backlog "done"
  [ "$status" -eq 0 ]
  [ "$output" = "Done" ]
}

@test "denormalize_status_value: linear 'ready' -> 'Todo'" {
  run denormalize_status_value linear "ready"
  [ "$status" -eq 0 ]
  [ "$output" = "Todo" ]
}

@test "denormalize_status_value: round-trip backlog ready" {
  native="$(denormalize_status_value backlog ready)"
  back="$(normalize_status_value backlog "$native")"
  [ "$back" = "ready" ]
}

@test "denormalize_status_value: round-trip linear in_progress" {
  native="$(denormalize_status_value linear in_progress)"
  back="$(normalize_status_value linear "$native")"
  [ "$back" = "in_progress" ]
}

@test "denormalize_status_value: round-trip notion done" {
  native="$(denormalize_status_value notion done)"
  back="$(normalize_status_value notion "$native")"
  [ "$back" = "done" ]
}
