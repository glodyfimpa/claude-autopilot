#!/usr/bin/env bats
# Tests for lib/code-quality-adapter.sh
#
# Responsibility: dispatch code quality operations (scan, check) to the
# configured provider. Includes a retry loop (max 5 iterations) that
# re-scans after fixes.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/code-quality-adapter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- code_quality_validate_provider --------

@test "code_quality_validate_provider accepts known providers" {
  run code_quality_validate_provider "sonarqube"
  assert_equal "0" "$status"
  run code_quality_validate_provider "semgrep"
  assert_equal "0" "$status"
  run code_quality_validate_provider "codeclimate"
  assert_equal "0" "$status"
  run code_quality_validate_provider "none"
  assert_equal "0" "$status"
}

@test "code_quality_validate_provider rejects unknown providers" {
  run code_quality_validate_provider "eslint"
  assert_equal "1" "$status"
  run code_quality_validate_provider ""
  assert_equal "1" "$status"
}

# -------- code_quality_scan --------

@test "code_quality_scan fails when no provider is configured" {
  config_init
  run code_quality_scan
  assert_equal "1" "$status"
  assert_contains "$output" "no code_quality provider configured"
}

@test "code_quality_scan returns stub message for semgrep provider" {
  config_init
  config_set "code_quality.provider" "semgrep"
  run code_quality_scan
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

@test "code_quality_scan returns stub message for codeclimate provider" {
  config_init
  config_set "code_quality.provider" "codeclimate"
  run code_quality_scan
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

@test "code_quality_scan returns empty JSON for none provider" {
  config_init
  config_set "code_quality.provider" "none"
  run code_quality_scan
  assert_equal "0" "$status"
  local issues_count
  issues_count="$(echo "$output" | jq '.issues | length')"
  assert_equal "0" "$issues_count"
}

# -------- code_quality_check --------

@test "code_quality_check returns stub for semgrep" {
  config_init
  config_set "code_quality.provider" "semgrep"
  run code_quality_check
  assert_equal "2" "$status"
}

@test "code_quality_check returns 0 for none provider" {
  config_init
  config_set "code_quality.provider" "none"
  run code_quality_check
  assert_equal "0" "$status"
}

# -------- sonarqube provider --------

@test "code_quality_check delegates to sonarqube check" {
  config_init
  config_set "code_quality.provider" "sonarqube"
  # sonarqube check looks for sonar-scanner; it won't be available in test env
  run code_quality_check
  assert_equal "1" "$status"
  assert_contains "$output" "sonar-scanner"
}

@test "code_quality_scan delegates to sonarqube and returns normalized JSON" {
  config_init
  config_set "code_quality.provider" "sonarqube"
  # Create a fake sonar-scanner that returns mock API response
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/sonar-scanner" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/sonar-scanner"
  # Create fake curl that returns SonarQube API response
  cat > "$TEST_TMPDIR/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat <<'JSON'
{"issues":[{"key":"AX1","rule":"java:S1135","severity":"INFO","message":"Complete the task associated to this TODO comment.","component":"src/Main.java","line":10,"type":"CODE_SMELL"}]}
JSON
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/curl"
  export PATH="$TEST_TMPDIR/bin:$PATH"
  export SONAR_HOST_URL="http://localhost:9000"
  export SONAR_PROJECT_KEY="test-project"

  run code_quality_scan
  assert_equal "0" "$status"
  local issues_count rule
  issues_count="$(echo "$output" | jq '.issues | length')"
  rule="$(echo "$output" | jq -r '.issues[0].rule')"
  assert_equal "1" "$issues_count"
  assert_equal "java:S1135" "$rule"
}

# -------- retry loop --------

@test "code_quality_retry_loop stops after provider returns 0 issues" {
  config_init
  config_set "code_quality.provider" "none"
  run code_quality_retry_loop
  assert_equal "0" "$status"
  assert_contains "$output" "pass"
}

@test "code_quality_retry_loop fails after max 5 iterations with issues" {
  config_init
  config_set "code_quality.provider" "sonarqube"
  # Create a fake sonar-scanner
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/sonar-scanner" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/sonar-scanner"
  # Create fake curl that always returns issues
  cat > "$TEST_TMPDIR/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat <<'JSON'
{"issues":[{"key":"AX1","rule":"java:S1135","severity":"MAJOR","message":"Fix this.","component":"src/Main.java","line":10,"type":"CODE_SMELL"}]}
JSON
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/curl"
  export PATH="$TEST_TMPDIR/bin:$PATH"
  export SONAR_HOST_URL="http://localhost:9000"
  export SONAR_PROJECT_KEY="test-project"

  run code_quality_retry_loop
  assert_equal "1" "$status"
  assert_contains "$output" "5"
}

@test "code_quality_retry_loop succeeds when issues clear on iteration 2" {
  config_init
  config_set "code_quality.provider" "sonarqube"
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/sonar-scanner" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/sonar-scanner"
  # Create a curl that returns issues on first call, empty on second
  local counter_file="$TEST_TMPDIR/.curl_counter"
  echo "0" > "$counter_file"
  cat > "$TEST_TMPDIR/bin/curl" <<SCRIPT
#!/usr/bin/env bash
count=\$(cat "$counter_file")
count=\$((count + 1))
echo "\$count" > "$counter_file"
if [ "\$count" -le 1 ]; then
  cat <<'JSON'
{"issues":[{"key":"AX1","rule":"java:S1135","severity":"MAJOR","message":"Fix this.","component":"src/Main.java","line":10,"type":"CODE_SMELL"}]}
JSON
else
  cat <<'JSON'
{"issues":[]}
JSON
fi
SCRIPT
  chmod +x "$TEST_TMPDIR/bin/curl"
  export PATH="$TEST_TMPDIR/bin:$PATH"
  export SONAR_HOST_URL="http://localhost:9000"
  export SONAR_PROJECT_KEY="test-project"

  run code_quality_retry_loop
  assert_equal "0" "$status"
  assert_contains "$output" "pass"
}
