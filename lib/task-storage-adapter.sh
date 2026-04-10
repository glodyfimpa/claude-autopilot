#!/usr/bin/env bash
# lib/task-storage-adapter.sh - Dispatcher for task storage operations.
#
# Task storage providers handle both READ (fetch, list) and WRITE (create,
# update_status) operations for tasks. The configured provider lives in
# task_storage.provider in .autopilot-pipeline.json.
#
# Depends on lib/config.sh being sourced before this file.

TASK_STORAGE_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_STORAGE_PROVIDERS_DIR="$TASK_STORAGE_ADAPTER_SELF_DIR/task-storage-providers"

TASK_STORAGE_KNOWN_PROVIDERS="local-file chat-paste notion jira linear backlog"

# Return 0 if the provider name is known, 1 otherwise.
task_storage_validate_provider() {
  local candidate="$1"
  [[ -z "$candidate" ]] && return 1
  local p
  for p in $TASK_STORAGE_KNOWN_PROVIDERS; do
    if [[ "$p" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

# Internal: load the configured provider file into the CURRENT shell and
# publish the provider name via the shared variable TASK_STORAGE_CURRENT_PROVIDER.
#
# NOTE: this must NOT be called via command substitution ( $(...) ) because
# that spawns a subshell and `source` would only affect the subshell. Callers
# invoke it directly and then read TASK_STORAGE_CURRENT_PROVIDER.
TASK_STORAGE_CURRENT_PROVIDER=""
_task_storage_load_provider() {
  TASK_STORAGE_CURRENT_PROVIDER=""
  local provider
  provider="$(config_get "task_storage.provider" 2>/dev/null || true)"
  if [[ -z "$provider" ]]; then
    echo "no task_storage provider configured. Run /autopilot-configure first." >&2
    return 1
  fi
  if ! task_storage_validate_provider "$provider"; then
    echo "unknown task_storage provider: $provider" >&2
    return 1
  fi
  local provider_file="$TASK_STORAGE_PROVIDERS_DIR/${provider}.sh"
  if [[ ! -f "$provider_file" ]]; then
    echo "provider file not found: $provider_file" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$provider_file"
  TASK_STORAGE_CURRENT_PROVIDER="$provider"
  return 0
}

# Convert provider name (with hyphens) into a valid function name token.
# "local-file" -> "local_file"
_task_storage_fn_token() {
  printf '%s\n' "$1" | tr '-' '_'
}

# task_storage_fetch <ref>
#   Prints a JSON object describing the task.
task_storage_fetch() {
  local ref="$1"
  _task_storage_load_provider || return $?
  local provider="$TASK_STORAGE_CURRENT_PROVIDER"
  local token fn
  token="$(_task_storage_fn_token "$provider")"
  fn="task_storage_${token}_fetch"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    echo "provider $provider does not implement fetch (not yet implemented)" >&2
    return 2
  fi
  "$fn" "$ref"
}

# task_storage_update_status <ref> <new_status>
task_storage_update_status() {
  local ref="$1"
  local new_status="$2"
  _task_storage_load_provider || return $?
  local provider="$TASK_STORAGE_CURRENT_PROVIDER"
  local token fn
  token="$(_task_storage_fn_token "$provider")"
  fn="task_storage_${token}_update_status"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    echo "provider $provider does not implement update_status (not yet implemented)" >&2
    return 2
  fi
  "$fn" "$ref" "$new_status"
}

# task_storage_create <title> <description> <criteria_csv> [parent]
#   Creates a new task and prints a reference (path/id) on stdout.
task_storage_create() {
  local title="$1"
  local description="$2"
  local criteria_csv="$3"
  local parent="${4:-}"
  _task_storage_load_provider || return $?
  local provider="$TASK_STORAGE_CURRENT_PROVIDER"
  local token fn
  token="$(_task_storage_fn_token "$provider")"
  fn="task_storage_${token}_create"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    echo "provider $provider does not implement create (not yet implemented)" >&2
    return 2
  fi
  "$fn" "$title" "$description" "$criteria_csv" "$parent"
}

# task_storage_list
#   Prints a JSON array of tasks.
task_storage_list() {
  _task_storage_load_provider || return $?
  local provider="$TASK_STORAGE_CURRENT_PROVIDER"
  local token fn
  token="$(_task_storage_fn_token "$provider")"
  fn="task_storage_${token}_list"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    echo "provider $provider does not implement list (not yet implemented)" >&2
    return 2
  fi
  "$fn"
}
