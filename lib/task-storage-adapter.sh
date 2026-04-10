#!/usr/bin/env bash
# lib/task-storage-adapter.sh - Dispatcher for task storage operations.
#
# Task storage providers handle both read (fetch, list) and write (create,
# update_status) operations for tasks. The active provider lives in
# task_storage.provider in .autopilot-pipeline.json.
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
