---
name: autopilot-task
description: Execute a single task end-to-end (branch from main, implement, verify, PR)
---

Execute a single engineering task end-to-end. Argument received: $ARGUMENTS

## Purpose

Take one task from the configured task storage, create a branch from main using Echofold naming, run the implementation + verification loop, and open a PR on the configured PR target when the task is complete.

## Arguments

- `<ref>` identifier the task storage provider understands
  - `local-file`: path to a markdown task file (e.g. `tasks/t1234567.md`)
  - `notion`: page id
  - `jira`: issue key
  - `linear`: issue id
  - `chat-paste`: the raw task text

## Preconditions

- `.autopilot-pipeline.json` must have `task_storage.provider`, `pr_target.provider`, and `branch_convention.*` set.
- The working directory must be a git repository with a `main` (or `master`) branch.
- Autopilot quality gates must be active (`/autopilot on`) unless the user has explicitly opted out.

## Actions

### Step 1: Load libraries

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branch-utils.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/task-storage-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/pr-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/ci-watcher.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/complexity-estimator.sh"
```

### Step 2: Fetch the task

Run `task_storage_fetch "$ARGUMENTS"` and parse the JSON. Fail fast with a clear message if the provider returns exit 2 (stub) or 1 (missing ref).

### Step 3: Estimate complexity

Run `estimate_complexity "$task_json"`. If the tier is `epic`, stop and ask the user whether to split the task before continuing. If the tier is `complex`, warn the user that this task will run with full context and no parallelization.

### Step 4: Create the working branch from main

Read the branch convention from config:

```bash
project_prefix="$(config_get 'branch_convention.project_prefix' 2>/dev/null || infer_project_prefix \"$(pwd)\")"
```

Infer the branch kind (`feat` or `fix`) from the task title or acceptance criteria. Build the branch name:

```bash
branch="$(build_branch_name "$kind" "$project_prefix" "$ticket_id" "$title")"
create_branch_from_main "$branch"
```

### Step 5: Mark the task as in-progress

Call `task_storage_update_status "$ARGUMENTS" "in_progress"`. Ignore exit code 2 (provider doesn't support status updates).

Also write the active task state file so the SessionStart hook can inject context:

```bash
echo "{\"active_task\": \"$ARGUMENTS\"}" > "$HOME/.claude/.autopilot-active-task.json"
```

### Step 6: Implement + verify loop

Invoke the autopilot skill (from `skills/autopilot/SKILL.md`) with the task description and acceptance criteria as the initial context. The skill is responsible for:

- Running the implementation steps
- Running the quality gates (tests, lint, types, build)
- Iterating on failures up to the configured max (default 5)
- Writing a task-complete marker when all gates pass AND every acceptance criterion is satisfied

Do NOT open a PR mid-loop. The PR comes only after the task-complete marker is set.

### Step 7: Commit and push

When the task-complete marker is set:

1. Run `git status` to confirm there are changes to commit.
2. Stage modified files with `git add`.
3. Create a commit following the project convention (Conventional Commits if used). Example:
   ```
   feat(auth): add session token rotation

   Implements rotation per acceptance criteria #1-3 on <ticket>.
   ```
4. Push the branch with `git push -u origin <branch>`.

### Step 8: Open the PR

Build the PR body with:

- A one-sentence summary
- Acceptance criteria as a checklist (all checked)
- A link back to the task ref when the storage supports it

Call `pr_adapter_create "$branch" "$title" "$body" "$base"` and capture the returned PR URL.

### Step 8.5: Wait for CI

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/ci-watcher.sh"
```

Call `wait_for_ci "$head_ref"` where `$head_ref` is the commit SHA that was pushed. The function reads `pr_target.config.ci_timeout_minutes` from the config (default 15 minutes).

- **Exit 0**: CI passed. Proceed to marking the task done.
- **Exit 2**: Provider is a stub (gitlab/bitbucket). Proceed without blocking.
- **Exit 1**: CI failed. Roll the task status back to `in_progress` by calling `task_storage_update_status "$ARGUMENTS" "in_progress"`. Surface the failure log to the user and stop. Do NOT mark the task as done.

### Step 9: Mark the task as done

Call `task_storage_update_status "$ARGUMENTS" "done"`. Print the PR URL to the user.

Clean up the active task state file:

```bash
rm -f "$HOME/.claude/.autopilot-active-task.json"
```

## Error handling

- If any gate fails after max iterations, stop BEFORE committing/pushing and surface the failure to the user. Leave the branch local so they can inspect.
- If `gh` (GitHub CLI) is missing and the provider is `github`, tell the user to install it.
- If the provider is a stub, the command should have failed at Step 2 already.
- On any error that stops execution (gate failures after max iterations, missing tools), also clean up the active task state file: `rm -f "$HOME/.claude/.autopilot-active-task.json"`
