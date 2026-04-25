#!/usr/bin/env bats
# Tests for lib/test-plan-runner.sh

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/test-plan-runner.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# Sample PR body fixture (heredoc into a var)
sample_body() {
  cat <<'EOF'
## Summary
- Did a thing.

## Test plan
- [x] `bats tests/lib/foo.bats` (already green)
- [ ] `bats tests/lib/new.bats`
- [ ] Run `npm test`
- [ ] Verify the dropdown looks correct in the UI
- [ ] Smoke test: open the page and click the button

## Notes
- [ ] Not part of the test plan
EOF
}

# -------- extract_test_plan --------

@test "extract_test_plan returns only the lines under '## Test plan'" {
  local body
  body="$(sample_body)"
  run extract_test_plan "$body"
  assert_equal "0" "$status"
  assert_contains "$output" "bats tests/lib/new.bats"
  assert_contains "$output" "Verify the dropdown looks correct in the UI"
  # Must NOT contain the 'Notes' section item
  [[ "$output" != *"Not part of the test plan"* ]]
}

@test "extract_test_plan returns empty when the section is missing" {
  run extract_test_plan "## Summary
- nothing here"
  assert_equal "0" "$status"
  assert_equal "" "$output"
}

# -------- list_unchecked_items --------

@test "list_unchecked_items returns only unchecked items, stripped of the marker" {
  local body plan
  body="$(sample_body)"
  plan="$(extract_test_plan "$body")"
  run list_unchecked_items "$plan"
  assert_equal "0" "$status"
  # The first item is checked ([x]) and must be excluded
  [[ "$output" != *"already green"* ]]
  assert_contains "$output" "bats tests/lib/new.bats"
  assert_contains "$output" "Verify the dropdown"
}

@test "list_unchecked_items returns empty when nothing is unchecked" {
  run list_unchecked_items "- [x] all good
- [x] also good"
  assert_equal "0" "$status"
  assert_equal "" "$output"
}

# -------- classify_item --------

@test "classify_item returns 'executable' for a backtick-quoted command" {
  run classify_item '`bats tests/lib/foo.bats`'
  assert_equal "executable" "$output"
}

@test "classify_item returns 'executable' for an npm test invocation" {
  run classify_item "Run npm test in the project root"
  assert_equal "executable" "$output"
}

@test "classify_item returns 'executable' for a bash invocation" {
  run classify_item "bash scripts/check.sh"
  assert_equal "executable" "$output"
}

@test "classify_item returns 'executable' for a path ending in .bats" {
  run classify_item "tests/lib/branch-utils.bats passes"
  assert_equal "executable" "$output"
}

@test "classify_item returns 'manual' for a UI verification" {
  run classify_item "Verify the dropdown looks correct in the UI"
  assert_equal "manual" "$output"
}

@test "classify_item returns 'manual' for a subjective check" {
  run classify_item "Make sure the spacing feels right"
  assert_equal "manual" "$output"
}

# -------- extract_command_from_item --------

@test "extract_command_from_item returns the backtick-quoted segment when present" {
  run extract_command_from_item 'Run `bats tests/lib/foo.bats` and check output'
  assert_equal "0" "$status"
  assert_equal "bats tests/lib/foo.bats" "$output"
}

@test "extract_command_from_item falls back to the full text when no backticks" {
  run extract_command_from_item "npm test in repo root"
  assert_equal "0" "$status"
  assert_equal "npm test in repo root" "$output"
}

@test "extract_command_from_item returns 1 for manual items" {
  run extract_command_from_item "Verify the dropdown looks correct"
  assert_equal "1" "$status"
}

# -------- annotate_item --------

@test "annotate_item produces a checked line on pass" {
  run annotate_item "bats tests/lib/foo.bats" "pass"
  assert_equal "- [x] bats tests/lib/foo.bats" "$output"
}

@test "annotate_item leaves the line unchecked on fail and adds a failure note" {
  run annotate_item "bats tests/lib/foo.bats" "fail"
  assert_contains "$output" "- [ ] bats tests/lib/foo.bats"
  assert_contains "$output" "(failed:"
}

@test "annotate_item leaves the line unchecked for manual review" {
  run annotate_item "Verify the dropdown looks correct" "manual"
  assert_contains "$output" "- [ ] Verify the dropdown looks correct"
  assert_contains "$output" "(manual review)"
}

@test "annotate_item returns 1 on unknown result kind" {
  run annotate_item "x" "garbage"
  assert_equal "1" "$status"
}
