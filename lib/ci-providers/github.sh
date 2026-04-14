#!/usr/bin/env bash
# lib/ci-providers/github.sh - CI watching via the GitHub CLI (gh)
#
# Contract:
#   ci_provider_github_wait <ref> <timeout_seconds>
#     - Watches CI runs for <ref> until they finish or <timeout_seconds> elapses.
#     - Returns 0 if CI passes (or no runs exist).
#     - Returns 1 on CI failure or timeout.
#
# Requirements: gh CLI must be installed and authenticated.

ci_provider_github_check() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is not installed. See https://cli.github.com" >&2
    return 1
  fi
}

ci_provider_github_wait() {
  local ref="$1"
  local timeout_seconds="$2"

  ci_provider_github_check || return 1

  # Check if any runs exist for this ref
  local runs
  runs="$(gh run list --commit "$ref" --json status --limit 1 2>/dev/null)"
  if [[ "$runs" == "[]" || -z "$runs" ]]; then
    echo "no CI runs found for $ref; skipping watch"
    return 0
  fi

  # Watch the run, blocking until it completes or times out
  local watch_output
  watch_output="$(gh run watch --exit-status --timeout "$timeout_seconds" "$ref" 2>&1)" || {
    local rc=$?
    echo "CI failed for $ref" >&2
    echo "$watch_output" >&2
    return 1
  }

  echo "$watch_output"
  return 0
}
