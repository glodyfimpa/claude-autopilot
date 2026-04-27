#!/usr/bin/env bats
# Tests for lib/release-utils.sh
#
# Pure helpers used by scripts/release.sh. The orchestrator script does the
# git/gh/editor side effects; these helpers are pure string transformations
# and validation predicates so they can be unit-tested in isolation.
#
# Public API:
#   validate_version_format <version>            -> 0 if X.Y.Z, 1 otherwise; echoes nothing
#   version_greater_than <a> <b>                 -> 0 if a > b, 1 otherwise (semver compare)
#   update_readme_test_count <content> <count>   -> echoes patched content; status 0/1
#   update_plugin_version <content> <version>    -> echoes patched JSON content; status 0/1
#   extract_pr_merges_from_log <log_text>        -> echoes one PR-merge subject per line

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/release-utils.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# ---------- validate_version_format ----------

@test "validate_version_format: 0.7.0 ok" {
  run validate_version_format "0.7.0"
  [ "$status" -eq 0 ]
}

@test "validate_version_format: 10.20.30 ok" {
  run validate_version_format "10.20.30"
  [ "$status" -eq 0 ]
}

@test "validate_version_format: rejects v-prefix" {
  run validate_version_format "v0.7.0"
  [ "$status" -ne 0 ]
}

@test "validate_version_format: rejects two-segment" {
  run validate_version_format "0.7"
  [ "$status" -ne 0 ]
}

@test "validate_version_format: rejects pre-release suffix" {
  run validate_version_format "0.7.0-rc1"
  [ "$status" -ne 0 ]
}

@test "validate_version_format: rejects empty" {
  run validate_version_format ""
  [ "$status" -ne 0 ]
}

# ---------- version_greater_than ----------

@test "version_greater_than: 0.7.0 > 0.6.0 = true" {
  run version_greater_than "0.7.0" "0.6.0"
  [ "$status" -eq 0 ]
}

@test "version_greater_than: 0.6.1 > 0.6.0 = true" {
  run version_greater_than "0.6.1" "0.6.0"
  [ "$status" -eq 0 ]
}

@test "version_greater_than: 1.0.0 > 0.99.99 = true" {
  run version_greater_than "1.0.0" "0.99.99"
  [ "$status" -eq 0 ]
}

@test "version_greater_than: equal returns false" {
  run version_greater_than "0.6.0" "0.6.0"
  [ "$status" -ne 0 ]
}

@test "version_greater_than: lower returns false" {
  run version_greater_than "0.5.0" "0.6.0"
  [ "$status" -ne 0 ]
}

@test "version_greater_than: 0.6.0 vs 0.6.10 (numeric, not lexical)" {
  run version_greater_than "0.6.10" "0.6.9"
  [ "$status" -eq 0 ]
}

# ---------- update_readme_test_count ----------

@test "update_readme_test_count: patches the line in place" {
  content="prelude
Current state: 335 tests, all green on macOS bash 3.2.
postlude"
  run update_readme_test_count "$content" "350"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Current state: 350 tests, all green on macOS bash 3.2."
  ! echo "$output" | grep -q "335 tests"
}

@test "update_readme_test_count: fails if marker missing" {
  run update_readme_test_count "no marker here" "100"
  [ "$status" -ne 0 ]
}

@test "update_readme_test_count: keeps surrounding lines intact" {
  content="line1
Current state: 100 tests, all green on macOS bash 3.2.
line3"
  run update_readme_test_count "$content" "200"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^line1$"
  echo "$output" | grep -q "^line3$"
}

# ---------- update_plugin_version ----------

@test "update_plugin_version: bumps version field" {
  content='{
  "name": "claude-autopilot",
  "version": "0.6.0",
  "description": "..."
}'
  run update_plugin_version "$content" "0.7.0"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"version": "0.7.0"'
  ! echo "$output" | grep -q '"version": "0.6.0"'
}

@test "update_plugin_version: fails if no version field" {
  run update_plugin_version '{"name": "x"}' "0.7.0"
  [ "$status" -ne 0 ]
}

# ---------- extract_pr_merges_from_log ----------

@test "extract_pr_merges_from_log: keeps squash-merge style (#N)" {
  input="feat(sprint): pre-flight check (#19)
chore: bump deps
feat(skill): smoke test (#21)
refactor: cleanup"
  run extract_pr_merges_from_log "$input"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "(#19)"
  echo "$output" | grep -q "(#21)"
  ! echo "$output" | grep -q "bump deps"
  ! echo "$output" | grep -q "refactor: cleanup"
}

@test "extract_pr_merges_from_log: keeps merge commit style" {
  input="Merge pull request #42 from feature/x
local commit
Merge pull request #43 from feature/y"
  run extract_pr_merges_from_log "$input"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "#42"
  echo "$output" | grep -q "#43"
  ! echo "$output" | grep -q "^local commit$"
}

@test "extract_pr_merges_from_log: empty log echoes nothing, status 0" {
  run extract_pr_merges_from_log ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
