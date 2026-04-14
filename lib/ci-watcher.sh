#!/usr/bin/env bash
# lib/ci-watcher.sh - Blocks task completion until CI finishes.
#
# Reads pr_target.provider from .autopilot-pipeline.json and dispatches to
# the matching CI check strategy under lib/ci-providers/. GitHub uses
# `gh run watch`; gitlab/bitbucket are stubs returning exit 2.
#
# Depends on lib/config.sh and lib/adapter-base.sh being sourced first.

CI_WATCHER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_PROVIDERS_DIR="$CI_WATCHER_SELF_DIR/ci-providers"

# shellcheck source=/dev/null
source "$CI_WATCHER_SELF_DIR/known-providers.sh"
# shellcheck source=/dev/null
source "$CI_WATCHER_SELF_DIR/adapter-base.sh"

CI_WATCHER_DEFAULT_TIMEOUT_MINUTES=15

# wait_for_ci <ref> [timeout_minutes]
#
#   Watches CI for the given git ref until it finishes.
#   Timeout is read from (in order of priority):
#     1. The second argument
#     2. pr_target.config.ci_timeout_minutes in the config
#     3. Default of 15 minutes
#
#   Exit codes:
#     0  CI passed (or no runs found)
#     1  CI failed, timeout, or configuration error
#     2  provider is a stub
wait_for_ci() {
  local ref="$1"
  local timeout_minutes="${2:-}"

  # If no explicit timeout, read from config or use default
  if [[ -z "$timeout_minutes" ]]; then
    timeout_minutes="$(config_get 'pr_target.config.ci_timeout_minutes' 2>/dev/null || true)"
    if [[ -z "$timeout_minutes" ]]; then
      timeout_minutes="$CI_WATCHER_DEFAULT_TIMEOUT_MINUTES"
    fi
  fi

  local timeout_seconds
  timeout_seconds=$((timeout_minutes * 60))

  adapter_dispatch \
    "CI_WATCHER" \
    "pr_target" \
    "pr_target.provider" \
    "$PR_ADAPTER_KNOWN_PROVIDERS" \
    "$CI_PROVIDERS_DIR" \
    "ci_provider" \
    "wait" "$ref" "$timeout_seconds"
}
