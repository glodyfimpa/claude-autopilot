---
id: TASK-1777750800004
title: 'autopilot skill: document canonical shell patterns for commit messages and test checks'
status: Done
assignee: []
created_date: '2026-04-27 14:35'
labels:
  - documentation
  - skill
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two recurring shell pitfalls keep tripping the inner loop, both already documented in the user's global CLAUDE.md but not in the autopilot skill itself:

1. **Commit messages with apostrophes / backticks fail when passed via heredoc.** The pattern `git commit -m "$(cat <<'EOF' ... EOF)"` collides with the quoting of nested apostrophes. Same problem with `gh pr create --body "$(cat ...)"`. Workaround: write to `/tmp/commit-msg.txt` then `git commit -F /tmp/commit-msg.txt`. Used 3 times manually in the v0.6.0 sprint after the first attempt failed.

2. **`bats tests/lib/ | grep -c "^not ok"` returns exit 1 on a fully green suite.** `grep -c` exits 1 when zero matches are found, regardless of `-c`. A suite with 335 ok and 0 not ok pipes to "0" then exits non-zero, which `run_in_background` reports as "failed" even though the suite is green. Canonical check: `grep -c "^ok "` (positive count, exits 0 if anything matched).

Add a "Shell pattern conventions" subsection to skills/autopilot/SKILL.md right after "Operating rules":

- For commit messages and PR bodies: ALWAYS use the file-based pattern (`git commit -F file`, `gh pr create --body-file file`) for any message that exceeds one line OR contains apostrophes, backticks, or other shell-special characters. Default to file-based when in doubt.
- For checking bats suite outcomes in scripts and background tasks: use `grep -c "^ok "` to count passes, and assert it matches the expected total. Do NOT chain on `grep -c "^not ok"` — its exit code is misleading on a green suite.

These are doc-only changes — no code. They prevent re-discovery of known traps every sprint.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 skills/autopilot/SKILL.md adds a "Shell pattern conventions" subsection
- [x] #2 The commit/PR-body pattern explicitly recommends `-F file` / `--body-file file` as default, not as fallback
- [x] #3 The bats grep pattern explicitly recommends `grep -c "^ok "` and warns against `grep -c "^not ok"`
- [x] #4 The subsection cites the v0.6.0 sprint as the case-study where both patterns were rediscovered manually
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 No code changes — doc only
- [x] #2 Manual review: confirm the patterns match what already lives in the user's global CLAUDE.md (single source of truth)
<!-- DOD:END -->
