---
id: TASK-1.1
title: Code quality adapter + SonarQube provider (Echofold phase 7)
status: Done
assignee: []
created_date: '2026-04-10 12:56'
updated_date: '2026-04-10 12:58'
labels:
  - adapter
  - code-quality
  - echofold-phase-7
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a new adapter layer that runs semantic code quality analysis after the test/lint/types/build gates pass and before the security reviewer. Mirrors the SonarQube step in the Echofold pipeline: detects code smells, cognitive complexity, duplication and security hotspots that lint and type checks cannot see. Integrates a retry loop with a hard max of 5 iterations per Echofold.

The adapter follows the same pattern as pr-adapter/task-storage-adapter/prd-source-adapter: a known-providers list in lib/known-providers.sh, a dispatch function using adapter-base.sh, and one provider file per tool under lib/code-quality-providers/.

Slot in the inner loop: runs between Stop hook gates (step 2) and security reviewer (step 5) of the execution flow documented in skills/autopilot/SKILL.md. Must respect the task-complete marker contract (marker is only written after code quality passes).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 lib/code-quality-adapter.sh dispatches fetch/scan via adapter-base.sh
- [ ] #2 lib/code-quality-providers/sonarqube.sh calls the SonarQube MCP (or REST API) and returns a normalized result JSON
- [ ] #3 Stub providers exist for semgrep, codeclimate, and 'none' (opt-out)
- [ ] #4 Retry loop respects max 5 iterations; exceeds raises a clear error and blocks the task-complete marker
- [ ] #5 lib/known-providers.sh has a new CODE_QUALITY_KNOWN_PROVIDERS constant
- [ ] #6 wizard.sh proposes sonarqube by default when the SonarQube MCP is detected
- [ ] #7 tests/lib/code-quality-adapter.bats covers validate, dispatch, retry loop, and stub exit 2
- [ ] #8 skills/autopilot/SKILL.md inner-loop documentation names the new step between gates and security
- [ ] #9 README.md provider matrix lists the new stage
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
- [ ] #2 README structure table updated
<!-- DOD:END -->
