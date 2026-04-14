#!/usr/bin/env bash
# lib/pr-providers/gitlab.sh - STUB implementation for GitLab MRs
#
# When implemented, this provider should use either the `glab` CLI
# (https://gitlab.com/gitlab-org/cli) or the GitLab REST API.
#
# Contract (matches the other providers):
#   pr_provider_gitlab_create <branch> <title> <body> <base>

pr_provider_gitlab_create() {
  echo "gitlab provider is not yet implemented. Contributions welcome." >&2
  return 2
}
