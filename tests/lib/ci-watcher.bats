#!/usr/bin/env bats
# Tests for lib/ci-watcher.sh
#
# Responsibility: wait for CI to finish after a push before marking a task done.
# The watcher reads pr_target.provider from the config and dispatches to the
# matching CI check strategy. GitHub uses `gh run watch`; gitlab/bitbucket
# return exit 2 (stub).

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/ci-watcher.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- wait_for_ci: config errors --------

@test "wait_for_ci fails when no provider is configured" {
  config_init
  run wait_for_ci "abc1234" "15"
  assert_equal "1" "$status"
  assert_contains "$output" "no pr_target provider configured"
}

@test "wait_for_ci fails with clear error for unknown provider" {
  config_init
  config_set "pr_target.provider" "mystery"
  run wait_for_ci "abc1234" "15"
  assert_equal "1" "$status"
  assert_contains "$output" "unknown pr_target provider: mystery"
}

# -------- wait_for_ci: github happy path --------

@test "wait_for_ci succeeds when gh run watch exits 0 (CI passes)" {
  config_init
  config_set "pr_target.provider" "github"
  # Create a fake gh CLI that succeeds
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
echo "gh $*" >> "$TEST_TMPDIR/gh.log"
echo "All checks passed"
exit 0
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/gh"
  PATH="$TEST_TMPDIR/bin:$PATH"
  export PATH TEST_TMPDIR

  run wait_for_ci "abc1234" "15"
  assert_equal "0" "$status"

  # Verify gh was invoked with the expected arguments
  local log
  log="$(cat "$TEST_TMPDIR/gh.log")"
  assert_contains "$log" "run watch"
  assert_contains "$log" "abc1234"
}

# -------- wait_for_ci: github CI failure --------

@test "wait_for_ci returns 1 when gh run watch reports failure" {
  config_init
  config_set "pr_target.provider" "github"
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  echo '[{"status":"completed"}]'
  exit 0
fi
echo "Run failed: tests" >&2
exit 1
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/gh"
  PATH="$TEST_TMPDIR/bin:$PATH"
  export PATH TEST_TMPDIR

  run wait_for_ci "abc1234" "15"
  assert_equal "1" "$status"
  assert_contains "$output" "CI failed"
}

# -------- wait_for_ci: github no runs found --------

@test "wait_for_ci succeeds when no CI runs are found for the ref" {
  config_init
  config_set "pr_target.provider" "github"
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  echo "[]"
  exit 0
fi
exit 0
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/gh"
  PATH="$TEST_TMPDIR/bin:$PATH"
  export PATH TEST_TMPDIR

  run wait_for_ci "abc1234" "15"
  assert_equal "0" "$status"
  assert_contains "$output" "no CI runs found"
}

# -------- wait_for_ci: timeout --------

@test "wait_for_ci uses configured timeout from config" {
  config_init
  config_set "pr_target.provider" "github"
  config_set "pr_target.config.ci_timeout_minutes" "30"
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
echo "gh $*" >> "$TEST_TMPDIR/gh.log"
echo "All checks passed"
exit 0
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/gh"
  PATH="$TEST_TMPDIR/bin:$PATH"
  export PATH TEST_TMPDIR

  # Call without explicit timeout; should read from config
  run wait_for_ci "abc1234"
  assert_equal "0" "$status"

  local log
  log="$(cat "$TEST_TMPDIR/gh.log")"
  assert_contains "$log" "--timeout 1800"
}

@test "wait_for_ci uses default 15 minutes when no timeout configured" {
  config_init
  config_set "pr_target.provider" "github"
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
echo "gh $*" >> "$TEST_TMPDIR/gh.log"
echo "All checks passed"
exit 0
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/gh"
  PATH="$TEST_TMPDIR/bin:$PATH"
  export PATH TEST_TMPDIR

  run wait_for_ci "abc1234"
  assert_equal "0" "$status"

  local log
  log="$(cat "$TEST_TMPDIR/gh.log")"
  assert_contains "$log" "--timeout 900"
}

# -------- wait_for_ci: stub providers --------

@test "wait_for_ci returns 2 for gitlab provider (stub)" {
  config_init
  config_set "pr_target.provider" "gitlab"
  run wait_for_ci "abc1234" "15"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

@test "wait_for_ci returns 2 for bitbucket provider (stub)" {
  config_init
  config_set "pr_target.provider" "bitbucket"
  run wait_for_ci "abc1234" "15"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

# -------- wait_for_ci: missing gh CLI --------

@test "ci_provider_github_check fails when gh is not on PATH" {
  # Source the github provider directly to test the check function
  source "$LIB_DIR/ci-providers/github.sh"
  # Build a minimal PATH that keeps jq but excludes gh
  local gh_path
  gh_path="$(command -v gh 2>/dev/null || true)"
  if [[ -n "$gh_path" ]]; then
    local gh_dir
    gh_dir="$(dirname "$gh_path")"
    # Create a filtered PATH that excludes the gh directory
    local filtered_path=""
    local saved_ifs="$IFS"
    IFS=":"
    for dir in $PATH; do
      if [[ "$dir" != "$gh_dir" ]]; then
        if [[ -n "$filtered_path" ]]; then
          filtered_path="$filtered_path:$dir"
        else
          filtered_path="$dir"
        fi
      fi
    done
    IFS="$saved_ifs"
    PATH="$filtered_path"
    export PATH
  fi

  run ci_provider_github_check
  assert_equal "1" "$status"
  assert_contains "$output" "gh CLI is not installed"
}
