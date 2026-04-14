---
name: autopilot
description: Autopilot mode with deterministic quality gates and full PRD→PR pipeline. Loaded when user activates /autopilot on or invokes /autopilot-task, /autopilot-sprint, /autopilot-prd, /autopilot-run
---

# Autopilot Mode

When autopilot is active, follow this workflow.

## Inner loop — implement + verify

Used by `/autopilot-task` and every subagent spawned by `/autopilot-sprint`. The goal is: bring ONE task from "ready" to "done" through the quality gates, then signal completion so the outer loop can open a PR.

### Work cycle

1. **ANALYZE** the task before writing code. Read the relevant files, understand the surrounding context, map out dependencies.
2. **PLAN** the changes: which files to modify, in what order, and how they depend on each other.
3. **IMPLEMENT** in logical, coherent blocks. Never mix unrelated edits into the same iteration.
4. The Stop hook automatically runs the quality gates: `test`, `lint`, `types`, `build`. The specific commands come from the detected stack.
5. If the Stop hook blocks you, read the error carefully and fix the specific problem. Do not rewrite large sections hoping to "make it work".
6. When all gates pass, run the **code quality adapter** (`lib/code-quality-adapter.sh`). The adapter dispatches to the configured provider (SonarQube, Semgrep, CodeClimate, or none) and enters a retry loop: scan, review issues, fix, re-scan, up to 5 iterations. If issues remain after 5 iterations, STOP and report the findings. Do not write the task-complete marker.
7. **Code simplification** -- if `simplify.mode` is `auto` (check with `config_get "simplify.mode"`; treat missing/empty as `auto`), invoke the code-simplifier subagent on the changed files: *"use a code-simplifier subagent to review and simplify the changes"*. If `simplify.mode` is `manual`, skip this step (the user can run `/simplify` themselves). If `simplify.mode` is `off`, skip entirely with no message. After simplification, re-run quality gates to confirm the simplified code still passes.
8. **Frontend verification** -- if `frontend_verify.provider` is not `none` (check with `config_get "frontend_verify.provider"`), run `frontend_verify_run` from `lib/frontend-verify-adapter.sh`. The adapter dispatches to chrome-devtools or playwright and returns a pass/fail report. If verification fails, fix the issues and re-verify. If the provider is `none`, this step is silently skipped.
9. When code quality, simplification, and frontend verification pass AND every acceptance criterion is satisfied, call the `security-reviewer` subagent: *"use a security-reviewer subagent to check the changes"*.
10. When the security review has no blocking findings, write the task-complete marker file (see below). This tells the Stop hook to let the outer loop commit and open the PR.

### Task-complete marker

The marker is a zero-byte file at `~/.claude/.autopilot-task-complete`. Write it with:

```bash
: > ~/.claude/.autopilot-task-complete
```

When the Stop hook sees this marker, it emits a "task complete" signal instead of forcing another gate cycle. The outer loop (`/autopilot-task`) picks up the signal, commits, pushes, and opens the PR. After the outer loop finishes, the marker is removed.

**Do not write the marker until all of the following are true:**
- Every acceptance criterion is satisfied by code (not by comments or TODOs).
- All quality gates pass (`test`, `lint`, `types`, `build`).
- Code quality scan passes with 0 issues (or the provider is set to `none`).
- Code simplification passed (or `simplify.mode` is `off`/`manual`).
- Frontend verification passed (or `frontend_verify.provider` is `none`).
- The security-reviewer subagent returned no blocking findings.
- The working tree has real changes to commit.

### Operating rules

- Work autonomously: implement, verify, and fix without asking for confirmation on routine code operations.
- The hook system protects you from dangerous operations (you cannot touch `.env`, credentials, etc.).
- Permission rules for the gate commands were added to `settings.local.json` on activation, so they should not require user approval.
- If you reach the 5-iteration limit without passing the gates, STOP and clearly explain what is failing. Do not write the task-complete marker.
- Use subagents for investigations that require reading many files — this protects the main context window.
- If context fills up, use `/compact` to free space.
- Never skip gates: if tests don't exist, create them before implementing the feature.

## Outer loop — full pipeline

The outer loop is orchestrated by the slash commands, not by this skill directly. Reference:

- `/autopilot-configure` first-run wizard that writes `.autopilot-pipeline.json`.
- `/autopilot-prd <ref>` read a PRD from the configured source, decompose it into tasks, and persist them into the configured task storage.
- `/autopilot-task <ref>` run one task through the inner loop, then commit + push + open a PR on the configured PR target.
- `/autopilot-sprint [filter]` list every ready task, estimate complexity, plan execution (sequential or parallel), and run all of them.
- `/autopilot-run <prd_ref>` chain `/autopilot-prd` and `/autopilot-sprint` in one shot.

### Branch strategy (Echofold)

Every task runs on its own branch, always created from `main`:

- Feature: `feat/{PROJECT}-{ticket}-{slug}`
- Fix: `fix/{PROJECT}-{ticket}-{slug}`

`{PROJECT}` defaults to the repo name in uppercase if no prefix is configured. `{ticket}` comes from the task storage provider (id, key, or a timestamp). `{slug}` is a kebab-case version of the task title, max 40 chars.

Never reuse an existing branch. Never branch from a feature branch (worktree subagents are the only exception, and they still root-check against `main`).

### Parallelization (Phase 4)

When `/autopilot-sprint` runs with strategy `adaptive` or `always-parallel`, tasks are grouped by shared-file dependencies and distributed across worktrees. Hard cap defaults to 3 concurrent lanes. Each lane runs this same inner loop inside an isolated worktree.

## Pipeline recap

```
PRD source → decomposition → task storage → task execution → PR target
  (adapter)       (Claude)        (adapter)       (adapter)       (adapter)
```

Every stage is provider-agnostic: local files, chat paste, Notion, Jira, Linear, Backlog, GitHub, GitLab, Bitbucket are all plug-and-play. The configuration lives in `.autopilot-pipeline.json` at the project root.
