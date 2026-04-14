---
id: TASK-1.9
title: Real-world validation on Freelance Compass or RESEVO
status: To Do
assignee: []
created_date: '2026-04-10 13:00'
labels:
  - validation
  - e2e
  - sequential
  - v0.4.0
dependencies:
  - TASK-1.1
  - TASK-1.2
  - TASK-1.3
  - TASK-1.4
  - TASK-1.5
  - TASK-1.6
  - TASK-1.7
  - TASK-1.8
parent_task_id:
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v0.4.0 validation gate. Run the full autopilot pipeline end-to-end on Freelance Compass (Node/TS with real test, lint, types, build gates), from /autopilot-configure all the way to a merged PR. Collect friction notes for every phase and open follow-up tickets for each bug found.

Note: v0.3.0 was validated on claude-autopilot itself (bash/bats), which covered the pipeline flow but not a real multi-gate stack. Freelance Compass has Next.js + TypeScript + ESLint + Jest, which exercises all four quality gates.

This task is EXPLICITLY sequential: it must run after all v0.4.0 bug fixes are merged. Cannot be parallelized with anything else.

The deliverable is not code but a validation report documenting: which providers were chosen, how the wizard behaved, whether the inner loop passed on the first attempt, how many iterations it took per task, how the CI watchdog behaved on a real GitHub Actions workflow, and what bugs or friction were discovered.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pick one real project (Freelance Compass or RESEVO) and run /autopilot-configure inside it
- [ ] #2 Feed a real PRD through /autopilot-prd and verify the decomposed tasks are sensible
- [ ] #3 Run /autopilot-task on the first decomposed task and reach an open PR on GitHub
- [ ] #4 CI watchdog correctly blocks task-complete until GitHub Actions finishes green
- [ ] #5 Code quality adapter runs against SonarCloud (or equivalent) and catches at least one real issue
- [ ] #6 A validation report is committed under docs/validation/v0.3.0-report.md with metrics and friction notes
- [ ] #7 Every bug discovered is filed as a new backlog task
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Validation report merged to main
- [ ] #2 All discovered bugs have an associated task or fix
<!-- DOD:END -->
