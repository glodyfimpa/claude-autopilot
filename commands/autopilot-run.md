---
name: autopilot-run
description: Full pipeline — PRD in, PRs out (decompose + sprint in one command)
---

Run the full autopilot pipeline from PRD to PRs. Argument received: $ARGUMENTS

## Purpose

One-shot command that combines `/autopilot-prd` and `/autopilot-sprint`. Reads a PRD from the configured source, decomposes it into tasks with user approval, then executes the full batch with adaptive parallelization. Every completed task lands as an open PR on the configured PR target.

Use this when you have a PRD ready and you want to go straight from "spec" to "review queue".

## Arguments

- `<ref>` identifier the PRD source provider understands (same semantics as `/autopilot-prd`)

## Preconditions

- `.autopilot-pipeline.json` fully configured (all four stages).
- Git repository with a `main` branch.
- Quality gates active (recommended: `/autopilot on`).

## Actions

### Step 1: Delegate to `/autopilot-prd`

Run the full `/autopilot-prd $ARGUMENTS` workflow. On user rejection or failure, stop here.

### Step 2: Delegate to `/autopilot-sprint`

Once the tasks are persisted (or kept in chat for `chat-paste`), delegate to `/autopilot-sprint`. No filter argument — run every task that was just created in this session.

### Step 3: Final summary

Print a single summary table at the end showing:

- PRD title and source ref
- Number of tasks decomposed
- Number of tasks that reached "done"
- List of PR URLs
- List of failed tasks with their failure reasons

## Notes

- This command is a convenience orchestrator. All the heavy lifting lives in `/autopilot-prd` and `/autopilot-sprint`. Keep the implementations consistent by delegating to them rather than duplicating their logic here.
- The first time you run `/autopilot-run` on a new project, it will trigger `/autopilot-configure` automatically if `.autopilot-pipeline.json` is missing.
