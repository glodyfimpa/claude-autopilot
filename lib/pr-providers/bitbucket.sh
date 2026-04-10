#!/usr/bin/env bash
# lib/pr-providers/bitbucket.sh - STUB implementation for Bitbucket PRs
#
# When implemented, this provider should use the Bitbucket REST API
# (https://developer.atlassian.com/cloud/bitbucket/rest/) or a CLI wrapper.
#
# Contract (matches the other providers):
#   pr_provider_bitbucket_create <branch> <title> <body> <base>

pr_provider_bitbucket_create() {
  echo "bitbucket provider is not yet implemented. Contributions welcome." >&2
  return 2
}
