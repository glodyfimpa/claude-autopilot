#!/usr/bin/env bats
# Tests for lib/mcp-detector.sh
#
# Responsibility: detect active MCPs (from ~/.claude/settings.json) and git
# remote host, then suggest provider names for each pipeline stage.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # Use a fake CLAUDE settings path so tests don't touch the real one
  export CLAUDE_SETTINGS_PATH="$TEST_TMPDIR/claude-settings.json"
  # shellcheck source=/dev/null
  source "$LIB_DIR/mcp-detector.sh"
}

teardown() {
  teardown_isolated_tmpdir
  unset CLAUDE_SETTINGS_PATH
}

# -------- detect_git_host --------

@test "detect_git_host returns github for HTTPS github remote" {
  make_fake_git_repo "https://github.com/acme/sample.git"
  run detect_git_host
  assert_equal "github" "$output"
}

@test "detect_git_host returns github for SSH github remote" {
  make_fake_git_repo "git@github.com:acme/sample.git"
  run detect_git_host
  assert_equal "github" "$output"
}

@test "detect_git_host returns gitlab for gitlab.com remote" {
  make_fake_git_repo "https://gitlab.com/acme/sample.git"
  run detect_git_host
  assert_equal "gitlab" "$output"
}

@test "detect_git_host returns bitbucket for bitbucket.org remote" {
  make_fake_git_repo "https://bitbucket.org/acme/sample.git"
  run detect_git_host
  assert_equal "bitbucket" "$output"
}

@test "detect_git_host returns unknown for a self-hosted remote" {
  make_fake_git_repo "https://git.acme.internal/team/sample.git"
  run detect_git_host
  assert_equal "unknown" "$output"
}

@test "detect_git_host returns none when there is no git remote" {
  git init --quiet
  git config user.email "t@t.co"
  git config user.name "t"
  run detect_git_host
  assert_equal "none" "$output"
}

@test "detect_git_host returns none when not in a git repo" {
  run detect_git_host
  assert_equal "none" "$output"
}

# -------- scan_enabled_mcps --------

@test "scan_enabled_mcps returns empty when settings file is missing" {
  run scan_enabled_mcps
  assert_equal "0" "$status"
  assert_equal "" "$output"
}

@test "scan_enabled_mcps lists keys of enabledPlugins" {
  cat > "$CLAUDE_SETTINGS_PATH" <<'EOF'
{
  "enabledPlugins": {
    "notion@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "disabled-one@foo": false
  }
}
EOF
  run scan_enabled_mcps
  assert_contains "$output" "notion@claude-plugins-official"
  assert_contains "$output" "github@claude-plugins-official"
  # Disabled plugins should NOT appear
  [[ "$output" != *"disabled-one"* ]]
}

@test "scan_enabled_mcps also includes top-level mcpServers keys" {
  cat > "$CLAUDE_SETTINGS_PATH" <<'EOF'
{
  "enabledPlugins": {},
  "mcpServers": {
    "atlassian": { "url": "https://example.com" },
    "linear":    { "url": "https://example.com" }
  }
}
EOF
  run scan_enabled_mcps
  assert_contains "$output" "atlassian"
  assert_contains "$output" "linear"
}

# -------- suggest_pr_target_provider --------

@test "suggest_pr_target_provider returns github when git host is github" {
  make_fake_git_repo "https://github.com/acme/sample.git"
  run suggest_pr_target_provider
  assert_equal "github" "$output"
}

@test "suggest_pr_target_provider returns gitlab when git host is gitlab" {
  make_fake_git_repo "https://gitlab.com/acme/sample.git"
  run suggest_pr_target_provider
  assert_equal "gitlab" "$output"
}

@test "suggest_pr_target_provider returns empty when host unknown" {
  make_fake_git_repo "https://git.acme.internal/team/sample.git"
  run suggest_pr_target_provider
  assert_equal "" "$output"
}

# -------- suggest_task_storage_provider --------

@test "suggest_task_storage_provider suggests notion when notion MCP is enabled" {
  cat > "$CLAUDE_SETTINGS_PATH" <<'EOF'
{ "enabledPlugins": { "notion@claude-plugins-official": true } }
EOF
  run suggest_task_storage_provider
  assert_equal "notion" "$output"
}

@test "suggest_task_storage_provider suggests jira when atlassian MCP is enabled" {
  cat > "$CLAUDE_SETTINGS_PATH" <<'EOF'
{ "mcpServers": { "atlassian": { "url": "x" } } }
EOF
  run suggest_task_storage_provider
  assert_equal "jira" "$output"
}

@test "suggest_task_storage_provider falls back to local-file when nothing matches" {
  run suggest_task_storage_provider
  assert_equal "local-file" "$output"
}

# -------- suggest_prd_source_provider --------

@test "suggest_prd_source_provider prefers notion when available" {
  cat > "$CLAUDE_SETTINGS_PATH" <<'EOF'
{ "enabledPlugins": { "notion@claude-plugins-official": true } }
EOF
  run suggest_prd_source_provider
  assert_equal "notion" "$output"
}

@test "suggest_prd_source_provider falls back to local-file with no MCPs" {
  run suggest_prd_source_provider
  assert_equal "local-file" "$output"
}

# -------- list_available_providers_for_stage --------

@test "list_available_providers_for_stage pr-target lists all supported providers" {
  run list_available_providers_for_stage "pr-target"
  assert_contains "$output" "github"
  assert_contains "$output" "gitlab"
  assert_contains "$output" "bitbucket"
}

@test "list_available_providers_for_stage task-storage lists all supported providers" {
  run list_available_providers_for_stage "task-storage"
  assert_contains "$output" "notion"
  assert_contains "$output" "jira"
  assert_contains "$output" "linear"
  assert_contains "$output" "local-file"
  assert_contains "$output" "chat-paste"
}

@test "list_available_providers_for_stage prd-source lists all supported providers" {
  run list_available_providers_for_stage "prd-source"
  assert_contains "$output" "local-file"
  assert_contains "$output" "chat-paste"
  assert_contains "$output" "notion"
}

@test "list_available_providers_for_stage rejects unknown stage" {
  run list_available_providers_for_stage "nonsense"
  assert_equal "1" "$status"
}
