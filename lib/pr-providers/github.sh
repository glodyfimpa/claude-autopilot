#!/usr/bin/env bash
# lib/pr-providers/github.sh - PR creation via the GitHub CLI (gh)
#
# Contract:
#   pr_provider_github_create <branch> <title> <body> <base>
#     - Opens a PR from <branch> against <base>.
#     - Prints the PR URL on stdout on success.
#     - Returns non-zero on failure.
#
# Requirements: gh CLI must be installed and authenticated.

pr_provider_github_check() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is not installed. See https://cli.github.com" >&2
    return 1
  fi
}

pr_provider_github_create() {
  local branch="$1"
  local title="$2"
  local body="$3"
  local base="$4"

  pr_provider_github_check || return 1

  # gh pr create prints the PR URL on its last line.
  gh pr create \
    --base "$base" \
    --head "$branch" \
    --title "$title" \
    --body "$body"
}
