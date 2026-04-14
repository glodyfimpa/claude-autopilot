#!/usr/bin/env bash
# lib/pr-providers/bitbucket.sh - PR creation via Bitbucket CLI (bb)
#
# Contract:
#   pr_provider_bitbucket_create <branch> <title> <body> <base>
#     - Opens a PR from <branch> against <base>.
#     - Prints the PR URL on stdout on success.
#     - Returns non-zero on failure.
#
# Requirements: bb CLI must be installed and authenticated.

pr_provider_bitbucket_check() {
  if ! command -v bb >/dev/null 2>&1; then
    echo "bb CLI is not installed. See https://bitbucket.org/atlassian/bitbucket-cli" >&2
    return 1
  fi
}

pr_provider_bitbucket_create() {
  local branch="$1"
  local title="$2"
  local body="$3"
  local base="$4"

  pr_provider_bitbucket_check || return 1

  bb pr create \
    --source "$branch" \
    --destination "$base" \
    --title "$title" \
    --body "$body"
}
