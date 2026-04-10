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

Ask for confirmation before spawning any work.

### Step 6a: Sequential execution

When the plan strategy is `sequential`, iterate the groups in order and run each task through `/autopilot-task <ref>` one after another. Stop the batch if any task fails gates after max iterations.

### Step 6b: Parallel execution

When the plan strategy is `parallel`, spawn one subagent per group (up to `maxConcurrency` in flight at any time) using the Task tool with `isolation: "worktree"`. Each subagent runs the same logic as `/autopilot-task` but inside its isolated worktree.

Wait for all subagents to finish. Collect their PR URLs and any failures. Clean up all worktrees on completion.

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
