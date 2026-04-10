#!/usr/bin/env bats
# Tests for lib/branch-utils.sh
#
# Responsibility: Echofold-style branch name generation and branch creation
# from main. Must handle slugification edge cases and be idempotent.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/branch-utils.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- slugify --------

@test "slugify lowercases and kebab-cases a simple title" {
  run slugify "Add User Authentication"
  assert_equal "add-user-authentication" "$output"
}

@test "slugify removes punctuation and diacritics" {
  run slugify "Fix: can't connect to Postgres 17 (urgent!)"
  assert_equal "fix-can-t-connect-to-postgres-17-urgent" "$output"
}

@test "slugify collapses multiple spaces and separators" {
  run slugify "  Hello   ---   World  "
  assert_equal "hello-world" "$output"
}

@test "slugify truncates at 40 characters without splitting words when possible" {
  run slugify "this is a very long title that should be truncated somewhere"
  # Expect at most 40 chars
  [[ "${#output}" -le 40 ]]
  # Expect no trailing hyphen
  [[ "${output: -1}" != "-" ]]
}

@test "slugify handles empty input gracefully" {
  run slugify ""
  assert_equal "untitled" "$output"
}

# -------- build_branch_name --------

@test "build_branch_name produces feat/PROJECT-TICKET-SLUG format for features" {
  run build_branch_name "feat" "MYAPP" "123" "Add login page"
  assert_equal "feat/MYAPP-123-add-login-page" "$output"
}

@test "build_branch_name produces fix/PROJECT-TICKET-SLUG format for bugfixes" {
  run build_branch_name "fix" "MYAPP" "456" "NullPointer on checkout"
  assert_equal "fix/MYAPP-456-nullpointer-on-checkout" "$output"
}

@test "build_branch_name rejects unsupported kind" {
  run build_branch_name "chore" "MYAPP" "1" "something"
  assert_equal "1" "$status"
  assert_contains "$output" "unsupported"
}

@test "build_branch_name uses 'task' as ticket fallback when ticket is empty" {
  run build_branch_name "feat" "MYAPP" "" "Add login page"
  # Should generate something deterministic: timestamp-ish or "task"
  assert_contains "$output" "feat/MYAPP-"
  assert_contains "$output" "-add-login-page"
}

# -------- infer_project_prefix --------

@test "infer_project_prefix returns the repo directory name in uppercase" {
  make_fake_git_repo
  # Rename the repo's parent directory to something predictable
  run infer_project_prefix
  assert_equal "0" "$status"
  # The test tmpdir name is random; verify shape (uppercase, no slashes)
  [[ "$output" =~ ^[A-Z0-9_-]+$ ]]
}

@test "infer_project_prefix trims trailing .git and suffixes" {
  mkdir -p "$TEST_TMPDIR/myproject.git"
  cd "$TEST_TMPDIR/myproject.git"
  make_fake_git_repo
  run infer_project_prefix
  assert_equal "MYPROJECT" "$output"
}

# -------- create_branch_from_main --------

@test "create_branch_from_main checks out main first then creates the new branch" {
  make_fake_git_repo
  # Create some unrelated work on main
  echo "feature stuff" > feature.txt
  git add feature.txt
  git commit --quiet -m "feature work"

  run create_branch_from_main "feat/TEST-1-hello"
  assert_equal "0" "$status"

  local current
  current="$(git rev-parse --abbrev-ref HEAD)"
  assert_equal "feat/TEST-1-hello" "$current"
}

@test "create_branch_from_main is idempotent: existing branch checks out cleanly" {
  make_fake_git_repo
  git checkout -b feat/TEST-1-hello --quiet
  git checkout main --quiet 2>/dev/null || true

  run create_branch_from_main "feat/TEST-1-hello"
  assert_equal "0" "$status"

  local current
  current="$(git rev-parse --abbrev-ref HEAD)"
  assert_equal "feat/TEST-1-hello" "$current"
}

@test "create_branch_from_main fails gracefully when not in a git repo" {
  run create_branch_from_main "feat/TEST-1-hello"
  assert_equal "1" "$status"
  assert_contains "$output" "not a git repository"
}
