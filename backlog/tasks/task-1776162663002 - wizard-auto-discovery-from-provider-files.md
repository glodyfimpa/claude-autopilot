---
id: task-1776162663002
title: Wizard auto-discovery from provider files instead of manual registration
status: Done
assignee: []
created_date: '2026-04-14 16:31'
labels:
  - enhancement
  - architecture
priority: medium
dependencies: []
parent_task_id:
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Adding a new adapter currently requires editing 3 files manually: known-providers.sh (add constant), mcp-detector.sh (add list_available_providers_for_stage case + suggest function), wizard.sh (add stage to WIZARD_KNOWN_STAGES + _wizard_stage_config_key + _wizard_default_for_stage). This scales poorly and is error-prone.

Replace with auto-discovery: the wizard scans `lib/*-providers/` directories, infers the adapter name from the directory, reads available providers from the filenames, and builds the stage list dynamically. known-providers.sh becomes generated or removed. Each adapter declares its config key and default in a comment header or a small metadata function.

Discovered during Wave 2: 3 of 4 tasks required touching wizard.sh, making it the second most conflicted file after README.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Wizard discovers stages by scanning lib/*-providers/ directories
- [ ] #2 Provider list per stage is derived from filenames in the providers directory
- [ ] #3 Adding a new provider only requires creating the provider file (no edits to wizard.sh, known-providers.sh, or mcp-detector.sh)
- [ ] #4 Backwards compatible: existing .autopilot-pipeline.json configs still work
- [ ] #5 bats tests cover auto-discovery with mock provider directories
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 All bats tests green
<!-- DOD:END -->
