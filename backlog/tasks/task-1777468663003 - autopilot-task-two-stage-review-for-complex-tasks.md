---
id: TASK-1777468663003
title: 'autopilot-task: two-stage review (spec compliance + code quality) for complex tasks'
status: To Do
assignee: []
created_date: '2026-04-29 13:30'
labels:
  - enhancement
  - command
  - quality
dependencies:
  - TASK-1777468663001
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/autopilot-task` currently runs a single review pass at the end of the inner loop: code-simplifier subagent (if `simplify.mode == auto`) and security-reviewer subagent. Both run AFTER the implementation is complete; neither runs DURING the implementation. Drift between the task's acceptance criteria and what was actually built is only caught at the end, when fixes are expensive.

`superpowers:subagent-driven-development` runs TWO reviewers between every implementation step: a spec compliance reviewer (does the code match the spec/AC?) and a code quality reviewer (is the code well-built?). This intercepted 2 real bugs during the 2026-04-29 fix sprint: one preexisting (Draft normalization), one introduced by the plan itself (JQL double-AND). Without per-step review they would have reached the final PR.

Adopt the two-stage review pattern in autopilot, gated on complexity to avoid overhead on simple tasks:

- For `complex` and `epic` tier: after each TDD cycle (RED → GREEN → commit), spawn spec-compliance-reviewer + code-quality-reviewer subagents. If either flags issues, the implementer fixes and the reviewers re-review until approved.
- For `standard` and `simple` tier: keep current behavior (final-only review).

Reviewer prompts can be adapted from `superpowers/skills/subagent-driven-development/{spec-reviewer,code-quality-reviewer}-prompt.md` but must be parameterized for autopilot's context: the spec authority is the task's acceptance criteria (not a separate spec doc), and project conventions are bash 3.2 / BSD coreutils.

Depends on TASK-1777468663001 (TDD strict step) — the per-step review only makes sense when there are well-defined steps to review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Two new prompt templates exist under `skills/autopilot/` (or `commands/`) for spec-compliance-reviewer and code-quality-reviewer, parameterized for autopilot's context
- [ ] #2 `commands/autopilot-task.md` Step 6 (inner loop) is updated: when complexity is `complex` or `epic`, after each commit run both reviewers; loop on issues until approved
- [ ] #3 The reviewer subagents receive: the diff of the latest commit, the task's acceptance criteria as spec authority, and the project conventions (bash 3.2, BSD sed)
- [ ] #4 If a reviewer reports issues, the same implementer subagent (or a new one with the issue list) fixes them; reviewer re-runs until approved
- [ ] #5 Standard / simple tier tasks bypass two-stage review entirely (current single-pass behavior preserved)
- [ ] #6 Manual smoke: a `complex` task that includes an intentional acceptance-criterion mismatch is rejected by the spec reviewer until fixed
- [ ] #7 PR description documents the per-step review trace (which reviewer flagged what, how many iterations)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Reviewer prompt templates committed and referenced from the command
- [ ] #2 Smoke test on a real `complex` task documented
- [ ] #3 Bats suite green; new tests cover the dispatch logic for complex vs standard
- [ ] #4 No noticeable latency regression on `standard` tier tasks (review path skipped)
<!-- DOD:END -->
