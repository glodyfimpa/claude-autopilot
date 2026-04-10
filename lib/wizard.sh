#!/usr/bin/env bash
# lib/wizard.sh - Non-interactive helpers for the autopilot setup wizard.
#
# The wizard is split in two halves:
#   1. wizard_propose / wizard_propose_all - pure, read-only; detect MCPs and
#      git remote, then return JSON with a recommended default and the list of
#      valid options for each pipeline stage. The slash command renders this
#      to the user and collects confirmation.
#   2. wizard_apply - writes a confirmed choice into .autopilot-pipeline.json.
#
# Known stages: prd-source, task-storage, pr-target, parallelization.
#
# Depends on lib/config.sh and lib/mcp-detector.sh being sourced first.

WIZARD_KNOWN_STAGES="prd-source task-storage pr-target parallelization"
WIZARD_PARALLELIZATION_STRATEGIES="adaptive always-sequential always-parallel"

# Internal: print the key under which a stage stores its provider in the
# config file. Most stages use <stage_snake>.provider, but parallelization
# uses parallelization.strategy since it has no provider per se.
_wizard_stage_config_key() {
  case "$1" in
    prd-source)      echo "prd_source.provider" ;;
    task-storage)    echo "task_storage.provider" ;;
    pr-target)       echo "pr_target.provider" ;;
    parallelization) echo "parallelization.strategy" ;;
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

# Propose the default + options for a single stage.
# Output: {stage, default, options, configKeys}
wizard_propose() {
  local stage="$1"
  if ! _wizard_is_valid_stage "$stage"; then
    echo "unknown stage: $stage" >&2
    return 1
  fi

  local default options_csv
  case "$stage" in
    pr-target)
      default="$(suggest_pr_target_provider 2>/dev/null || true)"
      [[ -z "$default" ]] && default="github"
      options_csv="$(list_available_providers_for_stage "pr-target")"
      ;;
    task-storage)
      default="$(suggest_task_storage_provider 2>/dev/null || true)"
      [[ -z "$default" ]] && default="local-file"
      options_csv="$(list_available_providers_for_stage "task-storage")"
      ;;
    prd-source)
      default="$(suggest_prd_source_provider 2>/dev/null || true)"
      [[ -z "$default" ]] && default="local-file"
      options_csv="$(list_available_providers_for_stage "prd-source")"
      ;;
    parallelization)
      default="adaptive"
      options_csv="$WIZARD_PARALLELIZATION_STRATEGIES"
      ;;
  esac

  # Convert space/newline separated list to a JSON array.
  local options_json
  options_json="$(printf '%s\n' $options_csv | jq -R . | jq -s '.')"

  local key
  key="$(_wizard_stage_config_key "$stage")"

  jq -n \
    --arg stage "$stage" \
    --arg default "$default" \
    --argjson options "$options_json" \
    --arg config_key "$key" \
    '{stage: $stage, default: $default, options: $options, configKeys: [$config_key]}'
}

# Propose defaults for every stage in one JSON object keyed by stage name.
wizard_propose_all() {
  local s out="{"
  local first=1
  for s in $WIZARD_KNOWN_STAGES; do
    local proposal
    proposal="$(wizard_propose "$s")" || return 1
    if (( first == 1 )); then
      out="${out}\"${s}\":${proposal}"
      first=0
    else
      out="${out},\"${s}\":${proposal}"
    fi
  done
  out="${out}}"
  printf '%s' "$out" | jq -c '.'
}

# Validate that a provider/strategy is legal for a given stage.
_wizard_validate_choice() {
  local stage="$1" choice="$2"
  local allowed
  case "$stage" in
    pr-target|task-storage|prd-source)
      allowed="$(list_available_providers_for_stage "$stage" 2>/dev/null || true)"
      ;;
    parallelization)
      allowed="$WIZARD_PARALLELIZATION_STRATEGIES"
      ;;
    *) return 1 ;;
  esac
  local a
  for a in $allowed; do
    [[ "$a" == "$choice" ]] && return 0
  done
  return 1
}

# Persist a confirmed choice into .autopilot-pipeline.json.
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
