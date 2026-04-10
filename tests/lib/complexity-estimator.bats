#!/usr/bin/env bats
# Tests for lib/complexity-estimator.sh
#
# Responsibility: assign a complexity tier to a task based on heuristic signals
# that do NOT require calling an LLM. This is the "first-pass" estimator; an
# LLM-backed refinement can plug in later.
#
# Tiers:
#   trivial  - <= 2 acceptance criteria, short description
#   standard - 3-5 acceptance criteria, medium description
#   complex  - 6+ acceptance criteria OR long description
#   epic     - criteria count > 10 OR explicit "epic" marker
#
# Input: a JSON task object matching the task-storage-adapter schema
#   { id, title, description, acceptanceCriteria: [...], ... }
# Output: JSON { tier, score, signals: { criteriaCount, descriptionWords } }

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/complexity-estimator.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# Helper: build a task JSON with given criteria count and description.
_task_json() {
  local criteria_count="$1"
  local description="$2"
  local arr=()
  local i
  for ((i=1; i<=criteria_count; i++)); do
    arr+=("Criterion $i")
  done
  local criteria_json
  if [[ ${#arr[@]} -eq 0 ]]; then
    criteria_json="[]"
  else
    criteria_json="$(printf '%s\n' "${arr[@]}" | jq -R . | jq -s '.')"
  fi
  jq -n --arg title "Sample" --arg description "$description" \
        --argjson criteria "$criteria_json" \
        '{id:"t1", title:$title, description:$description,
          status:"ready", parent:null, acceptanceCriteria:$criteria}'
}

# -------- tier assignment --------

@test "estimate_complexity classifies 1 criterion + short desc as trivial" {
  local task
  task="$(_task_json 1 "Add a README badge.")"
  run estimate_complexity "$task"
  assert_equal "0" "$status"
  local tier
  tier="$(echo "$output" | jq -r '.tier')"
  assert_equal "trivial" "$tier"
}

@test "estimate_complexity classifies 4 criteria + medium desc as standard" {
  local task desc
  desc="$(printf 'word %.0s' {1..40})"
  task="$(_task_json 4 "$desc")"
  run estimate_complexity "$task"
  assert_equal "0" "$status"
  local tier
  tier="$(echo "$output" | jq -r '.tier')"
  assert_equal "standard" "$tier"
}

@test "estimate_complexity classifies 7 criteria as complex" {
  local task
  task="$(_task_json 7 "A task with many criteria.")"
  run estimate_complexity "$task"
  assert_equal "0" "$status"
  local tier
  tier="$(echo "$output" | jq -r '.tier')"
  assert_equal "complex" "$tier"
}

@test "estimate_complexity classifies 12 criteria as epic" {
  local task
  task="$(_task_json 12 "Too much for a single ticket.")"
  run estimate_complexity "$task"
  assert_equal "0" "$status"
  local tier
  tier="$(echo "$output" | jq -r '.tier')"
  assert_equal "epic" "$tier"
}

@test "estimate_complexity escalates tier when description is very long" {
  local task big
  big="$(printf 'word %.0s' {1..500})"
  task="$(_task_json 2 "$big")"
  run estimate_complexity "$task"
  assert_equal "0" "$status"
  local tier
  tier="$(echo "$output" | jq -r '.tier')"
  # 2 criteria would be trivial, but 500 words bumps it to complex
  assert_equal "complex" "$tier"
}

# -------- signals shape --------

@test "estimate_complexity output includes criteriaCount and descriptionWords signals" {
  local task
  task="$(_task_json 3 "A short description.")"
  run estimate_complexity "$task"
  assert_equal "0" "$status"
  local cc wc
  cc="$(echo "$output" | jq -r '.signals.criteriaCount')"
  wc="$(echo "$output" | jq -r '.signals.descriptionWords')"
  assert_equal "3" "$cc"
  assert_equal "3" "$wc"
}

@test "estimate_complexity handles a task with no criteria" {
  local task
  task="$(_task_json 0 "Short body.")"
  run estimate_complexity "$task"
  assert_equal "0" "$status"
  local tier cc
  tier="$(echo "$output" | jq -r '.tier')"
  cc="$(echo "$output" | jq -r '.signals.criteriaCount')"
  assert_equal "trivial" "$tier"
  assert_equal "0" "$cc"
}

@test "estimate_complexity fails on invalid JSON input" {
  run estimate_complexity "not json at all"
  assert_equal "1" "$status"
  assert_contains "$output" "invalid"
}
