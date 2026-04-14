#!/usr/bin/env bats
# Tests for lib/frontend-verify-adapter.sh
#
# Responsibility: dispatch frontend verification operations (run) to the
# configured provider. Providers: chrome-devtools, playwright (stubs), none.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/frontend-verify-adapter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- frontend_verify_validate_provider --------

@test "frontend_verify_validate_provider accepts known providers" {
  run frontend_verify_validate_provider "chrome-devtools"
  assert_equal "0" "$status"
  run frontend_verify_validate_provider "playwright"
  assert_equal "0" "$status"
  run frontend_verify_validate_provider "none"
  assert_equal "0" "$status"
}

@test "frontend_verify_validate_provider rejects unknown providers" {
  run frontend_verify_validate_provider "mystery"
  assert_equal "1" "$status"
  run frontend_verify_validate_provider ""
  assert_equal "1" "$status"
}

# -------- frontend_verify_run --------

@test "frontend_verify_run fails when no provider is configured" {
  config_init
  run frontend_verify_run
  assert_equal "1" "$status"
  assert_contains "$output" "no frontend_verify provider configured"
}

@test "frontend_verify_run fails with clear error for unknown provider" {
  config_init
  config_set "frontend_verify.provider" "mystery"
  run frontend_verify_run
  assert_equal "1" "$status"
  assert_contains "$output" "unknown frontend_verify provider"
}

@test "frontend_verify_run returns stub message for chrome-devtools provider" {
  config_init
  config_set "frontend_verify.provider" "chrome-devtools"
  run frontend_verify_run
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

@test "frontend_verify_run returns stub message for playwright provider" {
  config_init
  config_set "frontend_verify.provider" "playwright"
  run frontend_verify_run
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

@test "frontend_verify_run returns pass for none provider" {
  config_init
  config_set "frontend_verify.provider" "none"
  run frontend_verify_run
  assert_equal "0" "$status"
  assert_contains "$output" "frontend verification skipped"
}

@test "frontend_verify_run none provider returns normalized JSON" {
  config_init
  config_set "frontend_verify.provider" "none"
  run frontend_verify_run
  assert_equal "0" "$status"
  local passed provider issues_count
  passed="$(echo "$output" | grep '{' | jq -r '.passed')"
  provider="$(echo "$output" | grep '{' | jq -r '.provider')"
  issues_count="$(echo "$output" | grep '{' | jq '.issues | length')"
  assert_equal "true" "$passed"
  assert_equal "none" "$provider"
  assert_equal "0" "$issues_count"
}
