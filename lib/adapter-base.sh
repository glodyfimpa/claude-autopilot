#!/usr/bin/env bash
# lib/adapter-base.sh - Shared skeleton for tool-agnostic adapters.
#
# Every adapter (pr-target, task-storage, prd-source) follows the same shape:
# a known-providers allowlist, a config key pointing at the active provider,
# and a set of dispatcher functions that route to provider files named after
# the provider. This file factors out that skeleton so each adapter only
# needs to declare its constants and call the helpers.
#
# Contract for an adapter built on this base:
#   1. Set <NAMESPACE>_KNOWN_PROVIDERS (space-separated allowlist).
#   2. Set <NAMESPACE>_PROVIDERS_DIR (absolute path to the provider files).
#   3. Set <NAMESPACE>_CONFIG_KEY (e.g. "task_storage.provider").
#   4. Set <NAMESPACE>_LABEL (e.g. "task_storage") for error messages.
#   5. Source this file.
#   6. Call adapter_dispatch with the namespace prefix and action name.
#
# Depends on lib/config.sh being sourced before this file.

# adapter_validate_provider <known_list> <candidate>
#   Returns 0 if the candidate is in the space-separated allowlist, 1 otherwise.
adapter_validate_provider() {
  local known_list="$1" candidate="$2"
  [[ -z "$candidate" ]] && return 1
  local p
  for p in $known_list; do
    [[ "$p" == "$candidate" ]] && return 0
  done
  return 1
}

# adapter_fn_token <name>
#   "local-file" -> "local_file" so the provider name can be used as a
#   function name suffix.
adapter_fn_token() {
  printf '%s\n' "$1" | tr '-' '_'
}

# adapter_load_provider <namespace> <label> <config_key> <known_list> <providers_dir>
#
# Reads the configured provider, validates it, sources its file into the
# CURRENT shell, and sets <NAMESPACE>_CURRENT_PROVIDER to the provider name.
#
# Must NOT be called via command substitution — `source` inside a subshell
# would not affect the caller.
adapter_load_provider() {
  local namespace="$1" label="$2" config_key="$3" known_list="$4" providers_dir="$5"
  local cur_var="${namespace}_CURRENT_PROVIDER"
  eval "$cur_var=\"\""

  local provider
  provider="$(config_get "$config_key" 2>/dev/null || true)"
  if [[ -z "$provider" ]]; then
    echo "no ${label} provider configured. Run /autopilot-configure first." >&2
    return 1
  fi
  if ! adapter_validate_provider "$known_list" "$provider"; then
    echo "unknown ${label} provider: $provider" >&2
    return 1
  fi
  local provider_file="$providers_dir/${provider}.sh"
  if [[ ! -f "$provider_file" ]]; then
    echo "provider file not found: $provider_file" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$provider_file"
  eval "$cur_var=\"\$provider\""
  return 0
}

# adapter_dispatch <namespace> <label> <config_key> <known_list> <providers_dir> <fn_prefix> <action> [args...]
#
# One-stop dispatcher. Loads the provider, looks up
# ${fn_prefix}_${fn_token}_${action}, and calls it with the forwarded args.
# Returns 2 if the provider does not implement the action (stub), the
# provider's own exit code otherwise.
adapter_dispatch() {
  local namespace="$1" label="$2" config_key="$3"
  local known_list="$4" providers_dir="$5" fn_prefix="$6" action="$7"
  shift 7

  adapter_load_provider "$namespace" "$label" "$config_key" "$known_list" "$providers_dir" || return $?
  local cur_var="${namespace}_CURRENT_PROVIDER"
  local provider
  eval "provider=\$$cur_var"

  local token fn
  token="$(adapter_fn_token "$provider")"
  fn="${fn_prefix}_${token}_${action}"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    echo "provider $provider does not implement ${action} (not yet implemented)" >&2
    return 2
  fi
  "$fn" "$@"
}
