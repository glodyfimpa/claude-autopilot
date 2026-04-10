---
id: TASK-1.3
title: SessionStart hook with sprint-context injection (Echofold phase 4)
status: To Do
assignee: []
created_date: '2026-04-10 12:58'
labels:
  - hooks
  - echofold-phase-4
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a SessionStart hook that writes a per-session sprint-context.md file before Claude starts working on a ticket. Echofold phase 4 uses this pattern so every subagent (especially in parallel worktree runs) starts with the same project rules, architecture notes, and current sprint goals injected at the top of the context window. Without this hook, parallel subagents each rebuild context from scratch and drift apart.

The hook reads the ticket metadata (from the task storage adapter, already loaded) and produces a sprint-context.md at the root of each worktree with: project rules summary, current sprint goals, acceptance criteria for the active ticket, and links to relevant docs.

Files touched: only hooks/session-start.sh (new), hooks.json (register), and tests/lib/session-start.bats (new). Does not touch any lib/ adapter. Fully parallelizable with every other adapter task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 hooks/session-start.sh reads the active task ref and writes sprint-context.md at the worktree root
- [ ] #2 hooks.json registers the hook under the SessionStart event
- [ ] #3 The generated sprint-context.md includes: project summary, sprint goal, current ticket title+criteria, doc links
- [ ] #4 If no active task is set, the hook writes a minimal context with just project rules and exits 0
- [ ] #5 tests/lib/session-start.bats covers the three cases: active task, no active task, malformed task JSON
- [ ] #6 README Structure section lists the new hook
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
<!-- DOD:END -->
