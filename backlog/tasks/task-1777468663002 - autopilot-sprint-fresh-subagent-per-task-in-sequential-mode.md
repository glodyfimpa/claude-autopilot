---
id: TASK-1777468663002
title: 'autopilot-sprint: fresh subagent per task in sequential mode'
status: In Progress
assignee: []
created_date: '2026-04-29 13:30'
updated_date: '2026-04-30 11:34'
labels:
  - enhancement
  - command
  - architecture
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/autopilot-sprint` Step 6a (sequential execution) currently iterates groups by recursively calling `/autopilot-task <ref>` in the same session. The sub-Claude executing the sequential sprint inherits the full session context across tasks: prompts, prior tool results, scratch state. Cross-task drift is possible — instructions from task N can subtly leak into task N+1.

Step 6b (parallel mode) already does the right thing: spawns each task in an isolated subagent with `isolation: "worktree"` via the `Agent` tool. Each task starts with a fresh, controlled context built by the controller.

Validated 2026-04-29 during the fix sprint: 11 tasks via `superpowers:subagent-driven-development` ran in 11 fresh isolated subagents (sequential, but each isolated). Zero cross-task drift; 2 real bugs caught by the per-task review. The pattern works in sequential mode too.

Make sequential mode (Step 6a) match the architecture of parallel mode (Step 6b): spawn one isolated subagent per task even when running them one at a time. The controller stays in the main session and curates each subagent's prompt with the exact context that task needs. No more recursive `/autopilot-task` invocation.

The provider abstraction, complexity estimation, file-overlap detection, and quality gates all stay where they are. Only the dispatch mechanism in Step 6a changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `commands/autopilot-sprint.md` Step 6a is rewritten to spawn one isolated subagent per task using the `Agent` tool, instead of recursively invoking `/autopilot-task`
- [ ] #2 Each sequential subagent receives a curated prompt with: task ref, task description, acceptance criteria, project conventions (bash 3.2, BSD sed), and the path of its working directory
- [ ] #3 The controller (main session) waits for each subagent to complete before dispatching the next; failures stop the batch, as today
- [ ] #4 The total token usage of a sequential sprint should be lower than today's recursive `/autopilot-task` model (no cumulative context bloat) — measure on a real 5+ task run
- [ ] #5 No regression in `tests/lib/autopilot-sprint*.bats` (existing tests should still pass; new tests may be needed for the dispatch change)
- [ ] #6 Document the parity between sequential and parallel subagent models in the command file so future readers see they share the same pattern
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Step 6a refactor: dispatch via `Agent` tool, prompt template documented in the command file
- [ ] #2 Smoke test: run `/autopilot-sprint` in sequential mode on at least 2 real ready tasks; verify each subagent runs in isolation (no shared state visible)
- [ ] #3 Bats suite green
- [ ] #4 PR description includes a before/after diagram of the dispatch model
<!-- DOD:END -->
