---
id: TASK-1776163200001
title: Sprint bundled PR strategy when tasks share files
status: To Do
assignee: []
created_date: '2026-04-15'
labels:
  - enhancement
  - architecture
priority: medium
dependencies: []
parent_task_id:
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When autopilot-sprint runs multiple tasks in parallel and several tasks touch the same files (e.g. wizard.sh, autopilot-task.md), each task produces a separate PR. These PRs conflict with each other on the same lines, creating a cascade of merge conflicts for the reviewer.

Extend autopilot-sprint Step 5 (plan presentation) to detect file overlap between tasks and offer a PR strategy choice:

- **(a) Separate PRs** (default) — one PR per task, reviewer handles conflicts
- **(b) Bundled PR** — all tasks on individual worktree branches, then cherry-picked into a single integration branch with one PR. Conflicts resolved during integration
- **(c) Grouped PRs** — tasks grouped by file overlap, one PR per group

Option (b) replicates what was done manually during v0.4.0 enhancements (PR #12): 6 tasks touching shared files were cherry-picked sequentially into one branch, conflicts resolved once, single PR opened.

File overlap detection can reuse the data already computed by `plan_execution` in parallelization-adapter.sh (the `groups` field already clusters tasks by shared files).

Discovered during v0.4.0 sprint: 6 parallel tasks produced worktree branches that all conflicted on wizard.sh, mcp-detector.sh, and autopilot-task.md. Manual bundling into one PR avoided the cascade.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 autopilot-sprint Step 5 detects file overlap between planned tasks and shows a warning
- [ ] #2 When overlap is detected, user is offered PR strategy choice: separate (a), bundled (b), grouped (c)
- [ ] #3 Option (b) creates an integration branch, cherry-picks each task's commit sequentially, resolves conflicts, and opens a single PR listing all tasks
- [ ] #4 Option (c) groups tasks by file overlap and opens one PR per group
- [ ] #5 Default behavior (a) is unchanged from current — no regression
- [ ] #6 bats tests cover the overlap detection logic
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
- [ ] #2 Manual smoke test with 2+ tasks sharing a file confirms bundled PR workflow
<!-- DOD:END -->
