---
id: TASK-1777750800005
title: >-
  autopilot: enforce zero-prompt hand-off in auto-mode (deterministic scope
  filtering + decision points)
status: In Progress
assignee: []
created_date: '2026-04-30 11:38'
updated_date: '2026-04-30 11:42'
labels:
  - enhancement
  - command
  - ux
  - spec
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All autopilot commands (`/autopilot-sprint`, `/autopilot-task`, `/autopilot-prd`, `/autopilot-run`) must operate in true hand-off mode when auto-mode is active: the user launches the command, walks away, comes back to a PR. ZERO interactive prompts during execution.

Today the spec leaves room for prompts that defeat hand-off:

1. `/autopilot-sprint` Step 6 is documented as "the only confirmation gate" — in auto-mode it must NOT be a prompt; it's a decision point where the controller declares strategy + integration branch + ordering and proceeds.
2. When the task storage contains tasks with scope ambiguities (explicit unsatisfied preconditions in the task body, deliverables targeting other repos, contradictory dependency declarations), today's spec implies a clarification dialog. In auto-mode the autopilot must instead apply deterministic exclusion rules and surface the exclusions in the run report, never as a question.

Concrete user-confirmed decisions (2026-04-30 sprint v0.7.x):

- Auto-mode = hand-off. Zero prompt during execution. Always.
- Scope-ambiguity tasks are excluded by deterministic rules, not by asking the user. Exclusions are reported in the run summary and final PR description with one-line reasoning per excluded task.
- The user can re-include any excluded task with a manual `/autopilot-task <ref>` after the sprint ends.

Deterministic exclusion rules (initial set; extend as new patterns emerge):

- **Rule A — explicit precondition not satisfied**: task description contains a phrase like "don't build until X happened" or "wait until N more Y" and the condition is not derivable as TRUE from the current repo/backlog state → EXCLUDE with reason "explicit precondition unmet: <quote>".
- **Rule B — deliverable outside current repo**: task description names a deliverable path that is clearly outside the working tree (e.g. "validation report on Freelance Compass" while we're in claude-autopilot) → EXCLUDE with reason "deliverable targets external repo: <name>".
- **Rule C — circular or unsatisfiable dependencies**: task A depends on task B and B depends on A, or A depends on a task that is `done` but not present in current backlog → EXCLUDE with reason "broken dependency graph: <details>".
- **Rule D — contradictory acceptance criteria**: ACs reference incompatible options without resolution (rare; surface as exclusion only when fully unsatisfiable, not when "design choice between X and Y" — those proceed with implementer's best judgment) → EXCLUDE with reason "contradictory ACs: <details>".

Tasks NOT matching any rule proceed normally. Note: ordinary design tradeoffs ("X or Y? both valid") do NOT trigger exclusion — the implementer subagent picks one with reasoning, documented in the PR. Only fully unsatisfiable situations exclude.

The check runs once at sprint start (between Step 3 complexity estimation and Step 4 plan execution). Excluded tasks remain in `ready` status (not flipped to anything else) so the user can rerun them manually.

Markdown-only change to the four command files. Possibly a tiny helper in `lib/` to apply Rule A/B detection from task description text (regex-driven, conservative). No new dependencies.

Why now: the v0.7.1 sprint surfaced exactly this gap — the controller asked the user "do you want to exclude TASK-1.9 and TASK-1777298431003?" (scope ambiguity) and "should I proceed with the spawn?" (batch gate). User correctly objected that auto-mode is hand-off and both prompts are the wrong default. Spec must encode this so every user gets the same behavior, not just my installation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `commands/autopilot-sprint.md` Step 6 is rewritten so that in auto-mode it is a decision point (declare strategy + integration branch + ordering, then proceed), NOT a prompt. The 'confirmation gate' wording is replaced with 'decision point declared' wording.
- [ ] #2 `commands/autopilot-sprint.md` adds a new Step 3.5 'Deterministic scope filtering' that applies Rules A/B/C/D above, removes excluded tasks from the planner input, and surfaces them in a 'Excluded from this sprint' section of the run summary.
- [ ] #3 Excluded tasks are reported in the final PR description with a table: task ref, exclusion rule, one-line reason, command to re-include manually.
- [ ] #4 `commands/autopilot-task.md`, `commands/autopilot-prd.md`, `commands/autopilot-run.md` are reviewed for any other interactive prompts and converted to deterministic decision points + reports. Document the audit in the PR.
- [ ] #5 If a regex-driven helper is added under `lib/` (e.g. `lib/scope-filter.sh`) it has bats coverage for each rule with at least one positive and one negative test case.
- [ ] #6 README 'How autopilot makes decisions' (or new) section documents the four exclusion rules with examples so users understand WHY a task got skipped in their report.
- [ ] #7 Smoke test: a backlog containing one Rule-A task and one Rule-B task is filtered automatically, the sprint runs only on the remaining tasks, the final PR description lists the two exclusions with reasons.
- [ ] #8 Zero new prompts introduced. Existing prompts in non-autopilot paths (e.g. /autopilot-configure wizard) are unchanged — the rule applies only to the four hands-off commands.
<!-- AC:END -->
