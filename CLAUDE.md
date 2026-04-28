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

## Direct-push exception (backlog-only)
- Default rule: every commit goes via PR (see above). Never `git push origin main` directly.
- Exception: a commit whose diff is **limited to `backlog/tasks/*.md`** may be committed and pushed straight to `main`. Covers status sync (To Do → In Progress → Done), new task file creation, and AC/body edits.
- Boundary: if `git diff --name-only` shows ANY path outside `backlog/tasks/` (commands, lib, skills, tests, docs, README, plugin.json, .gitignore, anything), fall back to the PR flow.
- Mixed diffs → split into two commits: one backlog-only direct-push, one feature PR.
- Always verify with `git diff --name-only` before pushing.

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
- Canonical flow: `scripts/release.sh <version>` (since v0.7.0). Does the full sequence in one command — preconditions check, bats run + green count capture, README test count sync, plugin.json bump, draft changelog from PR-merge commits since previous tag, optional `$EDITOR` pass on annotation, commit + annotated tag + push + `gh release create`. See README "Releasing" section for flag reference (`--dry-run`, `--no-edit`).
- Provider matrix in README is auto-generated: run `scripts/generate-readme-matrix.sh` and verify match (separate concern from the release script).
- Manual fallback (only if `scripts/release.sh` is unusable): bump `.claude-plugin/plugin.json`, sync `Current state: NNN tests` in README to match `bats tests/lib/ | grep -c "^ok "`, `git tag -a vX.Y.Z -m "changelog"`, push commit + tag, `gh release create`.
- README test count merge conflict pattern (still relevant when N feature PRs each bump the count): when N feature PRs each bump `Current state: N tests`, every PR after the first gets a conflict on that line. Resolution formula: `new_count = count_main_post_previous_merges + (count_branch_current − count_branch_baseline)`. Verify with `bats tests/lib/ | grep -c "^ok "` BEFORE the merge commit. Validated 3x during v0.5.0 sprint (PRs #15, #16, #17). The `compute_metric_overlap` signal in `lib/file-overlap-detector.sh` (since v0.7.0) flags this proactively at sprint planning time.
- Pre-flight: working tree must be clean (`git status --porcelain` empty). Common trap: untracked `.claude/` from Claude Code state files. Add `/.claude/` (root-anchored) to `.gitignore` if not already present — `release.sh` will refuse to run otherwise.
