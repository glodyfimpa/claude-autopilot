---
name: autopilot-configure
description: Run the autopilot setup wizard to configure pipeline providers (PRD source, task storage, PR target, parallelization)
---

Run the autopilot setup wizard. Argument received: $ARGUMENTS

## Purpose

Configure (or reconfigure) the autopilot pipeline for the current project. The wizard detects available MCPs and the git remote, proposes sensible defaults for each stage, and writes the confirmed choices to `.autopilot-pipeline.json` in the project root.

Configurable stages:

- **prd-source** where PRDs are read from (local-file, chat-paste, notion, jira, google-drive)
- **task-storage** where decomposed tasks live (local-file, chat-paste, notion, jira, linear, backlog)
- **pr-target** where pull requests are opened (github, gitlab, bitbucket)
- **parallelization** how the orchestrator plans execution (adaptive, always-sequential, always-parallel)

## Arguments

- `(no argument)` run the full wizard for every stage
- `<stage>` reconfigure one stage only (e.g. `/autopilot-configure task-storage`)

## Actions

### Step 1: Load libraries

Source the required libraries from `${CLAUDE_PLUGIN_ROOT}/lib`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/mcp-detector.sh"
source "${CLAUDE_PLUGIN_ROOT}/lib/wizard.sh"
```

### Step 2: Collect proposals

If no argument was given, run `wizard_propose_all` and parse the JSON. Otherwise run `wizard_propose <stage>` for the single requested stage.

### Step 3: Present defaults to the user

For each stage in the proposal, show the user:

1. The stage name (human friendly: "PRD source", "Task storage", "PR target", "Parallelization strategy")
2. The recommended default (with the reason when applicable: "detected Notion MCP", "detected github.com remote", etc.)
3. The list of valid options

Ask the user to confirm each default. Use the AskUserQuestion tool to present the options with the default as the first choice labelled "(Recommended)".

### Step 4: Apply each confirmed choice

For every confirmed answer, call `wizard_apply <stage> <provider>`. If any call fails, surface the error and abort the remaining steps.

### Step 5: Summarise the final config

Print the content of `.autopilot-pipeline.json` so the user can see exactly what was written. Remind them that the file is project-local and can be re-edited by running `/autopilot-configure <stage>` or by editing the JSON directly.

### Step 6: Next steps

Tell the user:

- Run `/autopilot-prd <ref>` to decompose a PRD into tasks
- Run `/autopilot-task <ref>` to execute a single task end-to-end
- Run `/autopilot-sprint` to run the full batch of ready tasks
- Run `/autopilot-run <prd_ref>` to go from PRD all the way to PRs in one shot

## Error handling

- If `jq` is missing, tell the user to install it (`brew install jq` on macOS, `apt-get install jq` on Debian/Ubuntu) and abort.
- If the project directory is not writable, surface the error and abort.
- Do NOT overwrite an existing `.autopilot-pipeline.json` on first run without telling the user. If the file already exists and the user passed no stage argument, warn that running the full wizard will overwrite existing choices and ask for confirmation.
