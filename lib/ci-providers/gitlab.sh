#!/usr/bin/env bash
# lib/ci-providers/gitlab.sh - STUB implementation for GitLab CI watching
#
# When implemented, this provider should use the `glab` CLI or the
# GitLab REST API to watch pipeline status.
#
# Contract (matches the other providers):
#   ci_provider_gitlab_wait <ref> <timeout_seconds>

ci_provider_gitlab_wait() {
  echo "gitlab CI watcher is not yet implemented. Contributions welcome." >&2
  return 2
}
