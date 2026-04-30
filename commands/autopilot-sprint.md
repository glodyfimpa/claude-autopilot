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

Run `task_storage_list ready`. The adapter validates the canonical status (`ready | in_progress | done`) and the provider applies the filter natively (jq for local providers, JQL / Notion filter / GraphQL filter for remote). If zero tasks are returned, stop and tell the user the queue is empty.

### Step 3: Estimate complexity for every task

For each task, call `estimate_complexity` and attach the result as a `complexity` field on the task JSON. Keep the enriched array.

### Step 3.5: Deterministic scope filtering

Source `lib/scope-filter.sh` and call `scope_filter_apply "$enriched_tasks_json"`. The filter returns:

```json
{
  "kept": ["TASK-001", "TASK-002", ...],
  "excluded": [
    {"id": "TASK-X", "rule": "A", "reason": "explicit precondition unmet (...)"},
    {"id": "TASK-Y", "rule": "B", "reason": "deliverable targets a repository ..."}
  ]
}
```

Replace the enriched task array with the `kept` subset. Keep the `excluded` list for the run summary and the final PR description.

The filter applies four deterministic rules (regex/graph driven; conservative — false negatives preferred over false positives):

- **Rule A — explicit precondition not satisfied**: task description contains an anchor like "don't build until X" / "wait until X" / "blocked until X" combined with a future-condition signal (count, "more", "have happened"). Excluded.
- **Rule B — deliverable outside current repo**: task description names an external project (Freelance Compass, RESEVO, bnb-investment-toolkit, life-os, ...) AND either an action verb (run/validate/build/deploy/...) targeting it OR a nominalized deliverable ("validation report on <project>"). Excluded.
- **Rule C — broken dependency**: task declares a dependency on an id that is not present in the current ready list. Excluded.
- **Rule D — contradictory ACs**: reserved for future use; not yet implemented.

Tasks not matching any rule pass through unchanged. **The filter never prompts the user.** Auto-mode is hand-off — exclusions are reported in the final summary and PR body, not asked mid-flight.

If `excluded` is non-empty, surface it once at this point in a tabular log line per excluded task (`[scope-filter] EXCLUDED <id> rule=<X> reason="<text>"`) so the user sees why the queue shrank when they review the run output.

If after filtering the `kept` list is empty, stop and tell the user the queue had only excluded tasks, naming each.

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

#### Step 5.1: Detect file overlap and select a PR strategy

Run the overlap detector on the enriched task array:

```bash
overlap="$(compute_overlap "$enriched_tasks_json")"
recommendation="$(recommend_pr_strategy "$enriched_tasks_json")"
```

`compute_overlap` returns a JSON object with four fields:

- `byTask` — map from task id to the list of files mentioned in its description/acceptance criteria
- `overlaps` — list of `{file, tasks}` records, one per file that appears in 2+ tasks
- `metricOverlaps` — list of `{line, tasks}` records, one per shared metric line that 2+ tasks would touch even when they share no source files. Known metrics: `README.md` test count, `.claude-plugin/plugin.json` version field, `CHANGELOG.md` top entry. This catches the v0.6.0 regression where 3 PRs each bumped `Current state: NNN tests` and the second/third inherited a guaranteed merge conflict despite touching different `lib/` files.
- `hasOverlap` — boolean shortcut, true when EITHER `overlaps` OR `metricOverlaps` is non-empty.

PR strategy selection (zero-prompt — auto-mode hand-off):

- **`hasOverlap == false`** → set strategy = **(a) separate PRs** silently.
- **`hasOverlap == true`** → set strategy = output of `recommend_pr_strategy` (typically **(b) bundled** when one cluster dominates or only metric overlap is present; **(c) grouped** when there are multiple disjoint clusters). Log the overlap matrix and the chosen strategy to the run output for transparency, but do NOT prompt the user.

The autopilot's hand-off contract requires that strategy choice be deterministic. `recommend_pr_strategy` is the single source of truth; if the user disagrees with the recommendation in a particular run, the corrective path is post-hoc PR review (request a re-roll or manual rebase), not a mid-execution prompt.

The chosen strategy is then surfaced together with the decision summary at Step 6.

### Step 6: Batch-spawn decision point

Before any of Steps 6a–6d run, **declare** (do not prompt) a single decision summary line and proceed:

```
[autopilot-sprint] proceeding: N tasks, plan=<sequential|parallel>, pr-strategy=<separate|bundled|grouped>, integration-branch=<name|n/a>
```

Auto-mode is hand-off: the decision is informed (already shaped by Step 1.5 git check, Step 3.5 scope filtering, Step 4 planner output, Step 5.1 overlap detection / strategy recommendation) and announced for transparency, but no user input is required. The previous "confirmation gate" wording — single yes/no prompt before spawn — is replaced because waiting on a prompt mid-execution defeats the hand-off contract that defines `/autopilot-sprint`'s purpose.

