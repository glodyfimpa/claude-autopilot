#!/usr/bin/env bash
# lib/wizard.sh - Non-interactive helpers for the autopilot setup wizard.
#
# Two halves:
#   wizard_propose / wizard_propose_all: pure read-only, detect MCPs and git
#     remote and return JSON with a recommended default plus the list of
#     valid options. The slash command renders this to the user and collects
#     confirmation.
#   wizard_apply: writes a confirmed choice into .autopilot-pipeline.json.
#
# Depends on lib/config.sh, lib/mcp-detector.sh, lib/known-providers.sh.

WIZARD_KNOWN_STAGES="prd-source task-storage pr-target parallelization code-quality simplify"

_wizard_stage_config_key() {
  case "$1" in
    prd-source)      echo "prd_source.provider" ;;
    task-storage)    echo "task_storage.provider" ;;
    pr-target)       echo "pr_target.provider" ;;
    parallelization) echo "parallelization.strategy" ;;
    code-quality)    echo "code_quality.provider" ;;
    simplify)        echo "simplify.mode" ;;
    *) return 1 ;;
  esac
}

_wizard_is_valid_stage() {
  local s
  for s in $WIZARD_KNOWN_STAGES; do
    [[ "$s" == "$1" ]] && return 0
  done
  return 1
}

# Compute the recommended default for a provider-backed stage using the
# matching suggest_* helper in mcp-detector.sh. Falls back per-stage when no
# MCP matches and no git host hint is available.
_wizard_default_for_stage() {
  case "$1" in
    pr-target)
      local d; d="$(suggest_pr_target_provider 2>/dev/null || true)"
      printf '%s\n' "${d:-github}" ;;
    task-storage)
      local d; d="$(suggest_task_storage_provider 2>/dev/null || true)"
      printf '%s\n' "${d:-local-file}" ;;
    prd-source)
      local d; d="$(suggest_prd_source_provider 2>/dev/null || true)"
      printf '%s\n' "${d:-local-file}" ;;
    parallelization)
      printf 'adaptive\n' ;;
    code-quality)
      local d; d="$(suggest_code_quality_provider 2>/dev/null || true)"
      printf '%s\n' "${d:-none}" ;;
    simplify)
      printf 'auto\n' ;;
  esac
}

# Propose the default and options for a single stage.
# Output: { stage, default, options, configKeys }
wizard_propose() {
  local stage="$1"
  if ! _wizard_is_valid_stage "$stage"; then
    echo "unknown stage: $stage" >&2
    return 1
  fi

  local default options_csv key
  default="$(_wizard_default_for_stage "$stage")"
  options_csv="$(list_available_providers_for_stage "$stage")"
  key="$(_wizard_stage_config_key "$stage")"

  local options_json
  # shellcheck disable=SC2086
  options_json="$(printf '%s\n' $options_csv | jq -R . | jq -s '.')"

  # Build config keys array. Notion providers require additional keys.
  local config_keys_json
  config_keys_json="$(jq -nc --arg k "$key" '[$k]')"
  if [[ "$stage" == "task-storage" || "$stage" == "prd-source" ]]; then
    config_keys_json="$(echo "$config_keys_json" | jq '. + [
      "notion.database_id",
      "notion.status_property",
      "notion.status_values.ready",
      "notion.status_values.in_progress",
      "notion.status_values.done"
    ]')"
  fi

  jq -n \
    --arg stage "$stage" \
    --arg default "$default" \
    --argjson options "$options_json" \
    --argjson config_keys "$config_keys_json" \
    '{stage: $stage, default: $default, options: $options, configKeys: $config_keys}'
}

# Propose defaults for every stage, returned as one JSON object keyed by
# stage name. jq merges the per-stage proposals directly — no string
# concatenation, no re-parse pass.
wizard_propose_all() {
  local s
  local proposals=""
  for s in $WIZARD_KNOWN_STAGES; do
    local p
    p="$(wizard_propose "$s")" || return 1
    proposals="${proposals}${p}"$'\n'
  done
  printf '%s' "$proposals" | jq -sc 'map({(.stage): .}) | add'
}

_wizard_validate_choice() {
  local stage="$1" choice="$2"
  _wizard_is_valid_stage "$stage" || return 1
  local allowed a
  allowed="$(list_available_providers_for_stage "$stage" 2>/dev/null || true)"
  for a in $allowed; do
    [[ "$a" == "$choice" ]] && return 0
  done
  return 1
}

wizard_apply() {
  local stage="$1" choice="$2"
  if ! _wizard_is_valid_stage "$stage"; then
    echo "unknown stage: $stage" >&2
    return 1
  fi
  if ! _wizard_validate_choice "$stage" "$choice"; then
    echo "unknown choice '$choice' for stage $stage" >&2
    return 1
  fi
  if ! config_exists; then
    config_init || return 1
  fi
  local key
  key="$(_wizard_stage_config_key "$stage")"
  config_set "$key" "$choice"
}
