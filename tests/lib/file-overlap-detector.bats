#!/usr/bin/env bats
# Tests for lib/file-overlap-detector.sh

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/file-overlap-detector.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- extract_files_from_text --------

@test "extract_files_from_text picks up backtick-quoted paths" {
  local bt=$'\x60'
  local input="modify ${bt}lib/wizard.sh${bt} and ${bt}commands/autopilot-task.md${bt}"
  run extract_files_from_text "$input"
  assert_equal "0" "$status"
  assert_contains "$output" "lib/wizard.sh"
  assert_contains "$output" "commands/autopilot-task.md"
}

@test "extract_files_from_text picks up bare paths with extensions" {
  run extract_files_from_text "edit lib/wizard.sh and add tests/lib/foo.bats"
  assert_equal "0" "$status"
  assert_contains "$output" "lib/wizard.sh"
  assert_contains "$output" "tests/lib/foo.bats"
}

@test "extract_files_from_text deduplicates repeated paths" {
  run extract_files_from_text "edit lib/wizard.sh, then edit lib/wizard.sh again"
  assert_equal "0" "$status"
  local count
  count=$(echo "$output" | grep -c "lib/wizard.sh" || true)
  assert_equal "1" "$count"
}

@test "extract_files_from_text returns empty on prose without paths" {
  run extract_files_from_text "Add a feature that does something"
  assert_equal "0" "$status"
  assert_equal "" "$output"
}

# -------- extract_files_from_task --------

@test "extract_files_from_task extracts paths from description and acceptanceCriteria" {
  local task='{"id":"T1","description":"modify lib/wizard.sh","acceptanceCriteria":["update commands/foo.md","add tests/lib/bar.bats"]}'
  run extract_files_from_task "$task"
  assert_equal "0" "$status"
  assert_contains "$output" "lib/wizard.sh"
  assert_contains "$output" "commands/foo.md"
  assert_contains "$output" "tests/lib/bar.bats"
}

# -------- compute_overlap --------

@test "compute_overlap reports hasOverlap=false when no shared files" {
  local tasks='[
    {"id":"T1","description":"modify lib/wizard.sh"},
    {"id":"T2","description":"modify lib/other.sh"}
  ]'
  run compute_overlap "$tasks"
  assert_equal "0" "$status"
  echo "$output" | jq -e '.hasOverlap == false' >/dev/null
  echo "$output" | jq -e '.overlaps | length == 0' >/dev/null
}

@test "compute_overlap detects a single shared file between two tasks" {
  local tasks='[
    {"id":"T1","description":"modify lib/wizard.sh and commands/a.md"},
    {"id":"T2","description":"modify lib/wizard.sh and commands/b.md"}
  ]'
  run compute_overlap "$tasks"
  assert_equal "0" "$status"
  echo "$output" | jq -e '.hasOverlap == true' >/dev/null
  local overlap_file
  overlap_file=$(echo "$output" | jq -r '.overlaps[0].file')
  assert_equal "lib/wizard.sh" "$overlap_file"
  echo "$output" | jq -e '.overlaps[0].tasks | length == 2' >/dev/null
}

@test "compute_overlap detects multiple shared files between three tasks" {
  local tasks='[
    {"id":"T1","description":"modify lib/wizard.sh and lib/foo.sh"},
    {"id":"T2","description":"modify lib/wizard.sh and lib/bar.sh"},
    {"id":"T3","description":"modify lib/foo.sh and lib/bar.sh"}
  ]'
  run compute_overlap "$tasks"
  assert_equal "0" "$status"
  echo "$output" | jq -e '.hasOverlap == true' >/dev/null
  echo "$output" | jq -e '.overlaps | length >= 2' >/dev/null
}

@test "compute_overlap byTask maps each task to its files" {
  local tasks='[
    {"id":"T1","description":"modify lib/wizard.sh"},
    {"id":"T2","description":"modify lib/wizard.sh and commands/b.md"}
  ]'
  run compute_overlap "$tasks"
  assert_equal "0" "$status"
  local t1_files t2_count
  t1_files=$(echo "$output" | jq -r '.byTask.T1[0]')
  assert_equal "lib/wizard.sh" "$t1_files"
  t2_count=$(echo "$output" | jq '.byTask.T2 | length')
  assert_equal "2" "$t2_count"
}

# -------- group_by_overlap --------

@test "group_by_overlap returns one singleton per task when no overlap" {
  local tasks='[
    {"id":"T1","description":"modify lib/wizard.sh"},
    {"id":"T2","description":"modify lib/other.sh"}
  ]'
  run group_by_overlap "$tasks"
  assert_equal "0" "$status"
  echo "$output" | jq -e '.groups | length == 2' >/dev/null
}

@test "group_by_overlap merges two tasks sharing a file into one group" {
  local tasks='[
    {"id":"T1","description":"modify lib/wizard.sh"},
    {"id":"T2","description":"modify lib/wizard.sh"}
  ]'
  run group_by_overlap "$tasks"
  assert_equal "0" "$status"
  echo "$output" | jq -e '.groups | length == 1' >/dev/null
  echo "$output" | jq -e '.groups[0] | length == 2' >/dev/null
}

@test "group_by_overlap merges transitively (T1->T2 via fileA, T2->T3 via fileB)" {
  local tasks='[
    {"id":"T1","description":"modify lib/foo.sh"},
    {"id":"T2","description":"modify lib/foo.sh and lib/bar.sh"},
    {"id":"T3","description":"modify lib/bar.sh"}
  ]'
  run group_by_overlap "$tasks"
  assert_equal "0" "$status"
  echo "$output" | jq -e '.groups | length == 1' >/dev/null
  echo "$output" | jq -e '.groups[0] | length == 3' >/dev/null
}

# -------- recommend_pr_strategy --------

@test "recommend_pr_strategy returns 'separate' when no overlap" {
  local tasks='[
    {"id":"T1","description":"modify lib/a.sh"},
    {"id":"T2","description":"modify lib/b.sh"}
  ]'
  run recommend_pr_strategy "$tasks"
  assert_equal "0" "$status"
  assert_equal "separate" "$output"
}

@test "recommend_pr_strategy returns 'bundled' when one overlap cluster" {
  local tasks='[
    {"id":"T1","description":"modify lib/wizard.sh"},
    {"id":"T2","description":"modify lib/wizard.sh"},
    {"id":"T3","description":"modify lib/wizard.sh"}
  ]'
  run recommend_pr_strategy "$tasks"
  assert_equal "0" "$status"
  assert_equal "bundled" "$output"
}

@test "recommend_pr_strategy returns 'grouped' when multiple disjoint overlap clusters" {
  local tasks='[
    {"id":"T1","description":"modify lib/foo.sh"},
    {"id":"T2","description":"modify lib/foo.sh"},
    {"id":"T3","description":"modify lib/bar.sh"},
    {"id":"T4","description":"modify lib/bar.sh"}
  ]'
  run recommend_pr_strategy "$tasks"
  assert_equal "0" "$status"
  assert_equal "grouped" "$output"
}
