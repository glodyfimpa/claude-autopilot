# CLAUDE.md

## Project
Claude Autopilot — Claude Code plugin for autonomous PRD→PR pipeline.
Bash scripts, bats tests, no Node/Python runtime.

## Testing
- Framework: bats-core. Run all: `bats tests/lib/`
- Helpers: `tests/helpers/test_helper.bash` (tmpdir, fake git repo, assertions)
- Always run full suite after rebase/merge conflict resolution before pushing
- TDD: test first → RED → implement → GREEN → refactor

## Portability (CRITICAL)
- Target: macOS bash 3.2 + BSD coreutils
- NO bash 4+ syntax: `${var^^}` → `echo "$var" | tr '[:lower:]' '[:upper:]'`
- NO `declare -A`, `mapfile`, `readarray`
- `sed -i.bak -e '...' file && rm -f file.bak` (BSD sed requires suffix)
- NO `git branch --show-current` → `git rev-parse --abbrev-ref HEAD`
- NO `git worktree remove` (git 2.15) → `rm -rf <path> && git worktree prune`

## Adapter Pattern
New providers: create `lib/<name>-providers/<provider>.sh` + test in `tests/lib/<name>-adapter.bats`.
Auto-discovery scans `lib/*-providers/` directories — no edits to known-providers.sh or wizard.sh needed.
`lib/known-providers.sh` remains as fallback for stages without provider dirs (parallelization, simplify).
See `lib/task-storage-adapter.sh` as reference adapter.

## Backlog
Tasks in `backlog/tasks/`, format: `task-ID - Title-slug.md`
YAML frontmatter with status: "To Do" | "In Progress" | "Done"
Backlog must be on main for the backlog provider to work across branches.

## PRs
- NEVER merge PRs. Only create them. The user reviews and merges manually.
- Execute ALL test plan items (including manual smoke tests) before declaring PR ready.
- Every checklist item in the PR body must be checked before handoff — no unchecked items.

## Worktrees
Subagent worktrees can leak files into the main directory.
After parallel runs: `git checkout -- . && git clean -fd <leaked-dirs> && git worktree prune`
- Always `cd` to worktree path before any git operation (checkout, add, commit)
- `git branch -D` fails if branch is checked out in a worktree — remove worktree first
- Subagents cannot run `gh pr create` — always create PRs from the main session
- When parallel tasks touch shared files, bundle into 1 PR via cherry-pick integration:
  create integration branch from main → cherry-pick each worktree commit sequentially →
  resolve conflicts → run full test suite → open single PR

## Release
- Update test count in README.md on each release (search "Current state:")
- Provider matrix in README is auto-generated: run `scripts/generate-readme-matrix.sh` and verify match
- Bump version in `.claude-plugin/plugin.json`
- Tag format: `git tag -a vX.Y.Z -m "changelog"`
