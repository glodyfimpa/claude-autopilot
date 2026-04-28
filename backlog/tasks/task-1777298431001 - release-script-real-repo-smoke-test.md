---
id: TASK-1777298431001
title: 'release script: add real-repo smoke test that catches dirty-tree on actual main'
status: Done
assignee: []
created_date: '2026-04-27 16:00'
labels:
  - testing
  - tooling
  - release
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The v0.7.0 release attempt (2026-04-27) failed on the first real run of `scripts/release.sh` with `ERROR: working tree is not clean. Commit or stash changes first.` because the `.claude/` directory at repo root was untracked. The release script's existing test coverage (28 tests in `tests/lib/release-utils.bats` + `tests/lib/release-script.bats`) used a fake-git-repo fixture that did not have a `.claude/` directory, so this scenario was never exercised.

The gap: bats tests cover the script's logic against a controlled tmpdir, but they don't catch interactions with state files Claude Code (or any other tool) may drop into the real repo between releases. This is a third tier of test that's missing.

Add a `tests/lib/release-script-realrepo.bats` (or extend `release-script.bats` with a new section) that runs the script in `--dry-run` mode against a temporary clone of the actual claude-autopilot repo:

1. `git clone --depth=1 file://$PLUGIN_ROOT $TEST_TMPDIR/clone`
2. `cd $TEST_TMPDIR/clone`
3. `./scripts/release.sh 0.99.0 --dry-run --no-edit` → must succeed (clone is clean by definition)
4. `touch .claude/something-untracked` → re-run → must fail with the dirty-tree error
5. `mkdir -p .vscode && touch .vscode/settings.json` → re-run → must also fail (other state-file scenarios)
6. Document what the test catches and why a fake-git fixture is insufficient.

Optionally: also add a "self-test" mode invoked as `scripts/release.sh --self-check` that lists every untracked file the dirty-tree check would reject, so future CI can flag accidentally-committed-but-not-gitignored files before release time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New bats file (or section) clones the real repo into TEST_TMPDIR and runs scripts/release.sh against it
- [ ] #2 Test verifies that an untracked .claude/ file triggers the dirty-tree refusal
- [ ] #3 Test verifies that an untracked .vscode/ file (or any common IDE state) triggers the dirty-tree refusal
- [ ] #4 Test asserts the clean-clone case succeeds in --dry-run
- [ ] #5 The test file documents WHY the fake-git fixture is insufficient (cite the v0.7.0 incident)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green (suite count grows by the new tests)
- [ ] #2 Manual replay: introduce a stale untracked file in the working tree, confirm release.sh refuses to run
<!-- DOD:END -->
