#!/usr/bin/env bats
# Tests for lib/wizard.sh
#
# The wizard is not interactive itself: it exposes two pure functions that
# the slash command wraps.
#
#   wizard_propose <stage>
#     Reads MCP settings + git remote and returns JSON:
#       { stage, default, options, configKeys }
#
#   wizard_propose_all
#     Returns a JSON object with one key per stage.
#
#   wizard_apply <stage> <provider>
#     Writes the chosen provider into .autopilot-pipeline.json under the
#     right section and returns 0, or 1 on failure.
#
# Known stages: prd-source, task-storage, pr-target, parallelization.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/mcp-detector.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/wizard.sh"

  # Minimal fake settings file for detection tests.
  CLAUDE_SETTINGS_PATH="$TEST_TMPDIR/fake-settings.json"
  export CLAUDE_SETTINGS_PATH
  echo '{}' > "$CLAUDE_SETTINGS_PATH"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- wizard_propose --------

@test "wizard_propose pr-target returns github default when remote is github" {
  make_fake_git_repo "https://github.com/acme/sample.git"
  run wizard_propose "pr-target"
  assert_equal "0" "$status"
  local default stage
  stage="$(echo "$output" | jq -r '.stage')"
  default="$(echo "$output" | jq -r '.default')"
  assert_equal "pr-target" "$stage"
  assert_equal "github" "$default"
}

@test "wizard_propose pr-target falls back to github when no remote is found" {
  run wizard_propose "pr-target"
  assert_equal "0" "$status"
  local default
  default="$(echo "$output" | jq -r '.default')"
  # With no git repo, the fallback default is still github (most common).
  assert_equal "github" "$default"
}

@test "wizard_propose task-storage suggests notion when notion MCP is enabled" {
  cat > "$CLAUDE_SETTINGS_PATH" <<'EOF'
{
  "enabledPlugins": { "notion@claude-plugins-official": true }
}
EOF
  run wizard_propose "task-storage"
  assert_equal "0" "$status"
  local default
  default="$(echo "$output" | jq -r '.default')"
  assert_equal "notion" "$default"
}

@test "wizard_propose task-storage falls back to local-file with no MCPs" {
  run wizard_propose "task-storage"
  assert_equal "0" "$status"
  local default
  default="$(echo "$output" | jq -r '.default')"
  assert_equal "local-file" "$default"
}

@test "wizard_propose prd-source prefers notion when notion MCP is enabled" {
  cat > "$CLAUDE_SETTINGS_PATH" <<'EOF'
{
  "enabledPlugins": { "notion@claude-plugins-official": true }
}
EOF
  run wizard_propose "prd-source"
  assert_equal "0" "$status"
  local default
  default="$(echo "$output" | jq -r '.default')"
  assert_equal "notion" "$default"
}

@test "wizard_propose parallelization returns adaptive as default" {
  run wizard_propose "parallelization"
  assert_equal "0" "$status"
  local default
  default="$(echo "$output" | jq -r '.default')"
  assert_equal "adaptive" "$default"
}

@test "wizard_propose rejects unknown stage" {
  run wizard_propose "wat"
  assert_equal "1" "$status"
  assert_contains "$output" "unknown stage"
}

# -------- wizard_propose output shape --------

@test "wizard_propose includes options array for pr-target" {
  make_fake_git_repo "https://github.com/acme/sample.git"
  run wizard_propose "pr-target"
  assert_equal "0" "$status"
  local has_github options_len
  options_len="$(echo "$output" | jq -r '.options | length')"
  [[ "$options_len" -ge 3 ]]
}

# -------- wizard_propose_all --------

@test "wizard_propose_all returns a proposal for every stage" {
  make_fake_git_repo "https://github.com/acme/sample.git"
  run wizard_propose_all
  assert_equal "0" "$status"
  local keys_count
  keys_count="$(echo "$output" | jq -r '. | keys | length')"
  assert_equal "5" "$keys_count"
  local pr_default
  pr_default="$(echo "$output" | jq -r '."pr-target".default')"
  assert_equal "github" "$pr_default"
}

# -------- wizard_apply --------

@test "wizard_apply persists pr-target choice" {
  config_init
  run wizard_apply "pr-target" "github"
  assert_equal "0" "$status"
  local stored
  stored="$(config_get "pr_target.provider")"
  assert_equal "github" "$stored"
}

@test "wizard_apply persists task-storage choice" {
  config_init
  run wizard_apply "task-storage" "local-file"
  assert_equal "0" "$status"
  local stored
  stored="$(config_get "task_storage.provider")"
  assert_equal "local-file" "$stored"
}

@test "wizard_apply persists prd-source choice" {
  config_init
  run wizard_apply "prd-source" "chat-paste"
  assert_equal "0" "$status"
  local stored
  stored="$(config_get "prd_source.provider")"
  assert_equal "chat-paste" "$stored"
}

@test "wizard_apply persists parallelization strategy" {
  config_init
  run wizard_apply "parallelization" "adaptive"
  assert_equal "0" "$status"
  local stored
  stored="$(config_get "parallelization.strategy")"
  assert_equal "adaptive" "$stored"
}

@test "wizard_apply rejects unknown stage" {
  config_init
  run wizard_apply "wat" "github"
  assert_equal "1" "$status"
  assert_contains "$output" "unknown stage"
}

@test "wizard_apply rejects invalid provider for stage" {
  config_init
  run wizard_apply "pr-target" "bogus"
  assert_equal "1" "$status"
  assert_contains "$output" "unknown"
}
