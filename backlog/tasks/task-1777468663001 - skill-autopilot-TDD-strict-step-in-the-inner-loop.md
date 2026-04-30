---
id: TASK-1777468663001
title: 'skill autopilot: TDD strict step in the inner loop'
status: Done
assignee: []
created_date: '2026-04-29 13:30'
updated_date: '2026-04-30 13:41'
labels:
  - enhancement
  - skill
  - tdd
  - quality
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The autopilot skill (`skills/autopilot/SKILL.md`) currently describes the inner loop as `ANALYZE → PLAN → IMPLEMENT → quality gates`. TDD is not explicitly required; the skill suggests it but doesn't enforce it. In practice this means the implementer subagent (during `/autopilot-task` or `/autopilot-sprint`) can write code-first and tests-after, missing the design feedback that test-first provides.

Discovered during the 2026-04-29 fix sprint for `task_storage_list`: the same fix was implemented via `superpowers:subagent-driven-development` which enforces TDD strict (test failing FIRST → minimum implementation → green). That discipline caught 2 real bugs (Draft normalization, JQL double-AND) that autopilot's loose ordering would not have surfaced.

Promote TDD from suggestion to mandatory step in the skill, gated on task complexity:

- For `complex` and `epic` tier: TDD strict is mandatory (write failing test → prove RED → implement → prove GREEN → commit per logical unit).
- For `standard` and `simple` tier: keep current flexibility (TDD recommended, not enforced) so trivial changes don't pay the round-trip cost.

The skill already calls `estimate_complexity`. The complexity tier is available before the inner loop starts; gate the TDD-strict requirement on it.

The change is markdown-only (no shell code touched). Cost is small, value is large for the kind of fix that surfaced the bug.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `skills/autopilot/SKILL.md` Inner Loop section explicitly defines a TDD strict sub-flow (RED → minimal impl → GREEN → refactor → commit) for `complex` and `epic` tier tasks
- [ ] #2 The skill states clearly that TDD strict is OPTIONAL for `standard` and `simple` tier tasks
- [ ] #3 The skill references the existing `estimate_complexity` output as the gate, not a separate config flag
- [ ] #4 The IMPLEMENT step in the inner loop is updated to call out test-first explicitly when in TDD-strict mode
- [ ] #5 Manual smoke: a `complex` task implemented through `/autopilot-task` produces commits where the test commit precedes (or is co-located with) the implementation commit, verified by reading `git log` after a real run
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in PR #36 (commit b6aa3ce). The autopilot inner loop now requires TDD strict (RED → GREEN → REFACTOR → COMMIT per logical unit) for tasks at `complex` or `epic` complexity tier. For `standard` and `simple` tier the previous flexibility is preserved. The gate is the existing `estimate_complexity` output (no new config flag). Added doc-only/markdown-only edge case and "complexity reassessment" escape hatch for misclassified tasks.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Skill text is unambiguous about when TDD strict is mandatory and when it is optional
- [ ] #2 No regression in autopilot bats suite (skill change is doc-only, but verify the suite stays at the current green count)
- [ ] #3 Smoke test on a real `complex` task documented in the PR
<!-- DOD:END -->
