---
id: TASK-177615736660
title: Stop-gate should warn when no quality gates are configured
status: Done
priority: medium
---

## Description
When detect-stack.sh returns stack unknown with all empty gate commands, the stop-gate hook passes silently with no checks. This gives a false sense of safety. The hook should emit a systemMessage warning that no gates are active so the user knows quality is not being verified.

## Acceptance Criteria
- [ ] #1 stop-gate.sh emits a warning systemMessage when all gate commands are empty
- [ ] #2 The warning suggests running detect-stack.sh or configuring gates manually
- [ ] #3 tests/lib/stop-gate.bats covers the zero-gates scenario
