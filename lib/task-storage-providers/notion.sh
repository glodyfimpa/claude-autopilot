#!/usr/bin/env bash
# lib/task-storage-providers/notion.sh - STUB
#
# When implemented, this provider should call the Notion MCP tools:
#   - mcp__<notion>__notion-fetch for fetch
#   - mcp__<notion>__notion-update-page for update_status
#   - mcp__<notion>__notion-create-pages for create
#   - mcp__<notion>__notion-query-database-view for list
# The provider is expected to invoke these via the MCP CLI wrapper or through
# the Claude Code tool call interface.

task_storage_notion_fetch() {
  echo "notion provider is not yet implemented. Contributions welcome." >&2
  return 2
}

task_storage_notion_update_status() {
  echo "notion provider is not yet implemented. Contributions welcome." >&2
  return 2
}

task_storage_notion_create() {
  echo "notion provider is not yet implemented. Contributions welcome." >&2
  return 2
}

task_storage_notion_list() {
  echo "notion provider is not yet implemented. Contributions welcome." >&2
  return 2
}
