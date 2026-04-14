---
id: TASK-1.8
title: Jira + Linear task-storage providers
status: Done
assignee: []
created_date: '2026-04-10 13:00'
labels:
  - provider
  - task-storage
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the two task-storage stubs with real implementations:
- lib/task-storage-providers/jira.sh uses the Atlassian MCP (mcp__atlassian__*) or the Jira REST API
- lib/task-storage-providers/linear.sh uses the Linear MCP (mcp__linear__*) or the Linear GraphQL API

Shipped together because both speak ticket-tracker semantics (issue key, status transitions, fields like assignee/priority/labels), and the test scaffolding is near-identical. Having them in one task keeps the mock infrastructure DRY.

Files touched: only lib/task-storage-providers/jira.sh, lib/task-storage-providers/linear.sh, tests/lib/task-storage-adapter.bats (add new cases). Does not touch adapter-base or any other provider. Fully parallelizable with every other task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task_storage_jira_fetch, create, update_status, list all work against a real Jira project or the MCP
- [ ] #2 task_storage_linear_fetch, create, update_status, list all work against a real Linear team or the MCP
- [ ] #3 Both providers expose a <provider>_check function that returns 1 when credentials or MCP is missing
- [ ] #4 tests/lib/task-storage-adapter.bats has new cases that stub the MCPs and verify the dispatch works
- [ ] #5 README provider matrix moves jira and linear from stub to implemented
- [ ] #6 Config keys are added to the wizard: jira.project_key, jira.issue_type; linear.team_id
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
<!-- DOD:END -->