If a strategy step earlier in the flow flagged user input (e.g. an `hasOverlap == true` situation when running in INTERACTIVE mode, not auto-mode), that prompt happens at Step 5.1 — never here. In auto-mode `hasOverlap == true` ALSO skips the prompt: the controller takes the `recommend_pr_strategy` output as authoritative and proceeds.

The `excluded` list from Step 3.5 (if any) is captured for the final report. Excluded tasks remain in their original status (typically `ready`) so the user can re-run them manually with `/autopilot-task <ref>` after reviewing the report.

### Step 6a: Sequential execution

When the plan strategy is `sequential` and the chosen PR strategy is **(a) Separate PRs**, iterate the groups in order and spawn one isolated subagent per task using the `Agent` tool with `isolation: "worktree"`. Same dispatch pattern as Step 6b (parallel) — the only difference is **maxConcurrency = 1**, so the controller dispatches the next subagent only after the previous one has finished.

Do NOT recursively invoke `/autopilot-task <ref>` from inside the same session. The recursive invocation pattern (used in earlier versions) inherits the controller's full session context across tasks, which leaks state from task N into task N+1. The fresh-subagent pattern matches Step 6b's architecture and the discipline confirmed by the 2026-04-29 fix sprint (11 isolated subagents, zero cross-task drift, two real bugs caught at per-task review).

**Per-task subagent prompt** — the controller curates each subagent's prompt from this template:

```
You are an autopilot implementer subagent for ONE task. Run the inner-loop
defined in the `autopilot` skill (`skills/autopilot/SKILL.md`) and stop at
the task-complete marker. Do NOT push and do NOT open a PR — that is the
controller's job.

Task ref: <id>
Title: <title>
Description: <description verbatim>
Acceptance criteria: <numbered list verbatim>
Complexity tier: <tier>  # determines whether TDD strict applies

Project conventions:
- bash 3.2 + BSD coreutils (macOS) — NO bash 4+ syntax, NO declare -A,
  NO mapfile, sed -i needs a suffix.
- Tests: bats-core. Run `bats tests/lib/` for the full suite.
- Worktree path: <absolute path injected by the Agent tool>.

When done, write the marker file `~/.claude/.autopilot-task-complete` and
return a structured summary: files changed, commit hash, gate results.
```

The controller waits for each subagent to complete before dispatching the next. If a subagent fails the inner-loop gates after max iterations (defined by the skill), STOP the batch and report the failure — do not dispatch the next task. Failed tasks remain in `in_progress` status so the user can resume them with `/autopilot-task <ref>` after fixing the blocker.

**Parity with Step 6b.** Sequential and parallel modes share the same per-task contract: one Agent tool invocation, one worktree, one commit, no push, no PR. The only difference is the dispatch concurrency — `maxConcurrency = 1` for sequential, `maxConcurrency = plan.maxConcurrency` for parallel. This parity simplifies reasoning about the sprint flow: whether tasks run one at a time or in fan-out, the per-task agent looks the same.

**Worktree cleanup.** After each subagent completes (success or failure), the controller cleans up the worktree following the standard pattern: `cd <main repo>` → `git worktree remove <path>` (or `rm -rf <path> && git worktree prune` on git < 2.17). The integration branch (or per-task branches in (a) Separate PRs) keeps the commits.

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

Print TWO tables:

**Executed tasks:**
- Task ref
- Final status (done / failed)
- PR URL (if done)
- Failure reason (if failed)

**Excluded by scope filter (Step 3.5):**
- Task ref
- Rule (A / B / C / D)
- Reason (one line)
- Re-include command (`/autopilot-task <ref>`)

If `excluded` is empty, omit the second table.

The bundled or grouped PR description (when applicable) MUST also include the excluded list under a `## Excluded from this sprint` section, so reviewers can audit the filter's decisions and the user has a permanent record beyond the terminal output.

Remind the user that failed tasks are in `in_progress` state and can be resumed individually with `/autopilot-task <ref>`. Excluded tasks remain in their original state (typically `ready`) and can be re-attempted via the same command after the user verifies the precondition is satisfied or the rule no longer applies.

## Error handling

- If the task storage provider doesn't support `list`, fail fast with a helpful message telling the user to add tasks via `/autopilot-prd` first, or switch to a storage that supports listing.
- If a parallel subagent crashes, its worktree must still be cleaned up. Use a cleanup phase that runs regardless of outcome.
- If the token budget estimate exceeds the configured cap, log a `[autopilot-sprint] WARNING: estimated token budget <X> exceeds configured cap <Y> — proceeding anyway under auto-mode hand-off` line and proceed. Do NOT prompt the user. The cap is informational; if the user wants the cap to be enforced, they should switch to interactive mode or lower the parallel concurrency in `.autopilot-pipeline.json`.
