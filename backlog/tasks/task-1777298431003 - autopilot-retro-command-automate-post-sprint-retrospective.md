---
id: TASK-1777298431003
title: 'autopilot-retro: command to automate post-sprint retrospective'
status: To Do
assignee: []
created_date: '2026-04-27 16:30'
labels:
  - enhancement
  - command
  - workflow
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the v0.7.0 release sprint (2026-04-27) the user asked for an explicit retrospective. The flow was manual and took 5+ messages: identify gaps from the session (smoke-test gap, doc holes, process violations like direct push to main), categorize them as memories vs backlog tasks, write the .md files, open a PR (#24).

The pattern is repeatable. Every sprint that touches non-trivial workflow surfaces 2-3 follow-up items. Doing it manually each time wastes user attention.

Add a `/autopilot-retro` slash command that automates the post-sprint retrospective. The command should:

1. Read the last git tag (`git describe --tags --abbrev=0`) and the PRs merged AFTER it (gh pr list --state merged --base main --search "merged:>$tag_date").
2. Read the current Claude Code session transcript (best-effort — may need to inspect `~/.claude/projects/<...>/sessions/`) to identify retrospective signals: errors recovered, manual workarounds, "had to do X by hand" patterns.
3. Propose a list of N items, each classified as:
   - **Memory** (personal feedback rule for future sessions)
   - **Backlog task** (work item for the next sprint)
   - **Discard** (one-off, not worth capturing)
4. After user confirms the classification, generate the .md files in the right place (`~/.claude/projects/<...>/memory/` or `backlog/tasks/`).
5. If any backlog tasks were created, open a PR `chore/retro-vX.Y.Z` from `main` with the new task files (NEVER push directly).

Important constraint: don't build this until at least 2 more manual retrospectives have happened — the design space is still open after only 1 data point. The v0.7.0 retro itself was the first; track subsequent ones as input.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New `commands/autopilot-retro.md` slash command exists
- [ ] #2 Command reads last tag + post-tag merged PRs as starting input
- [ ] #3 Command proposes items with classification (memory / task / discard) for user review
- [ ] #4 Generated memory files follow the existing `feedback_*.md` schema
- [ ] #5 Generated backlog task files follow the existing `task-<timestamp> - <slug>.md` schema
- [ ] #6 Command opens a PR `chore/retro-<tag>` for new task files; NEVER pushes to main directly
- [ ] #7 At least 2 manual retros recorded as design input before implementation starts
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 At least 2 manual retro sessions have happened to inform the design (avoid premature abstraction)
- [ ] #2 Command file exists with complete prompt + step list
- [ ] #3 Manual smoke: run /autopilot-retro after a real sprint and verify the proposed items match what a human would have flagged
<!-- DOD:END -->
