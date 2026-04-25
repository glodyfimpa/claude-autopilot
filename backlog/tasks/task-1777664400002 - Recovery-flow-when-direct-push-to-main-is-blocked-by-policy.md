---
id: TASK-1777664400002
title: Recovery flow when direct push to main is blocked by policy
status: Done
assignee: []
created_date: '2026-04-25'
updated_date: '2026-04-25 15:30'
labels:
  - enhancement
  - tooling
dependencies: []
priority: low
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
- [x] #1 Detects blocked-push scenario by checking push exit code + HEAD branch + ahead-of-origin status
- [x] #2 Proposes branch name from commit message (e.g. "chore: release v0.4.0" → `release/v0.4.0`)
- [x] #3 Creates branch, resets main to `origin/main`, pushes branch, opens PR with original commit body
- [x] #4 Preserves any local tags pointing at the moved commit (recreates them after merge)
- [x] #5 Bails out safely if working tree is dirty or there are multiple commits to recover
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped via PR #15 (https://github.com/glodyfimpa/claude-autopilot/pull/15). New `/recover-blocked-push` command automates recovery when a direct push to `main` is rejected by repo policy (PRs-only). Library `lib/push-recovery.sh` exposes pure detection (`detect_blocked_push` returns JSON with blocked/branch/commits_ahead/dirty/multi_commit/branch_suggestion) and `recover_blocked_push` which moves the local commit to a new branch and resets main to origin. Bails out on dirty tree, multi-commit, or non-default branch. Tags are preserved (git tags follow SHAs). Conventional-commit prefixes (feat/fix/chore/docs/refactor/test/perf/build/ci/style) recognised; special case `chore: release vX.Y.Z` → `release/vX.Y.Z`. 17 bats tests cover slugify/detect/recover variants with mocked git state in tmpdir.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Manual smoke test: commit directly on main, run command, verify PR opened and main reset
- [x] #2 Bats test (or shell test) covers detection logic with mocked git state
<!-- DOD:END -->
