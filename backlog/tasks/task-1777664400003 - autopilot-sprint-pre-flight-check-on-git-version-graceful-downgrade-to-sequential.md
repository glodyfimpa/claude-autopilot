---
id: TASK-1777664400003
title: >-
  autopilot-sprint: pre-flight check on git version + graceful downgrade to
  sequential
status: Done
assignee: []
created_date: '2026-04-25 15:36'
labels:
  - enhancement
  - robustness
  - skill
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When `autopilot-sprint` runs the parallel strategy, it spawns subagents with `isolation: "worktree"` which calls `git worktree add --no-track`. The `--no-track` flag was added in git 2.20. On older git (e.g. git 2.15 still shipped with macOS Xcode toolchains), the spawn fails with: `error: unknown option no-track`.

Currently the skill has no pre-flight check. The first subagent crash-stops with a confusing error and leaves the user without parallelization. Fallback to sequential is manual.

Add a check at the start of `autopilot-sprint` (after Step 1, before Step 2):

1. Run `git --version` and parse the version number
2. If `< 2.20`, log a clear warning: `git X.Y detected; parallel worktrees require git 2.20+. Falling back to sequential strategy.`
3. Override the planner output: `strategy = "sequential"` regardless of `plan_execution` recommendation
4. Continue Step 6a (sequential) instead of Step 6b (parallel)

This was hit during the 2026-04-25 sprint that implemented TASK-17776644000XX series — the parent session's git was 2.15 and no parallelization happened.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 #1 lib/git-version-check.sh exposes a function `git_supports_worktree_no_track` returning 0/1
- [x] #2 #2 autopilot-sprint Step 1.5 calls the check and overrides strategy to sequential when unsupported
- [x] #3 #3 The downgrade is logged with the detected git version and the required minimum (2.20)
- [x] #4 #4 bats tests cover: git 2.15 (downgrade), git 2.20 (no downgrade), git 2.42 (no downgrade), missing git binary (clear error)
- [x] #5 #5 Documentation in README mentions the git 2.20 requirement for parallel mode
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 #1 All bats tests green
- [x] #2 #2 Manual smoke test on a system with git < 2.20 confirms graceful sequential fallback (no crash)
<!-- DOD:END -->
