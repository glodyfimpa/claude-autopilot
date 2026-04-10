#!/usr/bin/env bats
# Tests for lib/config.sh
#
# Responsibility: read/write the per-project pipeline config file
# (.autopilot-pipeline.json). Must handle missing files, invalid JSON,
# nested stage reads, and atomic writes.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- config_path --------

@test "config_path returns .autopilot-pipeline.json in current directory" {
  run config_path
  assert_equal "0" "$status"
  assert_equal "$TEST_TMPDIR/.autopilot-pipeline.json" "$output"
}

# -------- config_exists --------

@test "config_exists returns 1 when file is missing" {
  run config_exists
  assert_equal "1" "$status"
}

@test "config_exists returns 0 when file is present" {
  echo '{"version":1}' > .autopilot-pipeline.json
  run config_exists
  assert_equal "0" "$status"
}

# -------- config_init --------

@test "config_init creates a new file with version 1 and empty stages" {
  run config_init
  assert_equal "0" "$status"
  assert_file_exists ".autopilot-pipeline.json"
  local version
  version=$(jq -r '.version' .autopilot-pipeline.json)
  assert_equal "1" "$version"
}

@test "config_init refuses to overwrite an existing file" {
  echo '{"version":1,"custom":"keep-me"}' > .autopilot-pipeline.json
  run config_init
  assert_equal "1" "$status"
  # Original content preserved
  local custom
  custom=$(jq -r '.custom' .autopilot-pipeline.json)
  assert_equal "keep-me" "$custom"
}

# -------- config_get --------

@test "config_get returns empty string when the key is missing" {
  echo '{"version":1}' > .autopilot-pipeline.json
  run config_get "pr_target.provider"
  assert_equal "0" "$status"
  assert_equal "" "$output"
}

@test "config_get returns the value of a nested key" {
  cat > .autopilot-pipeline.json <<'EOF'
{
  "version": 1,
  "pr_target": {
    "provider": "github",
    "config": { "base_branch": "main" }
  }
}
EOF
  run config_get "pr_target.provider"
  assert_equal "github" "$output"
  run config_get "pr_target.config.base_branch"
  assert_equal "main" "$output"
}

@test "config_get fails when the config file is missing" {
  run config_get "pr_target.provider"
  assert_equal "1" "$status"
}

# -------- config_set --------

@test "config_set writes a new nested value and preserves existing keys" {
  echo '{"version":1,"existing":"keep"}' > .autopilot-pipeline.json
  run config_set "pr_target.provider" "github"
  assert_equal "0" "$status"
  local provider existing
  provider=$(jq -r '.pr_target.provider' .autopilot-pipeline.json)
  existing=$(jq -r '.existing' .autopilot-pipeline.json)
  assert_equal "github" "$provider"
  assert_equal "keep" "$existing"
}

@test "config_set creates the file if missing and initializes version" {
  run config_set "pr_target.provider" "github"
  assert_equal "0" "$status"
  local version provider
  version=$(jq -r '.version' .autopilot-pipeline.json)
  provider=$(jq -r '.pr_target.provider' .autopilot-pipeline.json)
  assert_equal "1" "$version"
  assert_equal "github" "$provider"
}

@test "config_set overwrites an existing value at the same path" {
  echo '{"version":1,"pr_target":{"provider":"gitlab"}}' > .autopilot-pipeline.json
  run config_set "pr_target.provider" "github"
  local provider
  provider=$(jq -r '.pr_target.provider' .autopilot-pipeline.json)
  assert_equal "github" "$provider"
}

# -------- config_validate --------

@test "config_validate passes on a well-formed file with version 1" {
  cat > .autopilot-pipeline.json <<'EOF'
{ "version": 1, "pr_target": { "provider": "github", "config": {} } }
EOF
  run config_validate
  assert_equal "0" "$status"
}

@test "config_validate fails on invalid JSON" {
  echo 'not-json' > .autopilot-pipeline.json
  run config_validate
  assert_equal "1" "$status"
  assert_contains "$output" "invalid JSON"
}

@test "config_validate fails when version field is missing or unsupported" {
  echo '{"pr_target":{}}' > .autopilot-pipeline.json
  run config_validate
  assert_equal "1" "$status"
  assert_contains "$output" "version"
}

# -------- config_unset --------

@test "config_unset removes a nested key and keeps siblings" {
  cat > .autopilot-pipeline.json <<'EOF'
{ "version":1, "pr_target":{"provider":"github","config":{"base_branch":"main"}} }
EOF
  run config_unset "pr_target.config"
  assert_equal "0" "$status"
  local has_config provider
  has_config=$(jq 'has("pr_target") and (.pr_target | has("config"))' .autopilot-pipeline.json)
  provider=$(jq -r '.pr_target.provider' .autopilot-pipeline.json)
  assert_equal "false" "$has_config"
  assert_equal "github" "$provider"
}
