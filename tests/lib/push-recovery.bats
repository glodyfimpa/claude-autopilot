#!/usr/bin/env bats
# Tests for lib/push-recovery.sh
#
# Responsibility: Detect the "direct push to main was blocked by policy"
# scenario and propose a safe recovery (extract commit to a release branch,
# reset main to origin, push branch, leave PR creation to the caller).
#
# All tests use a fake git repo in tmpdir. We do NOT run real `git push`.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/push-recovery.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# Helper: bootstrap a repo with a fake remote that already has 'main' at HEAD,
# then add `n` local commits ahead of origin/main on the local main branch.
make_fake_repo_with_local_ahead() {
  local n="${1:-1}"
  make_fake_git_repo
  # Simulate origin/main being at the initial commit.
  git update-ref refs/remotes/origin/main HEAD
  local i
  i=0
  while [ "$i" -lt "$n" ]; do
    echo "change $i" >> README.md
    git add README.md
    git commit --quiet -m "local change $i"
    i=$((i + 1))
  done
}

# -------- branch_name_from_message --------

@test "branch_name_from_message converts 'chore: release v0.4.0' to release/v0.4.0" {
  run branch_name_from_message "chore: release v0.4.0"
  assert_equal "release/v0.4.0" "$output"
}

@test "branch_name_from_message converts 'feat: add login page' to feat/add-login-page" {
  run branch_name_from_message "feat: add login page"
  assert_equal "feat/add-login-page" "$output"
}

@test "branch_name_from_message converts 'fix(api): null pointer' to fix/api-null-pointer" {
  run branch_name_from_message "fix(api): null pointer"
  assert_equal "fix/api-null-pointer" "$output"
}

@test "branch_name_from_message falls back to recover/<slug> when message has no conventional prefix" {
  run branch_name_from_message "Random unstructured message"
  assert_equal "recover/random-unstructured-message" "$output"
}

@test "branch_name_from_message falls back to recover/work when message is empty" {
  run branch_name_from_message ""
  assert_equal "recover/work" "$output"
}

# -------- detect_blocked_push --------

@test "detect_blocked_push returns blocked=true when on main with 1 local commit ahead" {
  make_fake_repo_with_local_ahead 1
  run detect_blocked_push
  assert_equal "0" "$status"
  echo "$output" | jq -e '.blocked == true' >/dev/null
  echo "$output" | jq -e '.commits_ahead == 1' >/dev/null
  echo "$output" | jq -e '.branch == "main"' >/dev/null
}

@test "detect_blocked_push surfaces commit subject as branch_suggestion" {
  make_fake_git_repo
  git update-ref refs/remotes/origin/main HEAD
  echo "x" >> README.md
  git add README.md
  git commit --quiet -m "chore: release v9.9.9"

  run detect_blocked_push
  assert_equal "0" "$status"
  local suggestion
  suggestion=$(echo "$output" | jq -r '.branch_suggestion')
  assert_equal "release/v9.9.9" "$suggestion"
}

@test "detect_blocked_push returns blocked=false when no commits ahead of origin" {
  make_fake_git_repo
  git update-ref refs/remotes/origin/main HEAD
  run detect_blocked_push
  assert_equal "0" "$status"
  echo "$output" | jq -e '.blocked == false' >/dev/null
}

@test "detect_blocked_push returns blocked=false when not on default branch" {
  make_fake_git_repo
  git update-ref refs/remotes/origin/main HEAD
  git checkout -b feature/x --quiet
  echo "x" >> README.md
  git add README.md
  git commit --quiet -m "feat: x"

  run detect_blocked_push
  assert_equal "0" "$status"
  echo "$output" | jq -e '.blocked == false' >/dev/null
}

@test "detect_blocked_push reports multi_commit=true when 2+ commits ahead (bail-out signal)" {
  make_fake_repo_with_local_ahead 3
  run detect_blocked_push
  assert_equal "0" "$status"
  echo "$output" | jq -e '.blocked == true' >/dev/null
  echo "$output" | jq -e '.commits_ahead == 3' >/dev/null
  echo "$output" | jq -e '.multi_commit == true' >/dev/null
}

@test "detect_blocked_push reports dirty=true when working tree has unstaged changes" {
  make_fake_repo_with_local_ahead 1
  echo "uncommitted" >> README.md
  run detect_blocked_push
  assert_equal "0" "$status"
  echo "$output" | jq -e '.dirty == true' >/dev/null
}

@test "detect_blocked_push fails clearly outside a git repo" {
  run detect_blocked_push
  assert_equal "1" "$status"
  assert_contains "$output" "not a git repository"
}

# -------- recover_blocked_push --------

@test "recover_blocked_push moves the local commit to a new branch and resets main to origin" {
  make_fake_repo_with_local_ahead 1
  local origin_sha
  origin_sha="$(git rev-parse origin/main)"
  local local_sha
  local_sha="$(git rev-parse HEAD)"

  # Capture the commit message for the branch name suggestion.
  run recover_blocked_push
  assert_equal "0" "$status"

  # The new branch must point at the original local commit.
  local new_branch
  new_branch="$(git rev-parse --abbrev-ref HEAD)"
  assert_contains "$new_branch" "recover/"
  local new_sha
  new_sha="$(git rev-parse HEAD)"
  assert_equal "$local_sha" "$new_sha"

  # main must now be back at origin/main.
  local main_sha
  main_sha="$(git rev-parse main)"
  assert_equal "$origin_sha" "$main_sha"
}

@test "recover_blocked_push refuses to act when working tree is dirty" {
  make_fake_repo_with_local_ahead 1
  echo "dirty" >> README.md

  run recover_blocked_push
  assert_equal "1" "$status"
  assert_contains "$output" "dirty"
}

@test "recover_blocked_push refuses to act with multiple commits ahead" {
  make_fake_repo_with_local_ahead 3

  run recover_blocked_push
  assert_equal "1" "$status"
  assert_contains "$output" "multiple commits"
}

@test "recover_blocked_push refuses to act when not on default branch" {
  make_fake_git_repo
  git update-ref refs/remotes/origin/main HEAD
  git checkout -b feature/x --quiet
  echo "x" >> README.md
  git add README.md
  git commit --quiet -m "feat: x"

  run recover_blocked_push
  assert_equal "1" "$status"
  assert_contains "$output" "not on default branch"
}

@test "recover_blocked_push preserves a tag pointing at the moved commit" {
  make_fake_repo_with_local_ahead 1
  git tag v9.9.9 HEAD

  run recover_blocked_push
  assert_equal "0" "$status"

  # The tag must still resolve, and point at the same SHA as the new branch HEAD.
  local tag_sha branch_sha
  tag_sha="$(git rev-parse v9.9.9)"
  branch_sha="$(git rev-parse HEAD)"
  assert_equal "$branch_sha" "$tag_sha"
}
