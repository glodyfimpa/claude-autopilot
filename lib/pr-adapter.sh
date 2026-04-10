#!/usr/bin/env bash
# lib/pr-adapter.sh - Dispatcher that delegates PR creation to the
# configured provider.
#
# Reads pr_target.provider from .autopilot-pipeline.json and sources the
# matching file from lib/pr-providers/. Each provider must expose
# pr_provider_<name>_create with the same contract.
#
# Depends on lib/config.sh and lib/adapter-base.sh being sourced first.

PR_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_PROVIDERS_DIR="$PR_ADAPTER_SELF_DIR/pr-providers"
PR_ADAPTER_CURRENT_PROVIDER=""

# shellcheck source=/dev/null
source "$PR_ADAPTER_SELF_DIR/known-providers.sh"
# shellcheck source=/dev/null
source "$PR_ADAPTER_SELF_DIR/adapter-base.sh"

pr_adapter_validate_provider() {
  adapter_validate_provider "$PR_ADAPTER_KNOWN_PROVIDERS" "$1"
}

# pr_adapter_create <branch> <title> <body> <base>
#   Exit codes:
#     0 success (PR URL printed on stdout)
#     1 configuration error
#     2 provider is a stub
#     * propagated from the provider on other failures
pr_adapter_create() {
  local branch="$1" title="$2" body="$3" base="${4:-main}"
  adapter_dispatch \
    "PR_ADAPTER" \
    "pr_target" \
    "pr_target.provider" \
    "$PR_ADAPTER_KNOWN_PROVIDERS" \
    "$PR_PROVIDERS_DIR" \
    "pr_provider" \
    "create" "$branch" "$title" "$body" "$base"
}
