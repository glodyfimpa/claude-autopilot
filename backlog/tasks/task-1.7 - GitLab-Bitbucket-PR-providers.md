---
id: TASK-1.7
title: GitLab + Bitbucket PR providers
status: To Do
assignee: []
created_date: '2026-04-10 12:59'
labels:
  - provider
  - pr-target
  - parallelizable
dependencies: []
parent_task_id: TASK-1
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the two PR provider stubs with real implementations:
- lib/pr-providers/gitlab.sh uses glab mr create
- lib/pr-providers/bitbucket.sh uses bb pr create (or the REST API if bb is not available)

Shipped as one task because both providers need the same interface (pr_provider_<name>_create branch, title, body, base), the same error handling contract (exit 1 for config errors, propagate provider exit otherwise), and the same check_cli helper pattern as the existing github provider.

Files touched: only lib/pr-providers/gitlab.sh, lib/pr-providers/bitbucket.sh, tests/lib/pr-adapter.bats (add new cases). Does not touch adapter-base or any other file. Fully parallelizable with every other task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 pr_provider_gitlab_create runs glab mr create with the passed branch/title/body/base and prints the MR URL
- [ ] #2 pr_provider_bitbucket_create uses bb pr create OR the REST API (clearly documented in the file header)
- [ ] #3 Both providers expose a <provider>_check function that returns 1 with a helpful message when the CLI is missing
- [ ] #4 tests/lib/pr-adapter.bats has new cases that stub the CLIs and verify the dispatch works
- [ ] #5 README provider matrix moves gitlab and bitbucket from stub to implemented
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
<!-- DOD:END -->
