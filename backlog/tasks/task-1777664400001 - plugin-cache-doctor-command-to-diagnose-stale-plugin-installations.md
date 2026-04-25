---
id: TASK-1777664400001
title: plugin-cache-doctor command to diagnose stale plugin installations
status: Done
assignee: []
created_date: '2026-04-25'
updated_date: '2026-04-25 15:30'
labels:
  - enhancement
  - tooling
dependencies: []
priority: medium
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
- [x] #1 Command lists all plugins in manifest and reports each as healthy/stale/orphan
- [x] #2 For stale entries, shows the missing path and suggests `claude plugin install <name>` after manifest cleanup
- [x] #3 For orphan caches, shows the path and suggests `rm -rf` after confirmation
- [x] #4 Dry-run mode (`--check`) reports findings without executing
- [x] #5 Idempotent: running twice on a healthy state is a no-op
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped via PR #14 (https://github.com/glodyfimpa/claude-autopilot/pull/14). New `/plugin-cache-doctor` command diagnoses desync between `~/.claude/plugins/installed_plugins.json` (manifest) and the on-disk `cache/<plugin>/<version>/` folders. Library `lib/plugin-cache-doctor.sh` exposes `diagnose_plugins`, `diagnose_plugins_json`, `doctor_check`, `suggest_fixes`. Dry-run by default; --fix mode gated by user confirmation. 14 bats tests cover stale/orphan/healthy/empty-manifest/missing-manifest with mocked PLUGINS_ROOT in tmpdir. Smoke test on real ~/.claude/plugins identified dozens of stale entries pointing at the old commit-hash folders (b36fd4b75301) after claude-plugins-official upstream switched to semver — exactly the v0.4.0 release-session scenario that motivated the task. Schema gotcha caught and fixed: real manifest is `.plugins[name] = [array of install records]` with `installPath`, not the simpler single-object schema assumed initially.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 bats test covers stale/orphan/healthy scenarios with mocked filesystem
- [x] #2 Manual smoke test on a real stale plugin confirms the fix works end-to-end
<!-- DOD:END -->
