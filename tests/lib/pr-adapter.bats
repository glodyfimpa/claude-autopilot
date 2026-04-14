#!/usr/bin/env bats
# Tests for lib/pr-adapter.sh
#
# Responsibility: dispatch PR creation to the configured provider.
# The adapter reads pr_target.provider from the config and sources the
# matching file from lib/pr-providers/.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/pr-adapter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- pr_adapter_create --------

@test "pr_adapter_create fails when no provider is configured" {
  config_init
  run pr_adapter_create "feat/TEST-1-hello" "Test PR" "body" "main"
  assert_equal "1" "$status"
  assert_contains "$output" "no pr_target provider configured"
}

@test "pr_adapter_create fails with clear error for unknown provider" {
  config_init
  config_set "pr_target.provider" "mystery"
  run pr_adapter_create "feat/TEST-1-hello" "Test PR" "body" "main"
  assert_equal "1" "$status"
  assert_contains "$output" "unknown pr_target provider: mystery"
}

@test "pr_adapter_create dispatches to the github provider" {
  config_init
  config_set "pr_target.provider" "github"
  # Create a fake gh CLI on PATH that records its invocation
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Record the pr create invocation
echo "gh $*" >> "$TEST_TMPDIR/gh.log"
# Emulate gh pr create output
echo "https://github.com/acme/sample/pull/42"
EOF
  chmod +x "$TEST_TMPDIR/bin/gh"
  PATH="$TEST_TMPDIR/bin:$PATH"
  export PATH TEST_TMPDIR

  run pr_adapter_create "feat/TEST-1-hello" "Test PR" "This is the body" "main"
  assert_equal "0" "$status"
  assert_contains "$output" "https://github.com/acme/sample/pull/42"

  # Verify gh was invoked with the expected arguments
  local log
  log="$(cat "$TEST_TMPDIR/gh.log")"
  assert_contains "$log" "pr create"
  assert_contains "$log" "--base main"
  assert_contains "$log" "--head feat/TEST-1-hello"
  assert_contains "$log" "--title Test PR"
}

@test "pr_adapter_create returns clear message for stub providers (gitlab, bitbucket)" {
  config_init
  config_set "pr_target.provider" "gitlab"
  run pr_adapter_create "feat/TEST-1-hello" "Test PR" "body" "main"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"

  config_set "pr_target.provider" "bitbucket"
  run pr_adapter_create "feat/TEST-1-hello" "Test PR" "body" "main"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

# -------- pr_adapter_validate_provider --------

@test "pr_adapter_validate_provider accepts known providers" {
  run pr_adapter_validate_provider "github"
  assert_equal "0" "$status"
  run pr_adapter_validate_provider "gitlab"
  assert_equal "0" "$status"
  run pr_adapter_validate_provider "bitbucket"
  assert_equal "0" "$status"
}

@test "pr_adapter_validate_provider rejects unknown providers" {
  run pr_adapter_validate_provider "mystery"
  assert_equal "1" "$status"
  run pr_adapter_validate_provider ""
  assert_equal "1" "$status"
}
