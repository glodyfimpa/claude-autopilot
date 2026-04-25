---
name: recover-blocked-push
description: Recover from a blocked direct push to main by moving the commit to a release branch
---

Recover from a blocked direct push to the default branch. Argument received: $ARGUMENTS

When repo policy enforces "PRs only" (no direct push to `main`), a `git push` after committing locally on main fails with a remote-side rejection. This command automates the recovery: move the local commit to a fresh branch, reset main back to `origin/main`, then push the branch and open a PR.

## Arguments

- `(no argument)` Run detection + propose a plan (no execution).
- `--detect` Same as no-arg: print JSON diagnosis only.
- `--apply` Execute the recovery (after explicit confirmation).

## Actions

### Step 1: Load the library

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/push-recovery.sh"
```

### Step 2: Diagnose

```bash
detect_blocked_push
```

Inspect the JSON. The recovery is safe when:

- `blocked == true` — on default branch with 1+ commit(s) ahead of `origin/main`
- `dirty == false` — working tree is clean
- `multi_commit == false` — exactly 1 commit ahead

If any of these is not true, surface the reason and stop. Examples:
- `dirty: true` → ask the user to commit or stash first
- `multi_commit: true` → recovery requires manual reasoning, do not automate
- `branch != main` → not the scenario this command handles

### Step 3: Execute (--apply only)

If the argument is `--apply` and the diagnosis is safe:

1. Show the user the proposed `branch_suggestion` from the JSON.
2. Ask for explicit confirmation.
3. Run `recover_blocked_push`. This:
   - Creates the recovery branch at the current HEAD
   - Resets the default branch to `origin/<default_branch>`
   - Leaves the working tree on the new branch
   - Preserves any tag pointing at the moved commit (tags follow SHAs)
4. After success, run:
   ```bash
   git push -u origin <new-branch>
   gh pr create --base main --title "<commit subject>" --body "..."
   ```
   Use the original commit body as the PR body when possible.

### Step 4: Tag handling

Tags pointing at the moved commit (e.g. `v0.4.0` after a release commit) survive the operation because git tags reference SHAs, not branches. After the PR merges, no further tag manipulation is needed unless the maintainer squashed the merge — in which case the tag should be re-applied to the new merge commit on main.

## Failure modes

- `not a git repository` — run from inside a repo
- `dirty` — uncommitted changes block the recovery
- `multiple commits` — the command refuses to recover when 2+ commits are ahead, since the user should pick which to ship and which to drop
- `not on default branch` — already on a feature branch, no recovery needed

## Notes

- Default branch is `main` unless `DEFAULT_BRANCH` is set in the environment (e.g. for repos still on `master`).
- The library never runs `git push --force` or any destructive operation against the remote. Only local refs are mutated.
