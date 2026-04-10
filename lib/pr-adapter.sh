#!/usr/bin/env bash
# lib/pr-adapter.sh - Dispatcher that delegates PR creation to the configured provider.
#
# The adapter reads 'pr_target.provider' from .autopilot-pipeline.json and
# sources the matching file from lib/pr-providers/. Each provider must expose
# a function named pr_provider_<name>_create with the same contract.
#
# Depends on lib/config.sh being sourced before this file.

# Resolve the directory of this script so the adapter can find provider files
# regardless of the caller's working directory.
PR_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_PROVIDERS_DIR="$PR_ADAPTER_SELF_DIR/pr-providers"

PR_ADAPTER_KNOWN_PROVIDERS="github gitlab bitbucket"

# Return 0 if the given provider name is known to the adapter, 1 otherwise.
pr_adapter_validate_provider() {
  local candidate="$1"
  [[ -z "$candidate" ]] && return 1
  local p
  for p in $PR_ADAPTER_KNOWN_PROVIDERS; do
    if [[ "$p" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

# Create a PR using the provider declared in the config.
# Usage: pr_adapter_create <branch> <title> <body> <base>
# Exit codes:
#   0  success (PR URL printed on stdout)
#   1  configuration error (missing or unknown provider)
#   2  provider is a stub / not yet implemented
#   *  propagated from the provider on other failures
pr_adapter_create() {
  local branch="$1"
  local title="$2"
  local body="$3"
  local base="${4:-main}"

  local provider
  provider="$(config_get "pr_target.provider" 2>/dev/null || true)"
  if [[ -z "$provider" ]]; then
    echo "no pr_target provider configured. Run /autopilot-configure first." >&2
    return 1
  fi

  if ! pr_adapter_validate_provider "$provider"; then
    echo "unknown pr_target provider: $provider" >&2
    return 1
  fi

  local provider_file="$PR_PROVIDERS_DIR/${provider}.sh"
  if [[ ! -f "$provider_file" ]]; then
    echo "provider file not found: $provider_file" >&2
    return 1
  fi

  # shellcheck source=/dev/null
  source "$provider_file"

  local fn_name="pr_provider_${provider}_create"
  if ! declare -f "$fn_name" >/dev/null 2>&1; then
    echo "provider $provider did not expose function $fn_name" >&2
    return 1
  fi

  "$fn_name" "$branch" "$title" "$body" "$base"
}
