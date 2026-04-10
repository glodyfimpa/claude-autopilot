#!/usr/bin/env bash
# lib/config.sh - Per-project pipeline config file (.autopilot-pipeline.json)
#
# The config lives in the current working directory as .autopilot-pipeline.json
# and holds provider choices for each pipeline stage (PRD source, task storage,
# PR target, parallelization). The file is schema-versioned so future changes
# can migrate gracefully.
#
# All functions are idempotent and write atomically (temp file + mv).

CONFIG_FILENAME=".autopilot-pipeline.json"
CONFIG_SCHEMA_VERSION=1

# Absolute path to the config file for the current working directory.
config_path() {
  printf '%s/%s\n' "$(pwd)" "$CONFIG_FILENAME"
}

# Returns 0 if the config file exists, 1 otherwise.
config_exists() {
  [[ -f "$(config_path)" ]]
}

# Create a new config file with schema version and empty stages.
# Fails with exit 1 if the file already exists.
config_init() {
  if config_exists; then
    echo "config already exists at $(config_path)" >&2
    return 1
  fi
  local tmp
  tmp="$(_config_tmpfile)"
  jq -n --argjson v "$CONFIG_SCHEMA_VERSION" '{version: $v}' > "$tmp"
  mv "$tmp" "$(config_path)"
}

# Read a nested value from the config by dotted path.
# Example: config_get "pr_target.provider"
# Returns empty string if the key is missing. Fails if the file is missing.
config_get() {
  local key="$1"
  if ! config_exists; then
    echo "config not found at $(config_path)" >&2
    return 1
  fi
  local path_array
  path_array="$(_config_dotted_to_json_path "$key")"
  jq -r --argjson p "$path_array" 'getpath($p) // "" | if . == null then "" else . end' "$(config_path)"
}

# Set a nested value at the given dotted path.
# Creates the config file if it does not exist.
# Intermediate objects are created as needed. Sibling keys are preserved.
config_set() {
  local key="$1"
  local value="$2"
  if ! config_exists; then
    jq -n --argjson v "$CONFIG_SCHEMA_VERSION" '{version: $v}' > "$(config_path)"
  fi
  local path_array tmp
  path_array="$(_config_dotted_to_json_path "$key")"
  tmp="$(_config_tmpfile)"
  jq --argjson p "$path_array" --arg val "$value" 'setpath($p; $val)' "$(config_path)" > "$tmp"
  mv "$tmp" "$(config_path)"
}

# Remove a nested key from the config.
config_unset() {
  local key="$1"
  if ! config_exists; then
    return 0
  fi
  local path_array tmp
  path_array="$(_config_dotted_to_json_path "$key")"
  tmp="$(_config_tmpfile)"
  jq --argjson p "$path_array" 'delpaths([$p])' "$(config_path)" > "$tmp"
  mv "$tmp" "$(config_path)"
}

# Validate the config file: must be valid JSON and have a supported version.
config_validate() {
  if ! config_exists; then
    echo "config not found at $(config_path)" >&2
    return 1
  fi
  if ! jq empty "$(config_path)" 2>/dev/null; then
    echo "invalid JSON in $(config_path)" >&2
    return 1
  fi
  local version
  version="$(jq -r '.version // empty' "$(config_path)")"
  if [[ -z "$version" ]]; then
    echo "missing version field in $(config_path)" >&2
    return 1
  fi
  if [[ "$version" != "$CONFIG_SCHEMA_VERSION" ]]; then
    echo "unsupported version: $version (expected $CONFIG_SCHEMA_VERSION)" >&2
    return 1
  fi
  return 0
}

# ---- Internal helpers ----

# Convert a dotted path string ("a.b.c") into a JSON array (["a","b","c"])
# so it can be passed to jq's getpath/setpath as --argjson.
_config_dotted_to_json_path() {
  local key="$1"
  jq -nc --arg k "$key" '$k | split(".")'
}

_config_tmpfile() {
  mktemp "${TMPDIR:-/tmp}/autopilot-config.XXXXXX"
}
