---
name: autopilot-prd
description: Read a PRD from the configured source and decompose it into tasks stored in the configured task storage
---

Decompose a PRD into actionable tasks. Argument received: $ARGUMENTS

## Purpose

Pipeline phase 1: read a Product Requirements Document from whichever provider is configured (local markdown file, pasted chat text, Notion page, Jira epic, Google Doc), then guide the user through decomposing it into concrete engineering tasks that land in the configured task storage.

## Arguments

- `<ref>` identifier passed to the PRD source provider
  - `local-file`: path to a markdown file (e.g. `prd/checkout-redesign.md`)
  - `chat-paste`: the full PRD text on the same line (or on the lines below the command)
  - `notion`: Notion page id
  - `jira`: Jira epic key (e.g. `PROJ-123`)
  - `google-drive`: Google Doc id

## Preconditions

- `.autopilot-pipeline.json` must exist and have `prd_source.provider` and `task_storage.provider` set. If either is missing, run `/autopilot-configure` first.

## Actions

### Step 1: Load libraries

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/prd-source-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/task-storage-adapter.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/complexity-estimator.sh"
```

### Step 2: Fetch the PRD

Run `prd_source_fetch "$ARGUMENTS"` and capture the returned JSON. On non-zero exit, stop and report the error.

### Step 3: Decompose into tasks

Using the PRD title, description, and context, propose a list of engineering tasks. Each task must have:

- A concise, imperative title (e.g. "Add session token rotation", not "Session tokens")
- A description explaining what and why, grounded in the PRD
- 2-5 acceptance criteria that describe observable outcomes, not implementation steps

Guidelines for decomposition:

- Prefer vertical slices (a small end-to-end change) over horizontal layers (all backend first, then frontend).
- Each task should be mergeable on its own without breaking the main branch.
- Tasks that touch the same module should be sequenced to avoid merge conflicts.
- If a single "task" feels larger than ~6 acceptance criteria, split it further.

### Step 4: Present the proposed tasks to the user

Show the full list with title + criteria and ask for approval. Use the AskUserQuestion tool so the user can:

- Approve the list as-is
- Request splitting/merging of specific tasks
- Remove tasks they don't want in this batch
- Add tasks that were missed

Iterate until the user approves the final list.

### Step 5: Run complexity estimation (preview)

For each approved task, call `estimate_complexity` with the task JSON and show the resulting tier (trivial / standard / complex / epic). Flag any epic tasks and suggest splitting them further.

### Step 6: Persist tasks to the configured storage

For each approved task, call:

```bash
task_storage_create "<title>" "<description>" "<comma_separated_criteria>"
```

Capture the returned ref (path or id) per task. If the storage is `chat-paste`, skip this step and keep the tasks in the conversation.

### Step 7: Summary

Print a list of the created tasks with their refs so the user can run `/autopilot-task <ref>` or `/autopilot-sprint` next.

## Error handling

- If the PRD source returns exit 2 (stub provider), tell the user the provider is not implemented yet and list alternatives.
- If the task storage returns exit 2, same handling.
- If the user rejects every decomposition attempt more than 3 times, pause and ask whether the PRD itself needs revision instead.
