#!/usr/bin/env bash
# lib/prd-source-adapter.sh - Dispatcher for PRD (Product Requirements Document) reads.
#
# A PRD is the high-level spec that the decomposition step turns into tasks.
# Providers read from wherever the PRD lives (local markdown, pasted chat text,
# Notion page, Jira epic, Google Doc, etc.) and return a normalized JSON object:
#
#   { title, description, context, metadata }
#
# Depends on lib/config.sh being sourced before this file.

PRD_SOURCE_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_SOURCE_PROVIDERS_DIR="$PRD_SOURCE_ADAPTER_SELF_DIR/prd-source-providers"

PRD_SOURCE_KNOWN_PROVIDERS="local-file chat-paste notion jira google-drive"

prd_source_validate_provider() {
  local candidate="$1"
  [[ -z "$candidate" ]] && return 1
  local p
  for p in $PRD_SOURCE_KNOWN_PROVIDERS; do
    if [[ "$p" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

# Convert provider name (with hyphens) into a valid function name token.
# "local-file" -> "local_file"
_prd_source_fn_token() {
  printf '%s\n' "$1" | tr '-' '_'
}

# Internal loader. Must be called directly (NOT via command substitution) so
# that `source` affects the caller's shell.
PRD_SOURCE_CURRENT_PROVIDER=""
_prd_source_load_provider() {
  PRD_SOURCE_CURRENT_PROVIDER=""
  local provider
  provider="$(config_get "prd_source.provider" 2>/dev/null || true)"
  if [[ -z "$provider" ]]; then
    echo "no prd_source provider configured. Run /autopilot-configure first." >&2
    return 1
  fi
  if ! prd_source_validate_provider "$provider"; then
    echo "unknown prd_source provider: $provider" >&2
    return 1
  fi
  local provider_file="$PRD_SOURCE_PROVIDERS_DIR/${provider}.sh"
  if [[ ! -f "$provider_file" ]]; then
    echo "provider file not found: $provider_file" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$provider_file"
  PRD_SOURCE_CURRENT_PROVIDER="$provider"
  return 0
}

# prd_source_fetch <ref>
#   <ref> semantics depend on the provider:
#     - local-file: path to a markdown file
#     - chat-paste: raw PRD text
#     - notion: page id
#     - jira: epic key
#     - google-drive: document id
#   Prints a normalized JSON object on stdout.
prd_source_fetch() {
  local ref="$1"
  _prd_source_load_provider || return $?
  local provider="$PRD_SOURCE_CURRENT_PROVIDER"
  local token fn
  token="$(_prd_source_fn_token "$provider")"
  fn="prd_source_${token}_fetch"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    echo "provider $provider does not implement fetch (not yet implemented)" >&2
    return 2
  fi
  "$fn" "$ref"
}
