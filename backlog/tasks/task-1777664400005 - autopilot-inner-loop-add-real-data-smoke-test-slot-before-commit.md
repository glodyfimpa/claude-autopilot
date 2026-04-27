---
id: TASK-1777664400005
title: 'autopilot inner loop: add real-data smoke test slot before commit'
status: Done
assignee: []
created_date: '2026-04-25 15:37'
labels:
  - enhancement
  - tdd
  - robustness
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TDD with synthetic fixtures covers logic correctness but does not catch wrong assumptions about external data shapes. The 2026-04-25 sprint hit this on TASK-1777664400001 (plugin-cache-doctor): tests passed with a hand-written fixture that assumed `.plugins[name]` was a single object, but the real `~/.claude/plugins/installed_plugins.json` schema is `.plugins[name] = [array of install records]`. The bug was caught only by an opportunistic read-only smoke test against the real file — not by the test suite.

Add a new step in the autopilot inner loop (skills/autopilot/SKILL.md) between "all gates green" and "write task-complete marker":

1. If the task description mentions a real external resource (path under `~/`, URL, MCP-backed system), Claude must perform at least one read-only smoke call against that resource and capture the output in the PR body.
2. The smoke test can be a single `head`, `jq`, `curl -I`, or equivalent — point is to exercise the assumption, not to be exhaustive.
3. If the smoke output diverges from what the synthetic fixtures encode, the loop iterates: update the fixtures to match reality, re-run the gates.

The step is optional for tasks that operate on internal state only (e.g. pure refactors, doc-only changes). A simple heuristic: if the task touches a file under `lib/<x>-providers/` or reads anything from `$HOME` / a network resource, the smoke is required.

This complements TASK-1776163200002 (test plan execution) which runs items already declared in the PR body. The smoke test slot adds items proactively when the task implicates external data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 #1 skills/autopilot/SKILL.md inner loop adds a smoke-test step between gates-green and task-complete marker
- [x] #2 #2 The skill describes the heuristic for when smoke is required (external resource access)
- [x] #3 #3 The smoke output is captured in the PR body under a new `## Smoke test` section
- [x] #4 #4 If smoke reveals a fixture mismatch, the loop iterates with explicit reasoning surfaced to the user
- [x] #5 #5 The step is documented as a no-op for tasks operating on internal state only
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 #1 Manual validation: run /autopilot-task on a task that implicates an external resource (e.g. a new task-storage provider) and confirm the smoke step fires and captures real output
- [x] #2 #2 README updated to mention the smoke step in the inner-loop description
<!-- DOD:END -->
