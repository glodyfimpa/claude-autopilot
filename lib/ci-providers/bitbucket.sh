#!/usr/bin/env bash
# lib/ci-providers/bitbucket.sh - STUB implementation for Bitbucket CI watching
#
# When implemented, this provider should use the Bitbucket Pipelines API
# to watch build status.
#
# Contract (matches the other providers):
#   ci_provider_bitbucket_wait <ref> <timeout_seconds>

ci_provider_bitbucket_wait() {
  echo "bitbucket CI watcher is not yet implemented. Contributions welcome." >&2
  return 2
}
