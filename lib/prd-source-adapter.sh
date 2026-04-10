#!/usr/bin/env bash
# lib/prd-source-adapter.sh - Dispatcher for PRD (Product Requirements
# Document) reads.
#
# A PRD is the high-level spec that the decomposition step turns into tasks.
# Providers read from wherever the PRD lives (local markdown, pasted chat
# text, Notion page, Jira epic, Google Doc) and return a normalized JSON
# object: { title, description, context, metadata }.
#
# Depends on lib/config.sh and lib/adapter-base.sh being sourced first.

PRD_SOURCE_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_SOURCE_PROVIDERS_DIR="$PRD_SOURCE_ADAPTER_SELF_DIR/prd-source-providers"
PRD_SOURCE_CURRENT_PROVIDER=""

# shellcheck source=/dev/null
source "$PRD_SOURCE_ADAPTER_SELF_DIR/known-providers.sh"
# shellcheck source=/dev/null
source "$PRD_SOURCE_ADAPTER_SELF_DIR/adapter-base.sh"

prd_source_validate_provider() {
  adapter_validate_provider "$PRD_SOURCE_KNOWN_PROVIDERS" "$1"
}

# prd_source_fetch <ref>
#   <ref> semantics depend on the provider:
#     local-file   path to a markdown file
#     chat-paste   raw PRD text
#     notion       page id
#     jira         epic key
#     google-drive document id
#   Prints a normalized JSON object on stdout.
prd_source_fetch() {
  adapter_dispatch \
    "PRD_SOURCE" \
    "prd_source" \
    "prd_source.provider" \
    "$PRD_SOURCE_KNOWN_PROVIDERS" \
    "$PRD_SOURCE_PROVIDERS_DIR" \
    "prd_source" \
    "fetch" "$@"
}
