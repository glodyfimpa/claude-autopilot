#!/usr/bin/env bash
# lib/task-storage-adapter.sh - Dispatcher for task storage operations.
#
# Task storage providers handle both read (fetch, list) and write (create,
# update_status) operations for tasks. The active provider lives in
# task_storage.provider in .autopilot-pipeline.json.
#
# Canonical status vocabulary used by all skills:
#   ready | in_progress | done
#
# Each provider exposes a `task_storage_<provider>_status_map` function
# returning a JSON object mapping native status values to canonical ones,
# e.g. backlog returns {"To Do": "ready", "Done": "done", ...}. The adapter
# helpers `normalize_status_value` and `denormalize_status_value` apply the
# map so skills never need to handle native status vocabularies.
#
# Depends on lib/config.sh and lib/adapter-base.sh being sourced first.

TASK_STORAGE_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_STORAGE_PROVIDERS_DIR="$TASK_STORAGE_ADAPTER_SELF_DIR/task-storage-providers"
TASK_STORAGE_CURRENT_PROVIDER=""

# shellcheck source=/dev/null
source "$TASK_STORAGE_ADAPTER_SELF_DIR/known-providers.sh"
# shellcheck source=/dev/null
source "$TASK_STORAGE_ADAPTER_SELF_DIR/adapter-base.sh"

task_storage_validate_provider() {
  adapter_validate_provider "$TASK_STORAGE_KNOWN_PROVIDERS" "$1"
}

_task_storage_dispatch() {
  adapter_dispatch \
    "TASK_STORAGE" \
    "task_storage" \
    "task_storage.provider" \
    "$TASK_STORAGE_KNOWN_PROVIDERS" \
    "$TASK_STORAGE_PROVIDERS_DIR" \
    "task_storage" \
    "$@"
}

task_storage_fetch()         { _task_storage_dispatch "fetch" "$@"; }
task_storage_update_status() { _task_storage_dispatch "update_status" "$@"; }
task_storage_create()        { _task_storage_dispatch "create" "$@"; }
task_storage_list()          { _task_storage_dispatch "list" "$@"; }

# Internal: load and call the status_map function for the given provider.
# Echoes the map JSON. Empty output if the provider does not declare one.
_task_storage_status_map() {
  local provider="$1"
  local provider_file="$TASK_STORAGE_PROVIDERS_DIR/${provider}.sh"
  if [[ ! -f "$provider_file" ]]; then
    return 1
  fi
  # shellcheck source=/dev/null
  source "$provider_file"
  local fn="task_storage_${provider}_status_map"
  if ! command -v "$fn" >/dev/null 2>&1; then
    return 1
  fi
  "$fn"
}

# normalize_status_value <provider> <native_value>
#   Echoes the canonical status value (ready|in_progress|done) corresponding
#   to <native_value>. If the value is unknown to the provider's status_map,
#   the input is returned unchanged so callers can still see it.
normalize_status_value() {
  local provider="$1"
  local native="$2"
  local map
  map="$(_task_storage_status_map "$provider" 2>/dev/null)"
  if [[ -z "$map" ]]; then
    printf '%s' "$native"
    return 0
  fi
  local mapped
  mapped="$(printf '%s' "$map" | jq -r --arg k "$native" '.[$k] // empty')"
  if [[ -z "$mapped" ]]; then
    printf '%s' "$native"
  else
    printf '%s' "$mapped"
  fi
}

# denormalize_status_value <provider> <canonical_value>
#   Echoes the native status value the provider expects on writes for the
#   given canonical value. Falls back to the canonical value when no inverse
#   mapping is found.
denormalize_status_value() {
  local provider="$1"
  local canonical="$2"
  local map
  map="$(_task_storage_status_map "$provider" 2>/dev/null)"
  if [[ -z "$map" ]]; then
    printf '%s' "$canonical"
    return 0
  fi
  # Find the first native key whose value equals $canonical.
  local native
  native="$(printf '%s' "$map" | jq -r --arg v "$canonical" 'to_entries | map(select(.value == $v)) | .[0].key // empty')"
  if [[ -z "$native" ]]; then
    printf '%s' "$canonical"
  else
    printf '%s' "$native"
  fi
}
