---
id: TASK-1777664400004
title: 'task-storage-adapter: normalize status values across providers'
status: Done
assignee: []
created_date: '2026-04-25 15:37'
labels:
  - enhancement
  - adapter
  - consistency
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each task storage provider exposes a different vocabulary for task status. The skills assume a canonical set (`ready | in_progress | done`), but providers return their native values:

- backlog (Backlog.md): `Draft | To Do | In Progress | Done`
- jira: `To Do | In Progress | Done` (configurable per workflow)
- linear: `Backlog | Todo | In Progress | In Review | Done | Canceled`
- notion: depends on the database's status property values
- local-file: free-form, often `ready | in_progress | done`

This was hit during the 2026-04-25 sprint: `task_storage_list` from the backlog provider returned tasks with `status: "To Do"`, but the skill filtered for `status == "ready"`. Manual workaround: filter on `(.status == "ready" or .status == "To Do" or .status == "todo")`.

Fix at the adapter layer, not in every skill:

1. Each provider declares a `<provider>_status_map` returning a JSON object that maps native → canonical
2. `task_storage_list` and `task_storage_fetch` apply the map before returning
3. `task_storage_update_status` accepts canonical values and translates to native before writing
4. Canonical vocabulary: `ready | in_progress | done` (matches local-file convention)

Bonus: skills become provider-agnostic in their filters. Removing 12 lines of `or .status ==` clauses across the codebase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 #1 Each existing provider in lib/task-storage-providers/ declares a status_map function
- [x] #2 #2 lib/task-storage-adapter.sh has a normalize_status helper that applies the map
- [x] #3 #3 task_storage_list returns tasks with canonical status values (ready/in_progress/done)
- [x] #4 #4 task_storage_fetch returns canonical status
- [x] #5 #5 task_storage_update_status translates canonical → native before calling the provider
- [x] #6 #6 All existing skills (autopilot-task, autopilot-sprint) use canonical filters only — no `or .status ==` chains
- [x] #7 #7 bats tests cover round-trip: native → canonical → native for each provider
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 #1 All bats tests green
- [x] #2 #2 Manual smoke test: run /autopilot-sprint with a backlog provider and confirm filter sees ready tasks correctly without manual workaround
<!-- DOD:END -->
