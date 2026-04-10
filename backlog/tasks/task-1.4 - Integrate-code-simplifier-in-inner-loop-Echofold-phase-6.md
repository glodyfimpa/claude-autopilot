---
id: TASK-1.4
title: Integrate code-simplifier in inner loop (Echofold phase 6)
status: To Do
assignee: []
created_date: '2026-04-10 12:58'
labels:
  - skill
  - inner-loop
  - echofold-phase-6
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Echofold phase 6 runs a code-simplifier pass after implementation and before the security review. Today our /simplify can be invoked manually but is not part of the autopilot inner loop. Make it an automatic step that fires after the gates pass.

Two options to implement:
1. Call the claude-code code-simplifier plugin via a skill invocation in skills/autopilot/SKILL.md
2. Bundle a lightweight simplifier sub-skill inside the autopilot plugin itself

Preferred: option 1, because it keeps the autopilot plugin focused and lets users swap simplifiers. The autopilot skill instructs Claude to invoke the simplifier subagent at the right step, and a config flag in .autopilot-pipeline.json allows opting out (simplify_mode: auto | manual | off).

Files touched: skills/autopilot/SKILL.md (add step between gates and security), lib/config.sh (new optional key simplify.mode), possibly a new lib/simplify-adapter.sh. Does NOT touch any other adapter, so parallelizable with every other adapter task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 skills/autopilot/SKILL.md inner-loop documents the simplifier step between gates-pass and security-review
- [ ] #2 .autopilot-pipeline.json supports simplify.mode with values auto|manual|off
- [ ] #3 When simplify.mode is auto, the skill instructs Claude to call the code-simplifier subagent right after gates pass
- [ ] #4 When simplify.mode is off, the step is skipped with no warnings
- [ ] #5 tests/lib/wizard.bats covers the new simplify.mode default in the wizard
- [ ] #6 CONTRIBUTING.md documents how to swap the simplifier with a custom plugin
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
- [ ] #2 Manual verification: simplifier runs on a dummy branch with gates-passing code
<!-- DOD:END -->
