---
id: DRAFT-2
title: >-
  [idea] Improve autopilot-task: TDD bash plugin scaffold for bats-based
  features
status: Draft
assignee: []
created_date: '2026-04-25 15:48'
labels:
  - idea
  - skill-improvement
  - from-retrospective
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Idea emerged from session retrospective 2026-04-25. Pattern observed 4 times (TASKs cache-doctor, push-recovery, test-plan-runner, file-overlap-detector all followed nearly identical TDD scaffolding sequences).

The existing /autopilot-task skill works but is not optimised for the sub-category "bash plugin feature with bats tests". For this category, the scaffolding is repetitive:

1. Create tests/lib/<name>.bats with `load "../helpers/test_helper"` + setup/teardown tmpdir + N test stubs (RED)
2. Verify it fails for the right reason
3. Create lib/<name>.sh with shebang and placeholder functions
4. RED→GREEN loop: read failure, propose fix, re-run
5. When all green, create commands/<name>.md if the task exposes a slash command
6. Bump README test count
7. Commit with structured message (acceptance criteria, DoD, smoke test)
8. push + gh pr create with body-file

Two ways to implement:
- (a) Extend the existing /autopilot-task skill with a "bash-bats" stack detection that triggers this scaffold
- (b) Standalone skill /autopilot-task-bash-bats that the user invokes when the task is known to be in this category

Option (a) is preferred: keeps the autopilot surface unified and lets the stack detector decide. Stack detection = if task description references lib/*.sh OR tests/lib/*.bats, use this scaffold.

Effort: medium (1-2 hours). Mostly templating + integration with the existing autopilot-task flow.

Why it matters: 4 nearly-identical TDD cycles in one sprint. Saves ~5 minutes per task on the boilerplate (boring) parts so the model can focus on the logic. Validated pattern on a real backlog (claude-autopilot itself).

Lower priority than the test-count-resolver because it does not unblock anything; it just makes a working flow faster.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 #1 Stack detector identifies 'bash-bats' tasks (lib/*.sh + tests/lib/*.bats hint in task description or AC)
- [ ] #2 #2 When detected, autopilot-task uses a scaffolded bats template instead of starting from scratch
- [ ] #3 #3 Template includes: load helper, setup_isolated_tmpdir, teardown, N test stubs derived from acceptance criteria
- [ ] #4 #4 The skill still requires user confirmation before committing/pushing (no behavioural regression)
- [ ] #5 #5 README test count bump is automatic (delta = number of new tests added)
<!-- AC:END -->
