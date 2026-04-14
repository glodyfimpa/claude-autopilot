---
id: TASK-1776159717849
title: autopilot-task should manage active task state file
status: To Do
priority: medium
---

## Description
autopilot-task creates ~/.claude/.autopilot-active-task.json manually but neither writes it at step 5 (mark in-progress) nor removes it at step 9 (mark done). The SessionStart hook depends on this file to inject sprint context. Without it, the hook always falls back to minimal context.

## Acceptance Criteria
- [ ] #1 commands/autopilot-task.md step 5 writes active_task JSON with the task ref
- [ ] #2 commands/autopilot-task.md step 9 removes the active_task JSON after PR is opened
- [ ] #3 tests verify the file lifecycle
