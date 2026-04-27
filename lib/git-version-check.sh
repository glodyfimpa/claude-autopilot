#!/usr/bin/env bash
# git-version-check.sh
#
# Detects whether the local git binary supports `git worktree add --no-track`,
# which the autopilot-sprint skill relies on for parallel subagent execution.
# The flag was introduced in git 2.20. macOS Xcode toolchains still ship with
# git 2.15, where the flag fails with `error: unknown option no-track`.
#
# Public API:
#   parse_git_version "<git --version output>"
#       echoes "MAJOR.MINOR" on stdout, returns 0 on success, non-zero on parse failure
#
#   git_version_at_least <required> <actual>
#       returns 0 if actual >= required (numeric major/minor compare), 1 otherwise
#
#   git_supports_worktree_no_track [--git-cmd <path>]
#       echoes the detected version on stdout
#       returns 0 if supported (>= 2.20), 1 if too old, 2 if git binary missing/unparseable
#       --git-cmd defaults to `git` on PATH

GIT_VERSION_CHECK_MIN_MAJOR=2
GIT_VERSION_CHECK_MIN_MINOR=20
GIT_VERSION_CHECK_MIN_VERSION="${GIT_VERSION_CHECK_MIN_MAJOR}.${GIT_VERSION_CHECK_MIN_MINOR}"

parse_git_version() {
  local input="$1"
  if [ -z "$input" ]; then
    return 1
  fi
  # Match: "git version X.Y" possibly followed by ".Z" and trailing text.
  local version
  version="$(printf '%s' "$input" | sed -n 's/^git version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p')"
  if [ -z "$version" ]; then
    return 1
  fi
  printf '%s' "$version"
}

git_version_at_least() {
  local required="$1"
  local actual="$2"
  local req_major req_minor act_major act_minor
  req_major="${required%%.*}"
  req_minor="${required#*.}"
  act_major="${actual%%.*}"
  act_minor="${actual#*.}"
  # Strip any trailing components (defensive — parse_git_version already trims).
  req_minor="${req_minor%%.*}"
  act_minor="${act_minor%%.*}"
  if [ "$act_major" -gt "$req_major" ]; then
    return 0
  fi
  if [ "$act_major" -lt "$req_major" ]; then
    return 1
  fi
  if [ "$act_minor" -ge "$req_minor" ]; then
    return 0
  fi
  return 1
}

git_supports_worktree_no_track() {
  local git_cmd="git"
  while [ $# -gt 0 ]; do
    case "$1" in
      --git-cmd)
        git_cmd="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  # Resolve binary: accept either an absolute/relative path that exists, or a name on PATH.
  if [ ! -x "$git_cmd" ] && ! command -v "$git_cmd" >/dev/null 2>&1; then
    printf 'git binary not found: %s\n' "$git_cmd"
    return 2
  fi

  local raw
  raw="$("$git_cmd" --version 2>/dev/null)"
  if [ -z "$raw" ]; then
    printf 'unable to read git version from: %s\n' "$git_cmd"
    return 2
  fi

  local version
  version="$(parse_git_version "$raw")"
  if [ -z "$version" ]; then
    printf 'unable to parse git version from: %s\n' "$raw"
    return 2
  fi

  if git_version_at_least "$GIT_VERSION_CHECK_MIN_VERSION" "$version"; then
    printf '%s' "$version"
    return 0
  fi
  printf '%s' "$version"
  return 1
}
