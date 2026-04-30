#!/usr/bin/env bats
# Tests for lib/scope-filter.sh
# Implements the deterministic scope filter from TASK-1777750800005.
# The filter takes an enriched-task JSON array and returns:
#   {kept: [...task ids...], excluded: [{id, rule, reason}, ...]}
# Rules:
#   A — explicit precondition not satisfied (regex on description)
#   B — deliverable outside current repo (regex naming external repo)
#   C — circular or unsatisfiable dependency (graph check)
#   D — contradictory acceptance criteria (rare; reserved)

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/scope-filter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- Rule A: explicit precondition not satisfied --------

@test "scope_filter_apply excludes Rule A: 'don't build until N more X'" {
  local input
  input='[{"id":"T1","title":"build retro","description":"Add a retro command. Important: don'\''t build this until at least 2 more manual retrospectives have happened.","acceptanceCriteria":[]}]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local kept_count excluded_count rule
  kept_count=$(echo "$output" | jq '.kept | length')
  excluded_count=$(echo "$output" | jq '.excluded | length')
  rule=$(echo "$output" | jq -r '.excluded[0].rule')
  assert_equal "0" "$kept_count"
  assert_equal "1" "$excluded_count"
  assert_equal "A" "$rule"
}

@test "scope_filter_apply does NOT exclude when 'don't' phrasing is unrelated to a precondition" {
  local input
  input='[{"id":"T1","title":"refactor","description":"Refactor the wizard. Don'\''t add new features in the same commit.","acceptanceCriteria":[]}]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local kept_count
  kept_count=$(echo "$output" | jq '.kept | length')
  assert_equal "1" "$kept_count"
}

# -------- Rule B: deliverable outside current repo --------

@test "scope_filter_apply excludes Rule B: 'validation report on Freelance Compass'" {
  local input
  input='[{"id":"T1","title":"validate","description":"Run the autopilot pipeline end-to-end on Freelance Compass and write a validation report.","acceptanceCriteria":["A validation report is committed under docs/validation/v0.3.0-report.md"]}]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local kept_count rule
  kept_count=$(echo "$output" | jq '.kept | length')
  rule=$(echo "$output" | jq -r '.excluded[0].rule')
  assert_equal "0" "$kept_count"
  assert_equal "B" "$rule"
}

@test "scope_filter_apply does NOT exclude when external project is mentioned only as historical context" {
  local input
  input='[{"id":"T1","title":"refactor","description":"Refactor the adapter. The pattern was inspired by the work on Freelance Compass last month.","acceptanceCriteria":["The adapter has unit tests"]}]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local kept_count
  kept_count=$(echo "$output" | jq '.kept | length')
  assert_equal "1" "$kept_count"
}

# -------- Rule C: broken / circular dependencies --------

@test "scope_filter_apply excludes Rule C: dependency on a task not present in input" {
  local input
  input='[{"id":"T1","title":"feature","description":"Build feature X.","dependencies":["T999"],"acceptanceCriteria":[]}]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local kept_count rule
  kept_count=$(echo "$output" | jq '.kept | length')
  rule=$(echo "$output" | jq -r '.excluded[0].rule')
  assert_equal "0" "$kept_count"
  assert_equal "C" "$rule"
}

@test "scope_filter_apply does NOT exclude when dependency exists within the input set" {
  local input
  input='[{"id":"T1","title":"feature","description":"Build X.","dependencies":["T2"],"acceptanceCriteria":[]},{"id":"T2","title":"setup","description":"Set up.","dependencies":[],"acceptanceCriteria":[]}]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local kept_count
  kept_count=$(echo "$output" | jq '.kept | length')
  assert_equal "2" "$kept_count"
}

# -------- Mixed input: some kept, some excluded --------

@test "scope_filter_apply keeps valid tasks and excludes only the matching ones" {
  local input
  input='[
    {"id":"T_OK","title":"work","description":"Refactor the wizard.","dependencies":[],"acceptanceCriteria":[]},
    {"id":"T_A","title":"retro","description":"Add retro. Don'\''t build this until at least 2 more retrospectives have happened.","dependencies":[],"acceptanceCriteria":[]},
    {"id":"T_B","title":"validate","description":"Validation report on Freelance Compass.","dependencies":[],"acceptanceCriteria":[]}
  ]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local kept_ids excluded_ids
  kept_ids=$(echo "$output" | jq -r '.kept | sort | join(",")')
  excluded_ids=$(echo "$output" | jq -r '.excluded | map(.id) | sort | join(",")')
  assert_equal "T_OK" "$kept_ids"
  assert_equal "T_A,T_B" "$excluded_ids"
}

# -------- Empty input --------

@test "scope_filter_apply on empty array returns empty kept and excluded" {
  run scope_filter_apply "[]"
  assert_equal "0" "$status"
  local kept_count excluded_count
  kept_count=$(echo "$output" | jq '.kept | length')
  excluded_count=$(echo "$output" | jq '.excluded | length')
  assert_equal "0" "$kept_count"
  assert_equal "0" "$excluded_count"
}

# -------- Reason text quality --------

@test "scope_filter_apply includes a quoted phrase in Rule A reason" {
  local input
  input='[{"id":"T1","title":"x","description":"Add it. Don'\''t build until 2 more retros have happened.","acceptanceCriteria":[]}]'
  run scope_filter_apply "$input"
  assert_equal "0" "$status"
  local reason
  reason=$(echo "$output" | jq -r '.excluded[0].reason')
  # Reason should mention "precondition" or "until"
  echo "$reason" | grep -qi "precondition\|until" || {
    echo "Reason was: $reason" >&2
    return 1
  }
}
