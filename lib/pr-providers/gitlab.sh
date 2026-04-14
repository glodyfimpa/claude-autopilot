#!/usr/bin/env bash
# lib/pr-providers/gitlab.sh - PR creation via GitLab CLI (glab)
#
# Contract:
#   pr_provider_gitlab_create <branch> <title> <body> <base>
#     - Opens a MR from <branch> against <base>.
#     - Prints the MR URL on stdout on success.
#     - Returns non-zero on failure.
#
# Requirements: glab CLI must be installed and authenticated.

pr_provider_gitlab_check() {
  if ! command -v glab >/dev/null 2>&1; then
    echo "glab CLI is not installed. See https://gitlab.com/gitlab-org/cli" >&2
    return 1
  fi
}

pr_provider_gitlab_create() {
  local branch="$1"
  local title="$2"
  local body="$3"
  local base="$4"

  pr_provider_gitlab_check || return 1

  glab mr create \
    --source-branch "$branch" \
    --target-branch "$base" \
    --title "$title" \
    --description "$body" \
    --yes
}
