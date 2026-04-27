---
id: TASK-1777298431002
title: 'autopilot-sprint: document grouped PR strategy semantics in sequential mode'
status: To Do
assignee: []
created_date: '2026-04-27 16:00'
labels:
  - documentation
  - skill
  - sprint-strategy
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The `commands/autopilot-sprint.md` command documents the grouped PR strategy assuming parallel worktree execution: "spawn one subagent per group… cherry-pick each task's commit sequentially into integration/sprint-<timestamp>-group<N>." But what happens when grouped is chosen AND the planner has forced sequential mode (e.g. via the v0.6.0 git-version-check fallback)?

In the v0.7.0 follow-up sprint (2026-04-27, this very session) the user picked grouped + sequential. I had to invent the interpretation on the fly: "execute the cluster's tasks sequentially on the same integration branch, then open one PR per cluster." It worked, but a different Claude in a future sprint could interpret it differently — e.g. open one PR per task and reject the grouped intent, or try to cherry-pick from non-existent worktree branches and crash.

The command spec needs an explicit Step 6d (or extended 6c) covering the cross-product:

| Strategy chosen | Execution mode | Behavior |
|---|---|---|
| separate | parallel | 6b — one subagent + one PR per task |
| separate | sequential | 6a — one task at a time + one PR per task |
| bundled | parallel | 6c — worktrees + cherry-pick into one branch |
| bundled | sequential | NEW — sequential commits on one integration branch + one PR |
| grouped | parallel | 6c — worktrees + cherry-pick per cluster |
| grouped | sequential | NEW — sequential commits on per-cluster integration branches + N PRs |

The "NEW" rows are the gap. Document them so the behavior is deterministic regardless of which sub-Claude executes the sprint.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 commands/autopilot-sprint.md adds a 2x3 strategy/execution-mode matrix table
- [ ] #2 Each cell links to the Step section that handles it (6a/6b/6c/6d)
- [ ] #3 New Step 6d covers bundled+sequential and grouped+sequential explicitly
- [ ] #4 The text cites the v0.7.0 follow-up sprint as the case where the gap was first hit
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 No code changes — command spec only
- [ ] #2 Manual replay: re-read the spec and confirm a fresh-context Claude could interpret grouped+sequential identically to how it was actually executed in this session
<!-- DOD:END -->
