#!/usr/bin/env bats
# Tests for scripts/generate-readme-matrix.sh
#
# Responsibility: generate the provider matrix table from known-providers.sh
# and provider files. Verifies markdown format, stub detection, and that the
# README stays in sync with the generated output.

load "../helpers/test_helper"

# -------- valid markdown output --------

@test "generate-readme-matrix outputs valid markdown table" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  # Check it starts with the header
  assert_contains "$output" "| Stage | Implemented | Stubs available |"
  # Check it has the separator
  assert_contains "$output" "|-------|-------------|-----------------|"
}

@test "generate-readme-matrix includes all five stages" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  assert_contains "$output" "PRD source"
  assert_contains "$output" "Task storage"
  assert_contains "$output" "PR target"
  assert_contains "$output" "Code quality"
  assert_contains "$output" "Frontend verify"
}

@test "generate-readme-matrix output has exactly 7 lines" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local line_count
  line_count="$(printf '%s\n' "$output" | wc -l | tr -d ' ')"
  assert_equal "7" "$line_count"
}

# -------- stub detection --------

@test "generate-readme-matrix detects jira prd-source as stub" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local prd_line
  prd_line="$(printf '%s\n' "$output" | grep 'PRD source')"
  # jira should appear in the Stubs column (third column)
  local stubs_col
  stubs_col="$(printf '%s' "$prd_line" | awk -F'|' '{print $4}')"
  assert_contains "$stubs_col" "jira"
}

@test "generate-readme-matrix detects semgrep as stub" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local cq_line
  cq_line="$(printf '%s\n' "$output" | grep 'Code quality')"
  local stubs_col
  stubs_col="$(printf '%s' "$cq_line" | awk -F'|' '{print $4}')"
  assert_contains "$stubs_col" "semgrep"
}

@test "generate-readme-matrix detects codeclimate as stub" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local cq_line
  cq_line="$(printf '%s\n' "$output" | grep 'Code quality')"
  local stubs_col
  stubs_col="$(printf '%s' "$cq_line" | awk -F'|' '{print $4}')"
  assert_contains "$stubs_col" "codeclimate"
}

@test "generate-readme-matrix lists local-file as implemented for PRD source" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local prd_line
  prd_line="$(printf '%s\n' "$output" | grep 'PRD source')"
  # local-file should be in the Implemented column (second column)
  local impl_col
  impl_col="$(printf '%s' "$prd_line" | awk -F'|' '{print $3}')"
  assert_contains "$impl_col" "local-file"
}

@test "generate-readme-matrix lists chat-paste as implemented for Task storage" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local ts_line
  ts_line="$(printf '%s\n' "$output" | grep 'Task storage')"
  local impl_col
  impl_col="$(printf '%s' "$ts_line" | awk -F'|' '{print $3}')"
  assert_contains "$impl_col" "chat-paste"
}

@test "generate-readme-matrix detects chrome-devtools and playwright as stubs" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local fv_line
  fv_line="$(printf '%s\n' "$output" | grep 'Frontend verify')"
  local stubs_col
  stubs_col="$(printf '%s' "$fv_line" | awk -F'|' '{print $4}')"
  assert_contains "$stubs_col" "chrome-devtools"
  assert_contains "$stubs_col" "playwright"
}

# -------- none providers classified as implemented --------

@test "generate-readme-matrix lists none as implemented for Code quality" {
  run bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh"
  assert_equal "0" "$status"
  local cq_line
  cq_line="$(printf '%s\n' "$output" | grep 'Code quality')"
  local impl_col
  impl_col="$(printf '%s' "$cq_line" | awk -F'|' '{print $3}')"
  assert_contains "$impl_col" "none"
}

# -------- README sync --------

@test "README provider matrix matches generated output" {
  local generated
  generated="$(bash "$PLUGIN_ROOT/scripts/generate-readme-matrix.sh")"
  # Extract the table from README between markers
  local readme_table
  readme_table="$(sed -n '/<!-- PROVIDER-MATRIX:BEGIN -->/,/<!-- PROVIDER-MATRIX:END -->/p' "$PLUGIN_ROOT/README.md" | grep '^|')"
  assert_equal "$generated" "$readme_table"
}
