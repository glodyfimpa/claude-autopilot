---
id: TASK-1776163200002
title: autopilot-task should execute test plan items before marking done
status: To Do
assignee: []
created_date: '2026-04-15'
labels:
  - enhancement
  - quality
priority: high
dependencies: []
parent_task_id:
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
autopilot-task opens a PR with a test plan checklist in the body (Step 8), then immediately marks the task as done (Step 9). Manual smoke test items in the test plan are left unchecked, giving the reviewer an incomplete PR.

Add a new Step 8.6 between "Wait for CI" (Step 8.5) and "Mark done" (Step 9) that reads the PR body, identifies executable test plan items (bash commands, script invocations), runs each one, and updates the PR body with checked items and results. Only proceed to Step 9 if all test plan items pass.

This resolves a recurring behavioral issue where PRs are declared ready with unchecked test plan items. Identified during v0.4.0 session: PR #12 was delivered with 3 unchecked smoke tests that all passed when run — they just weren't run before handoff.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 autopilot-task.md includes a Step 8.6 "Execute test plan" between CI wait and mark-done
- [ ] #2 Step 8.6 reads the PR body, extracts unchecked items from the test plan section
- [ ] #3 For each item containing an executable command (bash, script path, bats), Claude runs it and captures pass/fail
- [ ] #4 PR body is updated via gh pr edit with checked items and result annotations
- [ ] #5 If any test plan item fails, task is NOT marked done — failure is surfaced to the user
- [ ] #6 Items that are not executable (manual verification, subjective checks) are flagged for user review
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
- [ ] #2 Manual smoke test: run autopilot-task on a sample task, verify PR body has all items checked before done
<!-- DOD:END -->
