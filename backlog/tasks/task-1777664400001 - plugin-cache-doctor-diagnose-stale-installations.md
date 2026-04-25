---
id: TASK-1777664400001
title: plugin-cache-doctor command to diagnose stale plugin installations
status: To Do
assignee: []
created_date: '2026-04-25'
labels:
  - enhancement
  - tooling
priority: medium
dependencies: []
parent_task_id:
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a Claude Code plugin "disappears" from the UI (slash commands stop working, `/plugin list` shows it missing), the root cause is almost always a desync between two sources of truth: `~/.claude/plugins/installed_plugins.json` (manifest) and `~/.claude/plugins/cache/<plugin>/<version>/` (filesystem). The manifest can point to a commit hash whose cache folder no longer exists, typically after a `git pull` on the plugin's source repo changes the SHA.

This is a recurring issue — already documented in `~/.claude/CLAUDE.md` as a gotcha — and was hit twice in recent sessions (v0.4.0 release session 2026-04-25).

Build a `plugin-cache-doctor` command that:
1. Reads `~/.claude/plugins/installed_plugins.json` and `~/.claude/plugins/cache/`
2. Identifies stale entries: manifest paths that don't exist on disk
3. Identifies orphan caches: cache folders with no corresponding manifest entry
4. Proposes fixes for each finding (remove stale entry + reinstall, or remove orphan)
5. Executes fixes after user confirmation

Discovered during v0.4.0 release session: claude-autopilot was missing because cache pointed to commit `9d88fcab` (folder `0.1.0/`) which no longer existed after recent commits. Manual fix: `rm -rf cache/claude-autopilot/` + Python edit of `installed_plugins.json` + `claude plugin install`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Command lists all plugins in manifest and reports each as healthy/stale/orphan
- [ ] #2 For stale entries, shows the missing path and suggests `claude plugin install <name>` after manifest cleanup
- [ ] #3 For orphan caches, shows the path and suggests `rm -rf` after confirmation
- [ ] #4 Dry-run mode (`--check`) reports findings without executing
- [ ] #5 Idempotent: running twice on a healthy state is a no-op
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bats test covers stale/orphan/healthy scenarios with mocked filesystem
- [ ] #2 Manual smoke test on a real stale plugin confirms the fix works end-to-end
<!-- DOD:END -->
