---
id: TASK-1.5
title: 'Notion providers: task-storage + PRD source'
status: To Do
assignee: []
created_date: '2026-04-10 12:59'
labels:
  - provider
  - notion
  - echofold-phase-1
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the two Notion stubs (lib/task-storage-providers/notion.sh and lib/prd-source-providers/notion.sh) with real implementations that use the Notion MCP tools (mcp__*__notion-fetch, mcp__*__notion-create-pages, mcp__*__notion-update-page, mcp__*__notion-query-database-view).

Both providers ship together in one task because they share the same Notion MCP client patterns, the same schema detection logic (database id, title property, status property), and the same config keys (notion.database_id, notion.status_property, notion.status_values). Implementing them separately would duplicate the Notion-specific logic in two files.

Files touched: only lib/task-storage-providers/notion.sh, lib/prd-source-providers/notion.sh, and their respective bats tests. Optionally a small shared helper lib/notion-client.sh for the common MCP calls. Does not touch any adapter or other provider, so parallelizable with every other adapter task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task_storage_notion_fetch returns a normalized task JSON from a Notion page id
- [ ] #2 task_storage_notion_create creates a new page under the configured database with title, description, acceptance criteria, status=ready
- [ ] #3 task_storage_notion_update_status transitions the status property to the configured in_progress or done value
- [ ] #4 task_storage_notion_list returns every task in the configured database with status=ready
- [ ] #5 prd_source_notion_fetch reads a Notion page id and returns the normalized PRD JSON
- [ ] #6 The wizard can collect notion.database_id + status property mapping and persist it
- [ ] #7 tests/lib/task-storage-adapter.bats and tests/lib/prd-source-adapter.bats have new cases that mock the Notion MCP calls
- [ ] #8 README provider matrix moves notion from stub to implemented
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
- [ ] #2 Manual smoke test: fetch a real Notion page and create a task in a real Notion database
<!-- DOD:END -->
