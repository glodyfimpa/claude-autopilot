---
id: TASK-1777750800001
title: 'autopilot-sprint: detect self-modification and skip smoke step (meta-circular)'
status: To Do
assignee: []
created_date: '2026-04-27 14:35'
labels:
  - enhancement
  - skill
  - robustness
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The real-data smoke test slot introduced in v0.6.0 (TASK-1777664400005) hits a catch-22 when the sprint task itself modifies `skills/autopilot/SKILL.md` or other plugin internals: the new step says "smoke against an external resource" but the task has no external resource by definition (it changes the skill that defines the rule).

In the v0.6.0 sprint this was handled manually: I marked PR #21 as "Smoke test: not applicable (internal state only)" in the PR body. The skill should detect this case automatically rather than relying on the implementer to remember.

Add a self-modification detector at step #10:

1. If `git diff --name-only main..HEAD` shows ANY of:
   - `skills/autopilot/**`
   - `commands/autopilot*.md`
   - `lib/*-adapter.sh` (the dispatch layer, not the providers)
   - `hooks/**`
   ...AND no files outside the plugin's own source tree, the smoke step is automatically marked as no-op.
2. The PR body section auto-fills with: `Smoke test: not applicable — task modifies the autopilot plugin itself (no external resource to exercise).`
3. The heuristic from v0.6.0 still applies for normal tasks (touches `lib/<x>-providers/`, `$HOME`, network, MCP).

This closes the meta-circular gap: the skill knows when it's modifying itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 skills/autopilot/SKILL.md adds a "Self-modification detection" subsection under "Real-data smoke test"
- [ ] #2 The detector lists the paths that count as plugin-internal (skills, commands, adapter dispatch layer, hooks)
- [ ] #3 The skill mandates auto-filling the `## Smoke test` section with the no-op explanation when self-modification is detected
- [ ] #4 The provider-touching path (`lib/<x>-providers/`) is explicitly NOT classified as self-modification — provider work still requires real-data smoke
- [ ] #5 README inner-loop description mentions the auto-detection
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Manual review: walk the v0.6.0 sprint and confirm PR #21 would have auto-classified, while PR #19 (touches lib/git-version-check.sh — a non-provider lib file) and PR #20 (touches lib/task-storage-providers/) would NOT
- [ ] #2 No regression on the existing real-data smoke step for normal tasks
<!-- DOD:END -->
