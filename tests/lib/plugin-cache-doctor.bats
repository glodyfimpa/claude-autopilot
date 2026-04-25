#!/usr/bin/env bats
# Tests for lib/plugin-cache-doctor.sh
#
# Responsibility: Diagnose desync between ~/.claude/plugins/installed_plugins.json
# (manifest) and ~/.claude/plugins/cache/<plugin>/<version>/ (filesystem).
#
# All tests use a mocked plugins root in tmpdir — they MUST never touch the real
# ~/.claude/plugins directory. The library accepts PLUGINS_ROOT as override.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  PLUGINS_ROOT="$TEST_TMPDIR/plugins"
  mkdir -p "$PLUGINS_ROOT/cache"
  export PLUGINS_ROOT
  # shellcheck source=/dev/null
  source "$LIB_DIR/plugin-cache-doctor.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# Helper: create a manifest entry for plugin <name> pointing at cache <version>.
# Matches the real Claude Code schema: .plugins[name] is an ARRAY of install
# records, each with scope/installPath/version.
write_manifest() {
  local name="$1" version="$2"
  cat > "$PLUGINS_ROOT/installed_plugins.json" <<EOF
{
  "plugins": {
    "$name": [
      {
        "scope": "user",
        "installPath": "$PLUGINS_ROOT/cache/$name/$version",
        "version": "$version"
      }
    ]
  }
}
EOF
}

# Helper: create a cache folder
make_cache() {
  local name="$1" version="$2"
  mkdir -p "$PLUGINS_ROOT/cache/$name/$version"
}

# -------- diagnose_plugins (read-only) --------

@test "diagnose_plugins reports a healthy plugin when manifest path exists on disk" {
  write_manifest "myplugin" "1.0.0"
  make_cache "myplugin" "1.0.0"

  run diagnose_plugins
  assert_equal "0" "$status"
  assert_contains "$output" "myplugin"
  assert_contains "$output" "healthy"
}

@test "diagnose_plugins flags a stale plugin when manifest path is missing" {
  write_manifest "myplugin" "1.0.0"
  # Cache folder NOT created → stale

  run diagnose_plugins
  assert_equal "0" "$status"
  assert_contains "$output" "stale"
  assert_contains "$output" "myplugin"
}

@test "diagnose_plugins flags an orphan cache when folder has no manifest entry" {
  write_manifest "knownplugin" "1.0.0"
  make_cache "knownplugin" "1.0.0"
  # Extra folder with no manifest entry
  make_cache "ghost" "0.1.0"

  run diagnose_plugins
  assert_equal "0" "$status"
  assert_contains "$output" "orphan"
  assert_contains "$output" "ghost"
}

@test "diagnose_plugins handles an empty manifest gracefully" {
  echo '{"plugins": {}}' > "$PLUGINS_ROOT/installed_plugins.json"

  run diagnose_plugins
  assert_equal "0" "$status"
  assert_contains "$output" "no plugins"
}

@test "diagnose_plugins fails clearly when manifest is missing" {
  run diagnose_plugins
  assert_equal "1" "$status"
  assert_contains "$output" "manifest not found"
}

# -------- diagnose_plugins_json (machine-readable output) --------

@test "diagnose_plugins_json returns valid JSON with three keys" {
  write_manifest "myplugin" "1.0.0"
  make_cache "myplugin" "1.0.0"
  make_cache "ghost" "0.1.0"

  run diagnose_plugins_json
  assert_equal "0" "$status"
  # Should be parseable JSON
  echo "$output" | jq -e '.healthy and .stale and .orphans' >/dev/null
}

@test "diagnose_plugins_json lists stale entries with their missing path" {
  write_manifest "myplugin" "1.0.0"
  # No cache folder

  run diagnose_plugins_json
  assert_equal "0" "$status"
  local stale_count
  stale_count=$(echo "$output" | jq '.stale | length')
  assert_equal "1" "$stale_count"
  local stale_name
  stale_name=$(echo "$output" | jq -r '.stale[0].name')
  assert_equal "myplugin" "$stale_name"
}

@test "diagnose_plugins_json lists orphan caches with their disk path" {
  echo '{"plugins": {}}' > "$PLUGINS_ROOT/installed_plugins.json"
  make_cache "ghost" "0.1.0"

  run diagnose_plugins_json
  assert_equal "0" "$status"
  local orphan_count
  orphan_count=$(echo "$output" | jq '.orphans | length')
  assert_equal "1" "$orphan_count"
  local orphan_path
  orphan_path=$(echo "$output" | jq -r '.orphans[0].path')
  assert_contains "$orphan_path" "ghost"
}

# -------- check mode (--check / dry-run) --------

@test "doctor_check returns 0 on a healthy state and reports 'all healthy'" {
  write_manifest "myplugin" "1.0.0"
  make_cache "myplugin" "1.0.0"

  run doctor_check
  assert_equal "0" "$status"
  assert_contains "$output" "all healthy"
}

@test "doctor_check returns 2 when stale or orphan entries are found (dry-run signal)" {
  write_manifest "myplugin" "1.0.0"
  # Stale: no cache

  run doctor_check
  assert_equal "2" "$status"
  assert_contains "$output" "stale"
}

@test "doctor_check is idempotent: running twice on healthy state stays at 0" {
  write_manifest "myplugin" "1.0.0"
  make_cache "myplugin" "1.0.0"

  run doctor_check
  assert_equal "0" "$status"
  run doctor_check
  assert_equal "0" "$status"
}

# -------- fix suggestions --------

@test "suggest_fixes proposes 'claude plugin install' for stale plugins" {
  write_manifest "myplugin" "1.0.0"

  run suggest_fixes
  assert_equal "0" "$status"
  assert_contains "$output" "claude plugin install myplugin"
}

@test "suggest_fixes proposes 'rm -rf' for orphan caches" {
  echo '{"plugins": {}}' > "$PLUGINS_ROOT/installed_plugins.json"
  make_cache "ghost" "0.1.0"

  run suggest_fixes
  assert_equal "0" "$status"
  assert_contains "$output" "rm -rf"
  assert_contains "$output" "ghost"
}

@test "suggest_fixes outputs nothing when state is healthy" {
  write_manifest "myplugin" "1.0.0"
  make_cache "myplugin" "1.0.0"

  run suggest_fixes
  assert_equal "0" "$status"
  # No rm -rf, no install command
  [[ "$output" != *"rm -rf"* ]]
  [[ "$output" != *"plugin install"* ]]
}
