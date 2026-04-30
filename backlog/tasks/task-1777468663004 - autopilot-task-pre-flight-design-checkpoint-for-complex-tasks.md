---
id: TASK-1777468663004
title: 'autopilot-task: pre-flight design checkpoint for complex tasks'
status: Done
assignee: []
created_date: '2026-04-29 13:30'
updated_date: '2026-04-30 13:42'
labels:
  - enhancement
  - command
  - workflow
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/autopilot-task` jumps from "fetch task" → "create branch" → "implement". The implementer subagent receives the task description and acceptance criteria as the only design input. If the task description is ambiguous, missing key constraints, or has design tradeoffs that aren't yet decided, the subagent picks one path silently and the user discovers the wrong choice at PR review time.

`superpowers:brainstorming` runs a 7-step Socratic dialogue before any code is written. For autopilot the full flow is overkill — most tasks in a backlog are already well-defined. But for `complex` tier tasks (where ambiguity hurts most), an opt-in pre-flight checkpoint adds value:

1. Show the user the task description + acceptance criteria.
2. Identify likely design ambiguities (signals: "X or Y", multiple valid approaches in the AC, AC says "should" without specifying how).
3. Offer: "this task has N design ambiguities. Want to brainstorm them now via `superpowers:brainstorming` before I start, or proceed with my best judgment?"
4. Default = proceed (autopilot is autonomous by design).
5. If user opts in, spawn `superpowers:brainstorming` skill, capture the resulting design as a short markdown doc next to the task, then resume `/autopilot-task` with the design doc as additional context.

Gating: only show the checkpoint for `complex` and `epic` tier. Never for `standard` or `simple`. The checkpoint must be a single yes/no — not the full superpowers flow inline.

This is the lightest possible bridge between autopilot's autonomous default and superpowers' design-first discipline. It gives the user a chance to inject thinking on the tasks where it matters, without slowing down the rest of the sprint.

Depends on the existing `complexity-estimator.sh` output (no new code in lib/).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `commands/autopilot-task.md` adds a Step 3.5 (between "Estimate complexity" and "Create branch") that triggers ONLY when complexity is `complex` or `epic`
- [ ] #2 The checkpoint shows the user a single yes/no: "Brainstorm design via superpowers:brainstorming before starting?" with default = no
- [ ] #3 If user says no, proceed unchanged (no friction added on the no-path)
- [ ] #4 If user says yes, the `superpowers:brainstorming` skill is invoked. Its output is captured as a short markdown design doc in `docs/superpowers/specs/<date>-<task-ref>-design.md` (or equivalent path) before resuming
- [ ] #5 The implementer subagent receives the design doc as additional context after a yes-path checkpoint
- [ ] #6 The checkpoint NEVER triggers for `standard` or `simple` tier tasks (autopilot's speed is preserved for the common case)
- [ ] #7 If `superpowers` is not installed, the checkpoint silently degrades: shows a one-line warning ("brainstorming skill not available, proceeding") and continues
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in PR #36 (commit e0f170d). `/autopilot-task` Step 3.5 now scans `complex|epic` tasks for design-ambiguity signals and resolves them deterministically via a tie-breaker chain (existing pattern → portability → smaller diff → first-listed option). Each resolved ambiguity is documented in the PR body's `## Design ambiguities resolved` table for post-hoc review. AC reinterpretation: original spec called for a yes/no prompt; this conflicted with TASK-1777750800005 (zero-prompt hand-off, also added to this sprint). Resolved via deterministic resolution + PR-body documentation instead of mid-flight prompt. Step 3 (Estimate complexity) also rewritten to remove its prompts (epic tier no longer stops; surfaces a "Complexity reassessment" note in PR body recommending a follow-up split). Reinterpretation explicitly documented in commit message and PR body for reviewer attention. Approved by user.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Step 3.5 documented in the command file with explicit decision tree
- [ ] #2 Manual smoke: complex task with checkpoint=yes produces a design doc and includes it in the PR; complex task with checkpoint=no proceeds unchanged
- [ ] #3 Standard task does NOT see the checkpoint
- [ ] #4 Graceful fallback when superpowers is missing
<!-- DOD:END -->
