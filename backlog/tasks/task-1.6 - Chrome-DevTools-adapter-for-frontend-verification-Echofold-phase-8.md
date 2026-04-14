---
id: TASK-1.6
title: Chrome DevTools adapter for frontend verification (Echofold phase 8)
status: Done
assignee: []
created_date: '2026-04-10 12:59'
labels:
  - adapter
  - frontend
  - echofold-phase-8
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Echofold phase 8 runs Chrome DevTools MCP against the implementation to catch frontend regressions: console errors, failed network requests, accessibility violations. This is only relevant for projects that have a web UI.

Add a new optional adapter lib/frontend-verify-adapter.sh with providers:
- chrome-devtools (via Chrome MCP)
- playwright (via Playwright MCP)
- none (opt-out, default for non-web projects)

The adapter runs in the inner loop AFTER code quality (phase 7) and BEFORE task-complete marker, but only when frontend_verify.provider is not none. The wizard proposes chrome-devtools only when it detects a package.json with a web framework (react, vue, next, etc.) and the Chrome MCP is enabled.

Files touched: lib/frontend-verify-adapter.sh (new), lib/frontend-verify-providers/*.sh (new), lib/known-providers.sh (add new constant), skills/autopilot/SKILL.md (step in inner loop), tests/lib/frontend-verify-adapter.bats (new). Fully parallelizable with every other adapter task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 lib/frontend-verify-adapter.sh dispatches verify via adapter-base.sh
- [ ] #2 chrome-devtools provider runs the MCP tools and returns a normalized pass/fail report
- [ ] #3 playwright and none providers exist as stubs
- [ ] #4 The wizard proposes chrome-devtools only when package.json contains a web framework dependency and Chrome MCP is enabled
- [ ] #5 Inner loop step skips cleanly when frontend_verify.provider is none
- [ ] #6 tests/lib/frontend-verify-adapter.bats covers validate, dispatch, stub exit 2, and opt-out behavior
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
<!-- DOD:END -->
