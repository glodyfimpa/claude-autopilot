---
id: TASK-1777664400002
title: Recovery flow when direct push to main is blocked by policy
status: To Do
assignee: []
created_date: '2026-04-25'
labels:
  - enhancement
  - tooling
priority: low
dependencies: []
parent_task_id:
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In Auto mode, Claude can commit directly to local `main` then attempt to push. When repo policy enforces "PRs only" (no direct push to default branch), the push is blocked and Claude must manually recover: create a release branch from the local commit, hard-reset main back to the remote SHA, push the branch, open a PR.

This recovery sequence is mechanical and error-prone if done from scratch. Build a wrapper command (or extend `commit-commands:commit-push-pr`) that:
1. Detects the "direct push to main blocked" scenario (push fails AND HEAD is on default branch AND there's a local commit ahead of origin)
2. Proposes the recovery flow: branch name suggestion based on commit message, branch creation, main reset, push, PR creation with the original commit message as PR body
3. Executes after confirmation, or autonomously if Auto mode is active

Discovered during v0.4.0 release session 2026-04-25: bumped `plugin.json` directly on main, push was blocked by `claude-code` policy. Manual recovery took ~5 commands and required reasoning about reset target.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Detects blocked-push scenario by checking push exit code + HEAD branch + ahead-of-origin status
- [ ] #2 Proposes branch name from commit message (e.g. "chore: release v0.4.0" → `release/v0.4.0`)
- [ ] #3 Creates branch, resets main to `origin/main`, pushes branch, opens PR with original commit body
- [ ] #4 Preserves any local tags pointing at the moved commit (recreates them after merge)
- [ ] #5 Bails out safely if working tree is dirty or there are multiple commits to recover
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Manual smoke test: commit directly on main, run command, verify PR opened and main reset
- [ ] #2 Bats test (or shell test) covers detection logic with mocked git state
<!-- DOD:END -->
