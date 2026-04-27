---
id: TASK-1777750800003
title: 'file-overlap-detector: add metric-overlap signal for bundled PR recommendation'
status: Done
assignee: []
created_date: '2026-04-27 14:35'
labels:
  - enhancement
  - sprint-strategy
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The v0.6.0 sprint produced 3 separate PRs that each bumped `Current state: NNN tests` in README.md. The file-overlap detector saw 0 overlap (correct — they touch different lib files), but each PR after the first inherited a guaranteed merge conflict on that single line. Resolution required applying the formula documented in CLAUDE.md by hand (`new_count = count_main_post_previous_merges + (count_branch_current − count_branch_baseline)`).

This is not a file overlap — it's a **metric overlap**: a shared line that ALL test-adding PRs touch, regardless of which lib files they exercise. The detector should flag it.

Add a metric-overlap pass to `lib/file-overlap-detector.sh`:

1. New helper `compute_metric_overlap "$enriched_tasks_json"` returns a JSON object listing shared metric lines that 2+ tasks would touch:
   - README test count (`Current state: NNN tests`)
   - `.claude-plugin/plugin.json` `version` field
   - CHANGELOG.md (when present) top entry
2. Heuristic: a task "would touch" the test count if it adds bats files (description mentions `tests/lib/` or new `.bats`); the version line if it modifies `plugin.json`; the CHANGELOG if it's a release task.
3. `recommend_pr_strategy` consumes both file-overlap AND metric-overlap. If file overlap is empty but metric overlap covers all tasks, recommend `bundled` with reason `"shared metric line(s): {list}"`.
4. The `compute_overlap` JSON result gains a `metricOverlaps: [{line, tasks}]` field for transparency.

This catches the v0.6.0 case proactively: with the new signal, the planner would have suggested bundled PR for the 3 task-adding tasks, avoiding the 2 manual conflict resolutions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 lib/file-overlap-detector.sh exposes `compute_metric_overlap`
- [x] #2 The function detects shared README test-count line, plugin.json version, CHANGELOG.md top entry
- [x] #3 `compute_overlap` returns the union: `{byTask, overlaps, metricOverlaps, hasOverlap}` where hasOverlap is true if either kind of overlap exists
- [x] #4 `recommend_pr_strategy` returns `bundled` when metric overlap covers all tasks (even if file overlap is empty)
- [x] #5 The `autopilot-sprint` skill Step 5.1 displays metric overlaps to the user with the same matrix format
- [x] #6 bats tests cover: 3 task-adding tasks (metric overlap), 1 doc-only + 2 code tasks (no metric overlap), all 3 release tasks (3 metric overlaps), mixed
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 All bats tests green
- [x] #2 Manual replay: feed the v0.6.0 sprint task JSON and confirm `recommend_pr_strategy` returns `bundled` instead of `separate`
<!-- DOD:END -->
