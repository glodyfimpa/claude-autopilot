#!/usr/bin/env bash
# lib/notion-client.sh - Shared helper for Notion MCP tool calls.
#
# Provides thin wrappers around the Notion MCP tools. Each function prints
# the raw JSON response on stdout and returns 0 on success.
#
# These functions are designed to be overridden in tests (just redefine the
# function before calling the provider). In production, they delegate to
# the Claude Code MCP tool interface.
#
# Required config keys (read via config_get):
#   notion.database_id     - The Notion database ID for task operations
#   notion.status_property - Name of the status property (default: "Status")
#   notion.status_values.ready       - Value for "ready" status (default: "Ready")
#   notion.status_values.in_progress - Value for "in progress" status (default: "In Progress")
#   notion.status_values.done        - Value for "done" status (default: "Done")

# Fetch a Notion page by ID. Prints the page JSON on stdout.
# Usage: notion_client_fetch_page <page_id>
# Guard: if already defined (e.g. by a test mock), skip re-definition.
if ! declare -f notion_client_fetch_page >/dev/null 2>&1; then
notion_client_fetch_page() {
  local page_id="$1"
  if [[ -z "$page_id" ]]; then
    echo "notion_client_fetch_page: page_id is required" >&2
    return 1
  fi
  # In production, this is overridden by the Claude Code MCP runtime.
  # The function outputs the MCP tool call instruction for Claude to execute.
  echo "__MCP_CALL__:notion-fetch:$(jq -nc --arg id "$page_id" '{pageId: $id}')"
}
fi

# Query a Notion database view. Prints the results JSON on stdout.
# Usage: notion_client_query_database <database_id> [filter_json]
if ! declare -f notion_client_query_database >/dev/null 2>&1; then
notion_client_query_database() {
  local database_id="$1"
  local filter_json="${2:-}"
  if [[ -z "$database_id" ]]; then
    echo "notion_client_query_database: database_id is required" >&2
    return 1
  fi
  local args
  args="$(jq -nc --arg id "$database_id" '{databaseId: $id}')"
  if [[ -n "$filter_json" ]]; then
    args="$(echo "$args" | jq --argjson f "$filter_json" '. + {filter: $f}')"
  fi
  echo "__MCP_CALL__:notion-query-database-view:${args}"
}
fi

# Create a page in a Notion database. Prints the created page JSON on stdout.
# Usage: notion_client_create_page <database_id> <properties_json>
if ! declare -f notion_client_create_page >/dev/null 2>&1; then
notion_client_create_page() {
  local database_id="$1"
  local properties_json="$2"
  if [[ -z "$database_id" || -z "$properties_json" ]]; then
    echo "notion_client_create_page: database_id and properties_json are required" >&2
    return 1
  fi
  local args
  args="$(jq -nc --arg db "$database_id" --argjson props "$properties_json" \
    '{databaseId: $db, properties: $props}')"
  echo "__MCP_CALL__:notion-create-pages:${args}"
}
fi

# Update a Notion page's properties. Prints the updated page JSON on stdout.
# Usage: notion_client_update_page <page_id> <properties_json>
if ! declare -f notion_client_update_page >/dev/null 2>&1; then
notion_client_update_page() {
  local page_id="$1"
  local properties_json="$2"
  if [[ -z "$page_id" || -z "$properties_json" ]]; then
    echo "notion_client_update_page: page_id and properties_json are required" >&2
    return 1
  fi
  local args
  args="$(jq -nc --arg id "$page_id" --argjson props "$properties_json" \
    '{pageId: $id, properties: $props}')"
  echo "__MCP_CALL__:notion-update-page:${args}"
}
fi

# Extract the plain text title from a Notion page response.
# Usage: echo "$page_json" | notion_client_extract_title [property_name]
notion_client_extract_title() {
  local prop="${1:-Name}"
  jq -r --arg p "$prop" '
    .properties[$p].title // [] | map(.plain_text // "") | join("")
  '
}

# Extract rich text content from a Notion page response.
# Usage: echo "$page_json" | notion_client_extract_rich_text <property_name>
notion_client_extract_rich_text() {
  local prop="$1"
  jq -r --arg p "$prop" '
    .properties[$p].rich_text // [] | map(.plain_text // "") | join("")
  '
}

# Extract the status/select value from a Notion page response.
# Usage: echo "$page_json" | notion_client_extract_status [property_name]
notion_client_extract_status() {
  local prop="${1:-Status}"
  jq -r --arg p "$prop" '
    (.properties[$p].status.name // .properties[$p].select.name // "")
  '
}

# Extract the page ID from a Notion page response.
# Usage: echo "$page_json" | notion_client_extract_id
notion_client_extract_id() {
  jq -r '.id // ""'
}

# Extract markdown body from a notion-fetch response.
# The notion-fetch MCP tool returns a markdown field with the page content.
# Usage: echo "$fetch_response" | notion_client_extract_markdown
notion_client_extract_markdown() {
  jq -r '.markdown // .content // .body // ""'
}
