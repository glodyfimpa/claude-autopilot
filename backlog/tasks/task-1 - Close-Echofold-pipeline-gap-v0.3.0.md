---
id: TASK-1
title: Close Echofold pipeline gap (v0.3.0)
status: To Do
assignee: []
created_date: '2026-04-10 12:56'
labels:
  - epic
  - v0.3.0
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Epic tracking all the work needed to bring claude-autopilot from v0.2.0 (foundation shipped) to v0.3.0 (full parity with the Echofold autonomous development pipeline described at https://echofold.ai/news/how-to-automate-claude-code-autonomous-development). The v0.2.0 release covered phases 1, 3, 5 and 10 of the Echofold flow; v0.3.0 closes the gap on phases 4, 6, 7, 8 and on real-world provider coverage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SonarQube-style code quality adapter implemented with at least one working provider
- [ ] #2 CI watchdog blocks the task-complete marker until GitHub Actions finishes green
- [ ] #3 SessionStart hook injects sprint-context.md for parallel subagent runs
- [ ] #4 code-simplifier skill is invoked automatically in the inner loop
- [ ] #5 At least one real Notion provider (task-storage or prd-source) replaces the stub
- [ ] #6 The full v0.3.0 pipeline has been validated end-to-end on a real project
- [ ] #7 Composite plugin score vs Echofold reaches >=8.5/10
<!-- AC:END -->
