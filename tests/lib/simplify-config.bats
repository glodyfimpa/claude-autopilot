#!/usr/bin/env bats
# Tests for the simplify wizard stage integration.
#
# The simplifier is a skill instruction (not a bash adapter), so these tests
# cover the config/wizard surface only: stage recognition, default value,
# apply/validate, and propose output.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/mcp-detector.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/wizard.sh"

  CLAUDE_SETTINGS_PATH="$TEST_TMPDIR/fake-settings.json"
  export CLAUDE_SETTINGS_PATH
  echo '{}' > "$CLAUDE_SETTINGS_PATH"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- wizard_propose for simplify --------

@test "wizard_propose simplify returns auto as default" {
  run wizard_propose "simplify"
  assert_equal "0" "$status"
  local default
  default="$(echo "$output" | jq -r '.default')"
  assert_equal "auto" "$default"
}

@test "wizard_propose simplify lists auto manual off as options" {
  run wizard_propose "simplify"
  assert_equal "0" "$status"
  local options_len
  options_len="$(echo "$output" | jq -r '.options | length')"
  assert_equal "3" "$options_len"
}

@test "wizard_propose simplify config key is simplify.mode" {
  run wizard_propose "simplify"
  assert_equal "0" "$status"
  local key
  key="$(echo "$output" | jq -r '.configKeys[0]')"
  assert_equal "simplify.mode" "$key"
}

# -------- wizard_apply for simplify --------

@test "wizard_apply persists simplify mode auto" {
  config_init
  run wizard_apply "simplify" "auto"
  assert_equal "0" "$status"
  local stored
  stored="$(config_get "simplify.mode")"
  assert_equal "auto" "$stored"
}

@test "wizard_apply persists simplify mode off" {
  config_init
  run wizard_apply "simplify" "off"
  assert_equal "0" "$status"
  local stored
  stored="$(config_get "simplify.mode")"
  assert_equal "off" "$stored"
}

@test "wizard_apply persists simplify mode manual" {
  config_init
  run wizard_apply "simplify" "manual"
  assert_equal "0" "$status"
  local stored
  stored="$(config_get "simplify.mode")"
  assert_equal "manual" "$stored"
}

@test "wizard_apply rejects invalid simplify choice" {
  config_init
  run wizard_apply "simplify" "bogus"
  assert_equal "1" "$status"
  assert_contains "$output" "unknown"
}

# -------- wizard_propose_all includes simplify --------

@test "wizard_propose_all includes simplify stage" {
  make_fake_git_repo "https://github.com/acme/sample.git"
  run wizard_propose_all
  assert_equal "0" "$status"
  local simplify_default
  simplify_default="$(echo "$output" | jq -r '.simplify.default')"
  assert_equal "auto" "$simplify_default"
}
