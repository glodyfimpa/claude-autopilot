---
name: autopilot-sprint
description: Run every ready task in the configured storage through the full pipeline, with adaptive parallelization
---

Run every ready task in the configured storage. Argument received: $ARGUMENTS

## Purpose

Execute the full batch of ready tasks end-to-end. The parallelization strategy configured in `.autopilot-pipeline.json` decides whether tasks run sequentially, in parallel (via worktrees), or some mix. One PR per completed task, always branched from `main`.

## Arguments

- `(no argument)` run every task with status `ready`
- `<filter>` optional filter expression the task storage provider understands (e.g. a label name)

## Preconditions

- `.autopilot-pipeline.json` must be fully configured.
- `task_storage.provider` must support `list` (local-file does; chat-paste does not).
- The working directory must be a clean git repository.

## Actions

### Step 1: Load libraries

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/task-storage-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/complexity-estimator.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/parallelization-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branch-utils.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/pr-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/file-overlap-detector.sh"
```

### Step 2: List ready tasks

Run `task_storage_list` and filter to tasks with status `ready`. If zero tasks are returned, stop and tell the user the queue is empty.

### Step 3: Estimate complexity for every task

For each task, call `estimate_complexity` and attach the result as a `complexity` field on the task JSON. Keep the enriched array.

### Step 4: Plan execution

Call `plan_execution "$enriched_tasks_json"` and capture the plan:

```json
{
  "strategy": "parallel" | "sequential",
  "maxConcurrency": 3,
  "groups": [["t1"], ["t2", "t3"], ["t4"]]
}
```

### Step 5: Present the plan

Show the user:

- Total tasks, broken down by complexity tier
- Strategy and max concurrency
- The group layout (which tasks share a lane)
- An estimated token budget warning when the number of parallel lanes is high

#### Step 5.1: Detect file overlap and offer a PR strategy

Before asking for confirmation, run the overlap detector on the enriched task array:

```bash
overlap="$(compute_overlap "$enriched_tasks_json")"
recommendation="$(recommend_pr_strategy "$enriched_tasks_json")"
```

`compute_overlap` returns a JSON object with three fields:

- `byTask` — map from task id to the list of files mentioned in its description/acceptance criteria
- `overlaps` — list of `{file, tasks}` records, one per file that appears in 2+ tasks
- `hasOverlap` — boolean shortcut

Behavior:

- **`hasOverlap == false`** → no warning, default to **(a) separate PRs**, jump to confirmation.
- **`hasOverlap == true`** → show the user the overlap matrix and ask which PR strategy to use:
  - **(a) Separate PRs** — current behavior, one PR per task. Reviewer handles conflicts.
  - **(b) Bundled PR** (recommended when one overlap cluster covers all/most tasks) — all tasks run in their own worktree branches, then their commits are cherry-picked sequentially into a single integration branch (`integration/sprint-<timestamp>`); conflicts are resolved during integration; one PR is opened listing all tasks.
  - **(c) Grouped PRs** (recommended when there are multiple disjoint overlap clusters) — `group_by_overlap` partitions tasks into clusters; one PR per cluster, following the bundled flow within each.

Use `recommend_pr_strategy` as the default suggestion; the user can override.

Ask for confirmation before spawning any work.

### Step 6a: Sequential execution

When the plan strategy is `sequential`, iterate the groups in order and run each task through `/autopilot-task <ref>` one after another. Stop the batch if any task fails gates after max iterations.

### Step 6b: Parallel execution

When the plan strategy is `parallel` and the chosen PR strategy is **(a) Separate PRs**, spawn one subagent per group (up to `maxConcurrency` in flight at any time) using the Task tool with `isolation: "worktree"`. Each subagent runs the same logic as `/autopilot-task` but inside its isolated worktree.

Wait for all subagents to finish. Collect their PR URLs and any failures. Clean up all worktrees on completion.

### Step 6c: Bundled or grouped PR execution

When the chosen PR strategy is **(b) Bundled PR** or **(c) Grouped PRs**, the per-task subagents must NOT open their own PRs. Instead:

1. Run each subagent in its worktree as in Step 6b, but pass `bundled_mode=true` so the subagent stops at the local commit (no `git push -u`, no `gh pr create`).
2. After all subagents finish:
   - **Bundled (b)**: Create a single integration branch from `main` named `integration/sprint-<timestamp>`. Cherry-pick each successful task's commit sequentially. Resolve any conflicts that arise — the conflicts will surface in the same files the overlap detector flagged, so the resolution is deterministic. Run the FULL test suite (`bats tests/lib/`) on the integration branch. If green, push and open ONE PR listing every bundled task with its acceptance criteria.
   - **Grouped (c)**: Run `group_by_overlap` to get the clusters. For each cluster, repeat the bundled flow above with branch `integration/sprint-<timestamp>-group<N>`.
3. Clean up worktrees only after the integration step succeeds. If a cherry-pick fails irrecoverably, leave the source worktrees in place so the user can inspect.

The bundled flow replicates the manual sequence used during the v0.4.0 sprint (PR #12), where 6 tasks touching `wizard.sh`, `mcp-detector.sh`, and `autopilot-task.md` were cherry-picked into one branch with conflicts resolved once.

### Step 7: Summary

Print a table:

- Task ref
- Final status (done / failed)
- PR URL (if done)
- Failure reason (if failed)

Remind the user that failed tasks are back in `ready` state and can be retried individually with `/autopilot-task <ref>`.

## Error handling

- If the task storage provider doesn't support `list`, fail fast with a helpful message telling the user to add tasks via `/autopilot-prd` first, or switch to a storage that supports listing.
- If a parallel subagent crashes, its worktree must still be cleaned up. Use a cleanup phase that runs regardless of outcome.
- If the token budget estimate exceeds the configured cap, require explicit user confirmation before proceeding.
