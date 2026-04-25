#!/usr/bin/env bash
# push-recovery.sh
# Detect and recover from the "direct push to default branch was blocked
# by repo policy" scenario.
#
# Workflow:
#   1. detect_blocked_push: pure read; returns JSON with blocked/branch/
#      commits_ahead/dirty/multi_commit/branch_suggestion fields.
#   2. recover_blocked_push: moves the single local commit to a new branch
#      and resets the default branch back to origin. Refuses to run when
#      the working tree is dirty, when there are multiple commits ahead,
#      or when not on the default branch. Tags pointing at the moved commit
#      are preserved (git tags follow SHAs, not branches).
#
# Caller is responsible for: pushing the new branch and opening the PR.

# Default branch name. Override via DEFAULT_BRANCH env if a repo uses 'master'
# or similar.
_default_branch() {
  echo "${DEFAULT_BRANCH:-main}"
}

# branch_name_from_message <commit-subject>
# Suggest a branch name from a commit subject. Conventional-commit prefixes
# (feat, fix, chore, docs, refactor, test, perf, build, ci, style) become the
# branch namespace. 'chore: release vX.Y.Z' is a special case that maps to
# 'release/vX.Y.Z' since releases are usually a distinct branch namespace.
branch_name_from_message() {
  local msg="$1"
  if [ -z "$msg" ]; then
    echo "recover/work"
    return 0
  fi

  # Special case: "chore: release vX.Y.Z" -> release/vX.Y.Z
  case "$msg" in
    "chore: release v"*|"chore(release): v"*|"release v"*)
      local version
      version="$(echo "$msg" | sed -E 's/.*(v[0-9][0-9.]*[A-Za-z0-9.-]*).*/\1/')"
      if [ -n "$version" ] && [ "$version" != "$msg" ]; then
        echo "release/$version"
        return 0
      fi
      ;;
  esac

  # Conventional commit: <type>(<scope>): <subject>  OR  <type>: <subject>
  local prefix subject
  case "$msg" in
    feat:*|fix:*|chore:*|docs:*|refactor:*|test:*|perf:*|build:*|ci:*|style:*)
      prefix="${msg%%:*}"
      subject="${msg#*: }"
      ;;
    feat\(*\):*|fix\(*\):*|chore\(*\):*|docs\(*\):*|refactor\(*\):*|test\(*\):*|perf\(*\):*|build\(*\):*|ci\(*\):*|style\(*\):*)
      prefix="${msg%%(*}"
      local rest="${msg#*\(}"
      local scope="${rest%%\)*}"
      subject="${msg#*\): }"
      subject="$scope $subject"
      ;;
    *)
      prefix="recover"
      subject="$msg"
      ;;
  esac

  local slug
  slug="$(_slugify "$subject")"
  echo "$prefix/$slug"
}

_slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g'
}

# detect_blocked_push
# Read-only diagnosis. Prints a JSON blob:
#   {
#     "blocked": true|false,
#     "branch": "<current branch>",
#     "commits_ahead": N,
#     "dirty": true|false,
#     "multi_commit": true|false,
#     "branch_suggestion": "<proposed branch name>"
#   }
# Returns 1 outside a git repository.
detect_blocked_push() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "not a git repository"
    return 1
  fi

  local default_branch current commits_ahead dirty multi_commit blocked
  default_branch="$(_default_branch)"
  current="$(git rev-parse --abbrev-ref HEAD)"

  if git rev-parse --verify "refs/remotes/origin/$default_branch" >/dev/null 2>&1; then
    commits_ahead="$(git rev-list --count "origin/$default_branch..HEAD" 2>/dev/null || echo 0)"
  else
    commits_ahead=0
  fi

  if [ -n "$(git status --porcelain)" ]; then
    dirty=true
  else
    dirty=false
  fi

  if [ "$commits_ahead" -ge 2 ]; then
    multi_commit=true
  else
    multi_commit=false
  fi

  if [ "$current" = "$default_branch" ] && [ "$commits_ahead" -ge 1 ]; then
    blocked=true
  else
    blocked=false
  fi

  local branch_suggestion="recover/work"
  if [ "$commits_ahead" -ge 1 ]; then
    local subject
    subject="$(git log -1 --pretty=%s HEAD)"
    branch_suggestion="$(branch_name_from_message "$subject")"
  fi

  jq -n \
    --argjson blocked "$blocked" \
    --arg branch "$current" \
    --argjson commits_ahead "$commits_ahead" \
    --argjson dirty "$dirty" \
    --argjson multi_commit "$multi_commit" \
    --arg branch_suggestion "$branch_suggestion" \
    '{
      blocked: $blocked,
      branch: $branch,
      commits_ahead: $commits_ahead,
      dirty: $dirty,
      multi_commit: $multi_commit,
      branch_suggestion: $branch_suggestion
    }'
}

# recover_blocked_push
# Mutates git state: creates a recovery branch at HEAD and resets the
# default branch to origin/<default_branch>. Caller is then expected to
# `git push origin <new-branch>` and open the PR.
#
# Bails out (returns 1) when:
#   - not on the default branch
#   - working tree is dirty
#   - 2+ commits ahead of origin (mechanical recovery is unsafe)
recover_blocked_push() {
  local diag default_branch current commits_ahead dirty multi_commit
  diag="$(detect_blocked_push)" || return 1

  default_branch="$(_default_branch)"
  current="$(echo "$diag" | jq -r '.branch')"
  commits_ahead="$(echo "$diag" | jq -r '.commits_ahead')"
  dirty="$(echo "$diag" | jq -r '.dirty')"
  multi_commit="$(echo "$diag" | jq -r '.multi_commit')"

  if [ "$current" != "$default_branch" ]; then
    echo "not on default branch ($current); refusing to recover"
    return 1
  fi
  if [ "$dirty" = "true" ]; then
    echo "working tree dirty; commit or stash before recovering"
    return 1
  fi
  if [ "$multi_commit" = "true" ]; then
    echo "multiple commits ahead ($commits_ahead); recover manually"
    return 1
  fi
  if [ "$commits_ahead" -lt 1 ]; then
    echo "no commits to recover"
    return 1
  fi

  local new_branch
  new_branch="$(echo "$diag" | jq -r '.branch_suggestion')"

  # Create the recovery branch from current HEAD.
  if ! git checkout -b "$new_branch" --quiet 2>/dev/null; then
    # Branch may already exist locally; switch to it and reset to current SHA.
    local sha
    sha="$(git rev-parse HEAD)"
    git checkout "$new_branch" --quiet
    git reset --hard "$sha" --quiet
  fi

  # Now reset the default branch back to origin.
  git branch -f "$default_branch" "origin/$default_branch"

  echo "moved commit to $new_branch; $default_branch reset to origin/$default_branch"
  echo "next: git push -u origin $new_branch && gh pr create --base $default_branch"
}
