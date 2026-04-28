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

### Strategy x execution-mode matrix

The PR strategy chosen in Step 5.1 and the execution mode chosen by the planner (Step 4, possibly forced to `sequential` by Step 1.5) combine into six cases. Use this table to find the step that handles each one — behavior is deterministic regardless of which sub-Claude executes the sprint.

| PR strategy | Execution mode | Handler |
|---|---|---|
| separate    | parallel   | [Step 6b](#step-6b-parallel-execution) — one subagent + one PR per task |
| separate    | sequential | [Step 6a](#step-6a-sequential-execution) — one task at a time + one PR per task |
| bundled     | parallel   | [Step 6c](#step-6c-bundled-or-grouped-pr-execution) — worktrees + cherry-pick into one integration branch |
| bundled     | sequential | [Step 6d](#step-6d-bundled-or-grouped-pr-execution-sequential-mode) — sequential commits on one integration branch + one PR |
| grouped     | parallel   | [Step 6c](#step-6c-bundled-or-grouped-pr-execution) — worktrees + cherry-pick per cluster |
| grouped     | sequential | [Step 6d](#step-6d-bundled-or-grouped-pr-execution-sequential-mode) — sequential commits on per-cluster integration branches + N PRs |

### Step 1: Load libraries

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/task-storage-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/complexity-estimator.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/parallelization-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/branch-utils.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/pr-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/file-overlap-detector.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/git-version-check.sh"
```

### Step 1.5: Pre-flight check on git version

Parallel mode spawns subagents with `isolation: "worktree"`, which uses
`git worktree add --no-track` (added in git 2.20). On older git (e.g. macOS
Xcode toolchains shipping git 2.15) the spawn fails with
`error: unknown option no-track`.

Check before planning so the planner output can be safely overridden:

```bash
detected_version="$(git_supports_worktree_no_track)"
git_check_status=$?
case "$git_check_status" in
  0)  PARALLEL_OK=1 ;;
  1)  PARALLEL_OK=0
      echo "git $detected_version detected; parallel worktrees require git 2.20+. Falling back to sequential strategy." ;;
  2)  echo "ERROR: $detected_version" >&2; exit 1 ;;
esac
```

When `PARALLEL_OK=0`, after Step 4 force-set `strategy = "sequential"` on the
plan regardless of what `plan_execution` returned, and proceed via Step 6a.
A missing/unparseable git binary (status 2) is fatal — autopilot needs git.

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

`compute_overlap` returns a JSON object with four fields:

- `byTask` — map from task id to the list of files mentioned in its description/acceptance criteria
- `overlaps` — list of `{file, tasks}` records, one per file that appears in 2+ tasks
- `metricOverlaps` — list of `{line, tasks}` records, one per shared metric line that 2+ tasks would touch even when they share no source files. Known metrics: `README.md` test count, `.claude-plugin/plugin.json` version field, `CHANGELOG.md` top entry. This catches the v0.6.0 regression where 3 PRs each bumped `Current state: NNN tests` and the second/third inherited a guaranteed merge conflict despite touching different `lib/` files.
- `hasOverlap` — boolean shortcut, true when EITHER `overlaps` OR `metricOverlaps` is non-empty.

Behavior:

- **`hasOverlap == false`** → no warning. Silently set strategy = **(a) separate PRs**. Do NOT prompt the user to pick a strategy. Proceed directly to the batch-spawn confirmation gate at the start of Step 6.
- **`hasOverlap == true`** → show the user BOTH the file-overlap matrix and the metric-overlap matrix (same `{file/line, tasks}` format), then ask which PR strategy to use:
  - **(a) Separate PRs** — current behavior, one PR per task. Reviewer handles conflicts.
  - **(b) Bundled PR** (recommended when one overlap cluster covers all/most tasks, OR when only metric overlap is present) — all tasks run in their own worktree branches, then their commits are cherry-picked sequentially into a single integration branch (`integration/sprint-<timestamp>`); conflicts are resolved during integration; one PR is opened listing all tasks.
  - **(c) Grouped PRs** (recommended when there are multiple disjoint file-overlap clusters) — `group_by_overlap` partitions tasks into clusters; one PR per cluster, following the bundled flow within each.

`recommend_pr_strategy` returns `bundled` whenever file overlap is empty but metric overlap covers 2+ tasks — bundling avoids the cascading single-line conflicts. Use it as the default suggestion; the user can override.

When `hasOverlap == true` and the user has chosen a strategy, surface the chosen strategy together with the batch-spawn confirmation in Step 6 (single yes/no gate). The strategy choice itself is NOT a separate confirmation step.

### Step 6: Batch-spawn confirmation gate

Before any of Steps 6a–6d run, present a single yes/no prompt summarizing: number of tasks, plan strategy (sequential/parallel), PR strategy ((a)/(b)/(c)), integration branch name (if applicable). This is the **only** confirmation gate in the sprint flow — no earlier strategy/overlap prompt counts as confirmation. On `no`, stop without spawning any subagent or worktree.

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

### Step 6d: Bundled or grouped PR execution (sequential mode)

When the chosen PR strategy is **(b) Bundled PR** or **(c) Grouped PRs** AND the plan strategy is `sequential` (either because the planner returned `sequential` or because Step 1.5 forced it on older git), worktrees are not used. The bundle is built directly on a single integration branch by sequentially implementing each task on it. The per-task agent must NOT push or open its own PR.

**Bundled + Sequential**:

1. From `main`, create one integration branch: `integration/sprint-<timestamp>`. Check it out.
2. For each task in plan order: run the same per-task logic as `/autopilot-task` (implement, run gates, commit) directly on the integration branch — no worktree, no separate per-task branch. Each task produces one commit on the integration branch. Stop the batch if any task fails gates after max iterations.
3. After all tasks succeed, run the FULL test suite (`bats tests/lib/`) on the integration branch. If green, push and open ONE PR listing every bundled task with its acceptance criteria.

**Grouped + Sequential**:

1. Run `group_by_overlap` on the enriched task array to get the clusters.
2. For each cluster (in order), repeat the bundled+sequential flow above with branch `integration/sprint-<timestamp>-group<N>` created from `main`. Each cluster produces ONE PR. N clusters = N PRs.
3. Between clusters, return to `main` before creating the next integration branch so each cluster starts from a clean baseline.

Conflicts cannot arise within a single integration branch in this mode (there is no cherry-pick step), but the same gate failures that would surface in parallel mode still apply per task. If a task fails gates, leave the integration branch in place so the user can inspect.

This matrix gap was first encountered during the v0.7.0 follow-up sprint (2026-04-27): the user selected grouped PRs and the planner forced sequential mode. The original spec only covered grouped+parallel via cherry-pick (Step 6c), leaving sub-Claudes to improvise. Step 6d makes that combination explicit.

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
