#!/usr/bin/env bash
# Test helper shared by all bats files.
# Provides:
#   - PLUGIN_ROOT: absolute path to the plugin repo root
#   - LIB_DIR:     absolute path to lib/
#   - setup_isolated_tmpdir: creates a unique temp dir per test, cleaned up on teardown
#   - make_fake_git_repo: bootstraps a minimal git repo inside TEST_TMPDIR for tests that need one

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$PLUGIN_ROOT/lib"
export PLUGIN_ROOT LIB_DIR

setup_isolated_tmpdir() {
  local raw
  raw="$(mktemp -d "${TMPDIR:-/tmp}/autopilot-test.XXXXXX")"
  # Normalize any double slashes or trailing slashes from TMPDIR concatenation
  TEST_TMPDIR="$(cd "$raw" && pwd)"
  export TEST_TMPDIR
  cd "$TEST_TMPDIR" || return 1
}

teardown_isolated_tmpdir() {
  if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

make_fake_git_repo() {
  local remote_url="${1:-https://github.com/acme/sample.git}"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name  "Test Runner"
  git remote add origin "$remote_url"
  # Create an initial commit on main so branch creation from main works in tests.
  echo "# sample" > README.md
  git add README.md
  git commit --quiet -m "init"
  git branch -M main 2>/dev/null || git checkout -b main 2>/dev/null || true
}

# Assertion helpers (minimal; bats-assert is a separate dependency we don't want to force)
assert_equal() {
  local expected="$1" actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "expected: '$expected'"
    echo "actual:   '$actual'"
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "expected '$haystack' to contain '$needle'"
    return 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "expected file to exist: $path"
    return 1
  fi
}
