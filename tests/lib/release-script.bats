#!/usr/bin/env bats
# Tests for scripts/release.sh
#
# These cover the orchestrator-level checks that don't require a real GitHub
# remote: argument validation, dirty-tree refusal, version comparison, dry-run.
# A real release end-to-end (push + gh release create) is verified manually
# per the task's Definition of Done.
#
# We invoke the script in `--dry-run` mode against a fake git repo populated
# with a fixture plugin.json + README.md, so no network or gh CLI is needed.

load "../helpers/test_helper"

RELEASE_SCRIPT="$PLUGIN_ROOT/scripts/release.sh"

setup() {
  setup_isolated_tmpdir
  make_fake_git_repo "https://github.com/test/fake.git"

  mkdir -p .claude-plugin
  cat > .claude-plugin/plugin.json <<'JSON'
{
  "name": "claude-autopilot",
  "version": "0.6.0",
  "description": "test fixture"
}
JSON

  # Replace the README seed with a fixture that has the test-count marker.
  cat > README.md <<'MD'
# Fixture
Current state: 100 tests, all green on macOS bash 3.2.
MD

  git add .claude-plugin/plugin.json README.md
  git commit --quiet -m "fixture commit"
}

teardown() {
  teardown_isolated_tmpdir
}

# ---------- argument validation ----------

@test "release.sh: refuses missing version arg" {
  run "$RELEASE_SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "version"
}

@test "release.sh: refuses invalid version format" {
  run "$RELEASE_SCRIPT" "v0.7.0"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "format"
}

@test "release.sh: refuses target version not greater than current" {
  run "$RELEASE_SCRIPT" "0.5.0" --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "greater"
}

@test "release.sh: refuses equal version" {
  run "$RELEASE_SCRIPT" "0.6.0" --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "greater"
}

# ---------- working tree state ----------

@test "release.sh: refuses dirty working tree" {
  echo "dirty" > newfile.txt
  git add newfile.txt
  run "$RELEASE_SCRIPT" "0.7.0" --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "clean\|dirty"
}

@test "release.sh: refuses non-main branch" {
  git checkout -b feature/x --quiet
  run "$RELEASE_SCRIPT" "0.7.0" --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "main"
}

# ---------- dry-run output ----------

@test "release.sh: dry-run prints planned actions without mutating state" {
  run "$RELEASE_SCRIPT" "0.7.0" --dry-run --no-edit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "0.7.0"
  echo "$output" | grep -qi "dry"

  # Files not modified.
  grep -q '"version": "0.6.0"' .claude-plugin/plugin.json
  grep -q "100 tests" README.md
}

@test "release.sh: dry-run includes changelog section" {
  run "$RELEASE_SCRIPT" "0.7.0" --dry-run --no-edit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "changelog\|changes since"
}
