---
id: task-1776162663001
title: Auto-generate README provider matrix from known-providers.sh
status: Done
assignee: []
created_date: '2026-04-14 16:31'
labels:
  - enhancement
  - dx
priority: medium
dependencies: []
parent_task_id:
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The README provider matrix table is a systematic merge conflict source. Every PR that adds or promotes a provider must edit the same lines in README.md, causing conflicts when multiple PRs land in sequence.

Replace the static table with a script (e.g. `scripts/generate-readme-matrix.sh`) that reads `lib/known-providers.sh` and the provider directories to determine which providers are implemented (have a real implementation, not a stub that exits 2) vs which are stubs. The script outputs the markdown table, and a pre-commit hook or CI check verifies the README stays in sync.

Discovered during Wave 2 parallel execution: PRs #8, #9, #10 all conflicted on the same README lines.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A script generates the provider matrix table from known-providers.sh + provider files
- [ ] #2 Stub detection: providers whose only function exits 2 are listed under "Stubs available"
- [ ] #3 README.md provider matrix matches the script output
- [ ] #4 bats test verifies the script output is valid markdown
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
<!-- DOD:END -->
