---
id: TASK-1776157264100
title: Wizard should warn when selected provider is a stub
status: To Do
priority: medium
---

## Description
The wizard lets users select providers that are stubs (exit 2) without any warning. Users only discover the provider is not implemented when they run task_storage_fetch and it fails. The wizard should check if the provider file contains the stub marker and show a warning before accepting the choice.

## Acceptance Criteria
- [ ] #1 wizard_propose marks stub providers with a warning label in the options list
- [ ] #2 wizard_apply emits a clear warning when a stub provider is selected
- [ ] #3 tests/lib/wizard.bats covers the stub-warning behavior
