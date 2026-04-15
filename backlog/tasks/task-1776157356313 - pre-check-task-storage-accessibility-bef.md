---
id: TASK-1776157356313
title: Pre-check task storage accessibility before branch creation
status: Done
priority: medium
---

## Description
autopilot-task creates a branch from main and then tries to fetch the task. If the task storage directory does not exist on main (e.g. backlog was on a different branch), the fetch fails silently after the branch is already created. Add a pre-flight check that verifies the task ref is accessible before creating the branch.

## Acceptance Criteria
- [ ] #1 autopilot-task verifies task_storage_fetch succeeds before calling create_branch_from_main
- [ ] #2 Clear error message names the missing resource and suggests a fix
- [ ] #3 tests cover the pre-flight failure path
