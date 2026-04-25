---
id: DRAFT-1
title: '[idea] Skill: release-test-count-resolver'
status: Draft
assignee: []
created_date: '2026-04-25 15:48'
labels:
  - idea
  - skill
  - automation
  - from-retrospective
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Idea emerged from session retrospective 2026-04-25. Pattern observed 3 times in the same session (PRs #15, #16, #17 merge resolution).

When merging a feature branch into main and there is a conflict on the `Current state: N tests` line in README.md, the resolution is mechanical:
1. Read the count currently on origin/main (post-merge of any earlier PRs)
2. Run `bats tests/lib/ | grep -c "^ok "` for the actual count on the branch
3. Compute final = main_current + (branch_current - branch_baseline)
4. Resolve the `<<<<<<< HEAD ... ======= ... >>>>>>>` marker by replacing with the correct line
5. Verify that the count in README matches the bats output, fail-fast on divergence
6. Commit `Merge main into <branch> (resolve README test count: N)`

Generalises to any repo that tracks a test count in README. Likely useful for claude-autopilot, plugin-dev, future plugins, life-os, bnb-toolkit.

Trigger phrases:
- "I have a conflict on the README after merge"
- "resolve the test count in the README"
- "merge main into feature branch"

Effort: low (~30 min). 80% bash, 20% conflict marker parsing.

Why it matters: this exact pattern recurred 3x in one session and is documented in CLAUDE.md as a known gotcha. Each manual resolution costs ~5 commands and one verification step. Multiplier across releases is significant.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 #1 Skill at ~/.claude/skills/release-test-count-resolver/SKILL.md with frontmatter (name, description, when-to-use)
- [ ] #2 #2 Detects the README test count line via regex (handles `Current state: N tests` and similar variants)
- [ ] #3 #3 Computes the correct final count from git diffs, validates against actual bats output
- [ ] #4 #4 Resolves the conflict marker idempotently and produces a clean merge commit
- [ ] #5 #5 Fails fast with a clear message if the README count diverges from the bats output
<!-- AC:END -->
