#!/usr/bin/env bats
# Tests for hooks/stop-gate.sh
#
# The stop-gate hook runs quality gates (test, lint, types, build) after
# detecting the project stack. When no gates are configured, it should
# warn the user instead of silently approving.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  make_fake_git_repo

  # Create .autopilot-enabled so the hook doesn't exit early
  mkdir -p "$TEST_TMPDIR/.claude"
  echo "enabled" > "$TEST_TMPDIR/.claude/.autopilot-enabled"
  export HOME="$TEST_TMPDIR"

  # Copy stop-gate.sh to tmpdir so SCRIPT_DIR resolves there
  mkdir -p "$TEST_TMPDIR/hooks"
  cp "$PLUGIN_ROOT/hooks/stop-gate.sh" "$TEST_TMPDIR/hooks/stop-gate.sh"

  # Create some git changes so the hook doesn't exit at "no changes" check
  echo "change" >> README.md
}

teardown() {
  teardown_isolated_tmpdir
}

# Helper: create a mock detect-stack.sh that outputs the given JSON
_mock_detect_stack() {
  local json="$1"
  cat > "$TEST_TMPDIR/hooks/detect-stack.sh" <<SCRIPT
#!/bin/bash
echo '$json'
SCRIPT
  chmod +x "$TEST_TMPDIR/hooks/detect-stack.sh"
}

# Helper: run stop-gate with a minimal JSON input
_run_stop_gate() {
  echo '{"session_id":"test-session-1"}' | bash "$TEST_TMPDIR/hooks/stop-gate.sh"
}

# -------- Unknown stack warning --------

@test "stop-gate emits warning systemMessage when stack is unknown" {
  _mock_detect_stack '{"stack":"unknown","test":"","lint":"","types":"","build":""}'
  run _run_stop_gate
  assert_equal "0" "$status"
  assert_contains "$output" "AUTOPILOT WARNING"
  assert_contains "$output" "No quality gates detected"
}

@test "stop-gate unknown stack warning suggests detect-stack or manual config" {
  _mock_detect_stack '{"stack":"unknown","test":"","lint":"","types":"","build":""}'
  run _run_stop_gate
  assert_equal "0" "$status"
  assert_contains "$output" "detect-stack"
}

@test "stop-gate unknown stack outputs valid JSON with approve decision" {
  _mock_detect_stack '{"stack":"unknown","test":"","lint":"","types":"","build":""}'
  run _run_stop_gate
  assert_equal "0" "$status"
  local decision
  decision=$(echo "$output" | jq -r '.decision')
  assert_equal "approve" "$decision"
}

@test "stop-gate unknown stack includes systemMessage in JSON" {
  _mock_detect_stack '{"stack":"unknown","test":"","lint":"","types":"","build":""}'
  run _run_stop_gate
  assert_equal "0" "$status"
  local msg
  msg=$(echo "$output" | jq -r '.systemMessage')
  assert_contains "$msg" "AUTOPILOT WARNING"
}

# -------- Known stack with gates still works --------

@test "stop-gate with known stack and passing gates does not emit warning" {
  _mock_detect_stack '{"stack":"node-ts","test":"true","lint":"","types":"","build":""}'
  run _run_stop_gate
  assert_equal "0" "$status"
  # Should not contain the zero-gates warning
  if echo "$output" | grep -q "No quality gates detected"; then
    echo "unexpected zero-gates warning in output: $output"
    return 1
  fi
}
