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

### Step 2: Fetch the task (pre-flight check)

Run `task_storage_fetch "$ARGUMENTS"` and capture the exit code. This MUST succeed before any branch is created.

- **Exit 0**: Parse the JSON and proceed to Step 3.
- **Exit 1**: The task ref was not found. Print: `Pre-flight failed: task ref '<ref>' not found in task storage. Verify the ref exists and the task_storage.provider is correctly configured (current: <provider>).` STOP here — do NOT create any branch or proceed further.
- **Exit 2**: The provider is a stub (not implemented). Print: `Pre-flight failed: task storage provider '<provider>' is a stub and cannot fetch tasks. Configure an implemented provider with /autopilot-configure task-storage.` STOP here.

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

#### Step 6.5: Per-step review (complex / epic only)

When the task complexity tier is `complex` or `epic`, after EACH commit produced inside the inner loop (one per logical unit, per the TDD discipline section of the autopilot skill), run BOTH reviewers in parallel before the implementer proceeds to the next unit:

- **Spec-compliance reviewer** (prompt: `skills/autopilot/spec-compliance-reviewer-prompt.md`) — validates the commit against the task's acceptance criteria, flags drift and out-of-scope changes.
- **Code-quality reviewer** (prompt: `skills/autopilot/code-quality-reviewer-prompt.md`) — validates the commit for portability (bash 3.2 / BSD), hidden coupling, error-handling, and test design.

The implementer proceeds to the next unit ONLY when both reviewers return APPROVE on the same commit. If either rejects:

1. The implementer reads BOTH reports, fixes the issues (in a follow-up commit OR an amend depending on the issue's locality), and requests a re-review.
2. Re-review loop is bounded: if 3 iterations on the same commit still don't reach APPROVE on both, STOP and report the deadlock. The deadlock signal usually means the AC is malformed or the design needs a brainstorming checkpoint (see Step 3.5 once it lands via TASK-1777468663004).

Each reviewer subagent receives:
- The diff of the latest commit (`git show <sha>` output).
- The task's acceptance criteria verbatim from the task storage.
- The project conventions (bash 3.2, BSD sed, bats-core).

The PR description must document the per-step review trace: which reviewer flagged which issue, how many iterations were needed before APPROVE. Use a `## Review trace` section with one row per commit.

For `standard` and `simple` tier tasks, this step is **silently skipped** — the inner loop runs through to Step 7 with the existing single-pass review at the end (code-simplifier + security-reviewer per the skill's Step 9). Per-step review on trivial changes adds latency without value.

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

### Step 8.6: Execute the test plan before declaring the task done

The PR body Claude wrote in Step 8 includes a `## Test plan` section with a checklist. Before marking the task done, every item on that list must be verified — either executed (for shell commands, scripts, bats invocations) or flagged for manual review (for subjective checks like "verify the dropdown looks correct").

The motivation: PRs were repeatedly handed off with unchecked test plan items that, when run later, all passed — they just weren't run before declaring "done". This step closes that gap.

#### How to do it

1. Read the PR body via `gh pr view <pr-number> --json body --jq .body`.
2. Locate the `## Test plan` section. Each line of the form `- [ ] <text>` is an unchecked item.
3. For each unchecked item, classify it:
   - **Executable**: line contains a fenced code block, an inline backtick command, a path to a bats file (`tests/lib/*.bats`), or a recognisable invocation (`npm test`, `pytest`, `bats`, `bash <script>`, `gh ...`).
   - **Manual**: anything else (e.g. "verify the dropdown looks correct", "smoke test in the UI"). Cannot be automated.
4. Run each executable item:
   - Capture stdout, stderr, and exit code.
   - On exit 0, mark the item as passed.
   - On any non-zero exit, mark it as failed and STOP — do not proceed to Step 9.
5. After all executable items have run, build a new PR body where:
   - Every passing executable item becomes `- [x] <text>`.
   - Every failing executable item stays `- [ ] <text>` with an inline `_(failed: <one-line reason>)_` annotation.
   - Every manual item stays `- [ ] <text>` with an inline `_(manual review)_` annotation.
6. Update the PR with `gh pr edit <pr-number> --body-file <new-body-file>`.
7. If any executable item failed: surface the failure to the user, roll the task status back to `in_progress` via `task_storage_update_status "$ARGUMENTS" "in_progress"`, and STOP. Do NOT proceed to Step 9.
8. If at least one item is `_(manual review)_`, tell the user the task is `done pending manual review` and pause for confirmation before Step 9. Manual items can be acknowledged with a single user reply.

#### What counts as "passing"

The test plan is a contract with the reviewer. An item passes only if:
- It was actually executed in this run (no "trust me, it worked last time").
- The exit code was 0.
- The output is captured and stored in the PR body update so the reviewer can see what ran.

Skipping this step in Auto mode is not allowed — the rule applies whether the user is interactive or not.

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
