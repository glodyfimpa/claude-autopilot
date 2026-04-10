---
id: TASK-1.2
title: CI watchdog blocks task-complete marker until GitHub Actions finishes
status: To Do
assignee: []
created_date: '2026-04-10 12:57'
updated_date: '2026-04-10 12:58'
labels:
  - hooks
  - pr-flow
  - echofold-phase-5
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today the inner loop writes the task-complete marker as soon as the Stop hook gates pass and the security review is clean. The outer loop then commits, pushes, and opens the PR. This is premature: if GitHub Actions fails after the push (because the CI config runs checks that are stricter than our local gates, or because a platform-specific test breaks on the runner), the PR is already open and the task is already marked done.

Add a CI watchdog step between git push and the final "task done" state. The watchdog polls the GitHub Actions run for the head commit until it finishes, with a configurable timeout. If CI fails, the task stays in_progress and Claude is told the specific failure to fix.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New helper lib/ci-watcher.sh with wait_for_ci <ref> <timeout> function using gh api or gh run watch
- [ ] #2 Provider-aware: github uses gh run watch; gitlab/bitbucket stub returning 2
- [ ] #3 commands/autopilot-task.md step 8 calls ci-watcher after the push and before marking the task done
- [ ] #4 Configurable timeout in .autopilot-pipeline.json under pr_target.config.ci_timeout_minutes (default 15)
- [ ] #5 On CI failure, the task status returns to in_progress and the failure log is surfaced to Claude
- [ ] #6 tests/lib/ci-watcher.bats covers happy path, timeout, failure, and stub providers
- [ ] #7 README.md Decision criteria section documents the 'task done only when CI passes' rule
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
- [ ] #2 Manual smoke test: push a commit that fails CI and verify the watchdog rolls back state
<!-- DOD:END -->
