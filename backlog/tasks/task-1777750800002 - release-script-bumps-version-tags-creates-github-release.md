---
id: TASK-1777750800002
title: 'release script: bumps version, tags, creates GitHub release in one command'
status: To Do
assignee: []
created_date: '2026-04-27 14:35'
labels:
  - enhancement
  - tooling
  - release
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The v0.6.0 release was assembled by hand: bump `.claude-plugin/plugin.json`, verify test count vs README, write a tag annotation, push the tag, write release notes, run `gh release create`. Each step is mechanical and easy to skip or get wrong (test count drift, missing tag annotation, mismatched release notes).

Add `scripts/release.sh` that takes a target version and runs the full flow:

1. Argument: target version (e.g. `0.7.0`). Validate against current version in `.claude-plugin/plugin.json` (must be greater).
2. Verify the working tree is clean and on `main`.
3. Run `bats tests/lib/` and capture the green count. Fail if any test fails.
4. Update `Current state: NNN tests` in README to match the captured count.
5. Update `version` in `.claude-plugin/plugin.json`.
6. Generate the changelog from `git log <previous_tag>..HEAD --format='%s'`, filtering for PR merge commits.
7. Open `$EDITOR` on a draft tag annotation prefilled with the changelog so the user can refine before tagging.
8. Commit the version bump + README update with message `chore: release vX.Y.Z`.
9. Create annotated tag `vX.Y.Z` from the user-edited message.
10. Push commit + tag.
11. Run `gh release create vX.Y.Z` with the same release notes.

Optionally accept `--dry-run` to print every step without executing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 scripts/release.sh exists, executable, takes a version argument
- [ ] #2 Refuses to run on a dirty working tree or a non-main branch
- [ ] #3 Refuses to run if the target version is not greater than the current one
- [ ] #4 Auto-updates README test count from the actual bats run
- [ ] #5 Generates a draft changelog from git log between the previous tag and HEAD
- [ ] #6 Opens $EDITOR for tag annotation refinement (skip with --no-edit)
- [ ] #7 Pushes commit + tag, then creates the GitHub release with matching notes
- [ ] #8 bats tests cover: argument validation, dirty tree refusal, version comparison, dry-run output
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
- [ ] #2 Manual smoke test: run scripts/release.sh 0.7.0-test-rc1 in a throwaway worktree and confirm the full flow works end-to-end (dry-run is fine — no real GitHub release)
- [ ] #3 README documents the script as the canonical release flow
<!-- DOD:END -->
