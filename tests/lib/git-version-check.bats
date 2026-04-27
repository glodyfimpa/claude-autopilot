#!/usr/bin/env bats
# Tests for lib/git-version-check.sh
#
# Responsibility: detect whether the local git binary supports the
# `git worktree add --no-track` flag (added in git 2.20). The autopilot-sprint
# skill uses this to decide whether parallel worktree spawning is safe.
#
# Public API:
#   parse_git_version "<git --version output>" -> echoes "MAJOR.MINOR" or empty on parse failure
#   git_version_at_least <required> <actual>   -> returns 0 if actual >= required, 1 otherwise
#   git_supports_worktree_no_track [--git-cmd CMD] -> returns 0 if supported, 1 if not, 2 if git missing
#                                                   When --git-cmd is omitted, queries `git --version`.
#                                                   On success/failure also echoes the detected version.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/git-version-check.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# ---------- parse_git_version ----------

@test "parse_git_version: standard linux output" {
  run parse_git_version "git version 2.42.0"
  [ "$status" -eq 0 ]
  [ "$output" = "2.42" ]
}

@test "parse_git_version: macOS Xcode toolchain output" {
  run parse_git_version "git version 2.15.0"
  [ "$status" -eq 0 ]
  [ "$output" = "2.15" ]
}

@test "parse_git_version: apple variant suffix" {
  run parse_git_version "git version 2.39.3 (Apple Git-145)"
  [ "$status" -eq 0 ]
  [ "$output" = "2.39" ]
}

@test "parse_git_version: empty input" {
  run parse_git_version ""
  [ "$status" -ne 0 ]
}

@test "parse_git_version: garbage input" {
  run parse_git_version "not a git version string"
  [ "$status" -ne 0 ]
}

# ---------- git_version_at_least ----------

@test "git_version_at_least: 2.20 vs 2.15 = false" {
  run git_version_at_least "2.20" "2.15"
  [ "$status" -ne 0 ]
}

@test "git_version_at_least: 2.20 vs 2.20 = true" {
  run git_version_at_least "2.20" "2.20"
  [ "$status" -eq 0 ]
}

@test "git_version_at_least: 2.20 vs 2.42 = true" {
  run git_version_at_least "2.20" "2.42"
  [ "$status" -eq 0 ]
}

@test "git_version_at_least: major bump 2.20 vs 3.0 = true" {
  run git_version_at_least "2.20" "3.0"
  [ "$status" -eq 0 ]
}

@test "git_version_at_least: major regress 2.20 vs 1.99 = false" {
  run git_version_at_least "2.20" "1.99"
  [ "$status" -ne 0 ]
}

# ---------- git_supports_worktree_no_track ----------
#
# We isolate from the host's real git by creating fake git scripts in
# TEST_TMPDIR and passing them via --git-cmd.

_make_fake_git() {
  local version="$1"
  local script="$TEST_TMPDIR/fake-git-$version"
  cat > "$script" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  echo "git version $version"
  exit 0
fi
exit 0
EOF
  chmod +x "$script"
  echo "$script"
}

@test "git_supports_worktree_no_track: git 2.15 not supported" {
  fake="$(_make_fake_git "2.15.0")"
  run git_supports_worktree_no_track --git-cmd "$fake"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "2.15"
}

@test "git_supports_worktree_no_track: git 2.20 supported" {
  fake="$(_make_fake_git "2.20.0")"
  run git_supports_worktree_no_track --git-cmd "$fake"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2.20"
}

@test "git_supports_worktree_no_track: git 2.42 supported" {
  fake="$(_make_fake_git "2.42.0")"
  run git_supports_worktree_no_track --git-cmd "$fake"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2.42"
}

@test "git_supports_worktree_no_track: missing binary returns 2" {
  run git_supports_worktree_no_track --git-cmd "$TEST_TMPDIR/nonexistent-git"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "git"
}
