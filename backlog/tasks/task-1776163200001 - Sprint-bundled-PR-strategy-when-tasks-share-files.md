---
id: TASK-1776163200001
title: Sprint bundled PR strategy when tasks share files
status: Done
assignee: []
created_date: '2026-04-15'
updated_date: '2026-04-25 15:31'
labels:
  - enhancement
  - architecture
dependencies: []
priority: medium
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
- [x] #1 autopilot-sprint Step 5 detects file overlap between planned tasks and shows a warning
- [x] #2 When overlap is detected, user is offered PR strategy choice: separate (a), bundled (b), grouped (c)
- [x] #3 Option (b) creates an integration branch, cherry-picks each task's commit sequentially, resolves conflicts, and opens a single PR listing all tasks
- [x] #4 Option (c) groups tasks by file overlap and opens one PR per group
- [x] #5 Default behavior (a) is unchanged from current — no regression
- [x] #6 bats tests cover the overlap detection logic
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped via PR #17 (https://github.com/glodyfimpa/claude-autopilot/pull/17). New `lib/file-overlap-detector.sh` exposes `extract_files_from_text`, `extract_files_from_task`, `compute_overlap`, `group_by_overlap`, `recommend_pr_strategy` — all pure JSON-in/JSON-out. `commands/autopilot-sprint.md` gets Step 5.1 (detection + strategy prompt when overlap is found) and Step 6c (bundled and grouped execution flows: per-task subagents stop at the local commit, parent process cherry-picks into integration branch, resolves conflicts once, runs full test suite, opens ONE PR per cluster). Replicates the manual cherry-pick sequence used during the v0.4.0 sprint (PR #12) where 6 overlapping tasks were bundled into a single PR. 15 bats tests cover overlap detection, transitive grouping (union-find), and strategy recommendation. BSD/macOS quirk caught: `printf '%c' 96` does NOT produce a backtick on bash 3.2 — it prints "9" (first char of "96"). Fix: `$'\x60'` for backtick literals in bats tests.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 All bats tests green
- [x] #2 Manual smoke test with 2+ tasks sharing a file confirms bundled PR workflow
<!-- DOD:END -->
