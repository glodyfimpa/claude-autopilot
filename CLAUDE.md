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
New adapters follow: `lib/<name>-adapter.sh` + `lib/<name>-providers/*.sh`
+ entry in `lib/known-providers.sh` + stage in `lib/wizard.sh`
+ `tests/lib/<name>-adapter.bats`. See `lib/task-storage-adapter.sh` as reference.

## Backlog
Tasks in `backlog/tasks/`, format: `task-ID - Title-slug.md`
YAML frontmatter with status: "To Do" | "In Progress" | "Done"
Backlog must be on main for the backlog provider to work across branches.

## Worktrees
Subagent worktrees can leak files into the main directory.
After parallel runs: `git checkout -- . && git clean -fd <leaked-dirs> && git worktree prune`
