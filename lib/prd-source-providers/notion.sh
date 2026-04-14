#!/usr/bin/env bash
# lib/prd-source-providers/notion.sh - PRD source backed by a Notion page.
#
# Uses the Notion MCP tool notion-fetch to read a page by ID and extract
# the title and markdown body. Returns the standard PRD JSON:
#   { title, description, context, metadata }
#
# Depends on lib/notion-client.sh being available (sourced by this file).

PRD_NOTION_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$PRD_NOTION_SELF_DIR/../notion-client.sh"

# Fetch a PRD from a Notion page.
# Usage: prd_source_notion_fetch <page_id>
prd_source_notion_fetch() {
  local page_id="$1"
  if [[ -z "$page_id" ]]; then
    echo "notion prd source requires a page id" >&2
    return 1
  fi

  local response
  response="$(notion_client_fetch_page "$page_id")" || return 1

  local title body
  title="$(echo "$response" | notion_client_extract_title "Name")"
  body="$(echo "$response" | notion_client_extract_markdown)"

  # Fall back to page_id if no title found
  if [[ -z "$title" ]]; then
    title="$page_id"
  fi

  jq -n \
    --arg title "$title" \
    --arg description "$body" \
    --arg source "notion" \
    --arg ref "$page_id" \
    '{
      title: $title,
      description: $description,
      context: "",
      metadata: { source: $source, ref: $ref }
    }'
}
