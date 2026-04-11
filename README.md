```
             _              _ _       _   
  __ _ _   _| |_ ___  _ __ (_) | ___ | |_ 
 / _` | | | | __/ _ \| '_ \| | |/ _ \| __|
| (_| | |_| | || (_) | |_) | | | (_) | |_ 
 \__,_|\__,_|\__\___/| .__/|_|_|\___/ \__|
                     |_|
```

A Claude Code plugin for autonomous development.

Toggleable quality gates (test, lint, types, build) after every Claude iteration, plus an optional full pipeline that goes from PRD to open pull request in one command. Tool-agnostic at every stage: read PRDs from local files, Notion, Jira, or Google Drive; store tasks in local files, Notion, Jira, Linear, or Backlog; open PRs on GitHub, GitLab, or Bitbucket. Pick the tools you already use, skip the rest.

Inspired by [Echofold's autonomous development pipeline](https://echofold.ai/news/how-to-automate-claude-code-autonomous-development).

## Install

Inside a Claude Code session:

```
/plugin marketplace add glodyfimpa/claude-autopilot
/plugin install claude-autopilot@claude-autopilot
```

Or from the terminal:

```bash
claude plugin marketplace add glodyfimpa/claude-autopilot
claude plugin install claude-autopilot@claude-autopilot
```

Or interactively inside Claude Code:

```
/plugin marketplace add glodyfimpa/claude-autopilot
/plugin
```

Then go to the **Discover** tab, select `claude-autopilot`, and choose a scope (user, project, or local).

Verify with `/plugin list` (or `claude plugin list`). You should see `claude-autopilot@claude-autopilot — Status: ✔ enabled`. Restart Claude Code after installing so the new slash commands are registered.

After installing, turn on the quality gates loop:

```
/autopilot on
```

The plugin detects your project stack (Node, Python, Java, Rust, Go) and registers permission rules for the gate commands. To use the full PRD→PR pipeline, run the setup wizard once per project:

```
/autopilot-configure
```

The wizard scans active MCPs and the git remote, proposes defaults for each stage, and writes a config file at `.autopilot-pipeline.json` in the project root. Reconfiguring a single stage later is possible with `/autopilot-configure <stage>`.

## Update

```
/plugin marketplace update claude-autopilot
```

To receive updates automatically:

1. Run `/plugin`
2. Go to the **Marketplaces** tab
3. Select `claude-autopilot`
4. Select **Enable auto-update**

### Team setup

Pre-enable the plugin in `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "claude-autopilot@claude-autopilot": true
  },
  "extraKnownMarketplaces": {
    "claude-autopilot": {
      "source": {
        "source": "github",
        "repo": "glodyfimpa/claude-autopilot"
      }
    }
  }
}
```

## Prerequisites

claude-autopilot works in three modes depending on which tools you connect:

| Mode | What you run | How it works |
|------|--------------|--------------|
| **Gates only** | `/autopilot on` | Stop hook runs test/lint/types/build after every Claude iteration. No pipeline, no PR automation. Works on any project out of the box. |
| **Full pipeline** | `/autopilot-configure` + pipeline commands | Reads a PRD, decomposes it into tasks, executes each task on its own branch, opens one PR per task on the configured host. |
| **Chat-only** | `/autopilot-configure` with `chat-paste` providers | No external tools required. Tasks and PRDs live in the conversation; branches and PRs still follow the Echofold convention. |

Runtime requirements:

| Category | Required | Notes |
|----------|----------|-------|
| Shell | `bash` 3.2+ | Works on macOS (stock bash), Linux, WSL, Git Bash on Windows |
| JSON | `jq` 1.6+ | `brew install jq` or `apt-get install jq` |
| Git | `git` 2.20+ | Required by the PR adapter and branch utilities |
| PR CLI | `gh` for GitHub, `glab` for GitLab, `bb` for Bitbucket | Only the one matching your pr-target provider |

Supported pipeline providers (any tool with an MCP server can be added later):

| Stage | Implemented | Stubs available |
|-------|-------------|-----------------|
| PRD source | local-file, chat-paste | notion, jira, google-drive |
| Task storage | local-file, chat-paste | notion, jira, linear, backlog |
| PR target | github | gitlab, bitbucket |

## Commands

| Command | Does |
|---------|------|
| `/autopilot on` | Detect stack, register permission rules, activate the Stop hook quality gates |
| `/autopilot off` | Deactivate gates, remove permission rules added on activation |
| `/autopilot status` | Show whether gates are active, detected stack, iteration count if any |
| `/autopilot-configure` | First-run wizard for the full pipeline: picks providers for PRD source, task storage, PR target, parallelization |
| `/autopilot-configure <stage>` | Reconfigure one stage only (e.g. `/autopilot-configure task-storage`) |
| `/autopilot-prd <ref>` | Read a PRD from the configured source and decompose it into tasks with user approval |
| `/autopilot-task <ref>` | Run one task end-to-end: branch from main, implement, verify, commit, push, open PR |
| `/autopilot-sprint` | List every ready task, estimate complexity, plan execution (sequential or parallel worktrees), run the batch |
| `/autopilot-run <prd_ref>` | Full pipeline in one shot: delegates to `/autopilot-prd` then `/autopilot-sprint` |

## How it works

The plugin has two loops that operate at different scopes.

The **inner loop** is the quality gates cycle. After every Claude iteration the Stop hook reads the detected stack from `hooks/detect-stack.sh` and runs the four gate commands (test, lint, types, build) in sequence. If any gate fails, Claude receives the error output and tries again, up to five iterations per session. If all gates pass and the acceptance criteria for the active task are satisfied, Claude writes a marker file at `~/.claude/.autopilot-task-complete` and the hook emits a task-complete signal. The outer loop picks up the signal to commit, push, and open the PR. Without the marker, gates passing only means "this iteration was clean" and Claude keeps working on the rest of the task.

The **outer loop** is the PRD→PR pipeline and it is driven by four tool-agnostic adapters that live in `lib/`. `prd-source-adapter.sh` reads a spec from wherever it lives (local markdown, pasted chat, Notion page, Jira epic, Google Doc) and returns a normalized JSON object. Claude then decomposes the PRD into tasks interactively with the user and persists them through `task-storage-adapter.sh` to the configured backend. `/autopilot-task` cuts a fresh branch from `main` using the Echofold naming convention (`feat/{PROJECT}-{ticket}-{slug}` or `fix/{PROJECT}-{ticket}-{slug}`), runs the inner loop until the task-complete marker is set, then calls `pr-adapter.sh` to open the PR on the configured host. `/autopilot-sprint` adds the fourth adapter, `parallelization-adapter.sh`, which decides based on task complexity and shared-file dependencies whether to run tasks sequentially or in parallel worktrees.

Every adapter dispatches by naming convention: a single `adapter_dispatch` helper in `lib/adapter-base.sh` looks up `<layer>_<provider>_<action>` and calls it. Adding a new provider means editing one line in `lib/known-providers.sh` and dropping a file under `lib/<layer>-providers/`. The three existing adapters sum to 119 lines of code on top of a 96-line shared base.

## Decision criteria

The plugin enforces a single execution hierarchy: **gates before anything else**. No commit, no push, no PR until the four gates pass on real changes. When gates fail after five iterations, the loop stops and asks the user for help rather than merging broken work.

The task-complete marker is the load-bearing abstraction. It separates "this iteration is clean" from "this task is done". Without it, an automatic PR on the first clean iteration would open pull requests with half-finished features just because the tests happened to compile. The marker is written by the Claude skill only after every acceptance criterion is verified in code and a security review has passed.

Branching is never negotiable: each task starts from `main`, never from a feature branch. Parallel sprint runs use `git worktree add` for isolation and clean up on completion or cancellation.

Complexity estimation favors caution: trivial batches run sequentially (parallel overhead is not worth it), complex tasks force sequential execution (they need full context), and the adaptive strategy parallelizes only when all tasks are standard and share no files with each other.

## Structure

```
claude-autopilot/                                    the plugin
├── .claude-plugin/
│   └── plugin.json                                  plugin manifest
├── commands/
│   ├── autopilot.md                                 /autopilot on|off|status
│   ├── autopilot-configure.md                       /autopilot-configure [stage]
│   ├── autopilot-prd.md                             /autopilot-prd <ref>
│   ├── autopilot-task.md                            /autopilot-task <ref>
│   ├── autopilot-sprint.md                          /autopilot-sprint [filter]
│   └── autopilot-run.md                             /autopilot-run <prd_ref>
├── skills/
│   └── autopilot/
│       └── SKILL.md                                 inner loop workflow + task-complete marker
├── hooks/
│   ├── detect-stack.sh                              stack auto-detection (Node/Java/Python/Rust/Go)
│   ├── pretool-gate.sh                              PreToolUse: block dangerous operations
│   ├── stop-gate.sh                                 Stop: quality gates + task-complete marker
│   └── subagent-stop.sh                             SubagentStop: parallel sprint observability
├── hooks.json                                       hook registration
├── lib/
│   ├── adapter-base.sh                              shared dispatch skeleton for adapters
│   ├── known-providers.sh                           single source of truth for provider lists
│   ├── config.sh                                    read/write .autopilot-pipeline.json
│   ├── branch-utils.sh                              Echofold branch naming, slugify, create from main
│   ├── mcp-detector.sh                              scan enabled MCPs and git remote
│   ├── wizard.sh                                    non-interactive wizard helpers
│   ├── complexity-estimator.sh                      task tier scoring (trivial/standard/complex/epic)
│   ├── parallelization-adapter.sh                   plan execution: sequential vs parallel
│   ├── prd-source-adapter.sh                        PRD source dispatcher
│   ├── prd-source-providers/                        local-file, chat-paste, notion, jira, google-drive
│   ├── task-storage-adapter.sh                      task storage dispatcher
│   ├── task-storage-providers/                      local-file, chat-paste, notion, jira, linear, backlog
│   ├── pr-adapter.sh                                PR target dispatcher
│   └── pr-providers/                                github, gitlab, bitbucket
├── tests/
│   ├── helpers/
│   │   └── test_helper.bash                         bats helpers: tmpdir, fake git repo, assertions
│   └── lib/
│       └── *.bats                                   one bats file per lib module (107 tests)
├── CONTRIBUTING.md                                  TDD workflow, portability rules, adding providers
└── README.md
```

6 commands, 1 skill, 4 hooks, 10 library modules, 16 provider files (6 implemented, 10 stubs), 107 bats tests.

User config (generated by `/autopilot-configure`, not in the plugin):

```
.autopilot-pipeline.json                             per-project pipeline config
~/.claude/.autopilot-enabled                         gates-loop on/off marker
~/.claude/.autopilot-task-complete                   task-complete signal (transient)
~/.claude/.autopilot-<session>.json                  per-session iteration counter
```

## Portability

The plugin runs on:

- macOS (stock bash 3.2, BSD coreutils)
- Linux (bash 4+/5, GNU coreutils)
- WSL on Windows
- Git Bash on Windows

Explicitly avoided features that would break macOS or BSD systems:

| Avoided | Reason |
|---------|--------|
| `${var,,}` / `${var^^}` | bash 4+ only; uses `tr '[:upper:]' '[:lower:]'` instead |
| `declare -A` | bash 4+ only; uses integer-indexed arrays |
| `sed -i ''` vs `sed -i` | portable form is `sed -i.bak ... && rm -f *.bak` |
| `awk -v RS='multi-char'` | BSD awk only supports single-char RS; bash string ops instead |
| `readlink -f`, `date --iso-8601`, `mapfile` | GNU-only; pure bash equivalents used |

See `CONTRIBUTING.md` for the complete list.

## Development

**This section is for contributors to the plugin codebase, not for end users.** If you installed claude-autopilot with `/install-plugin`, everything is already set up.

### TDD workflow

Every `lib/` module is built test-first with [bats-core](https://github.com/bats-core/bats-core). Install bats with `brew install bats-core` on macOS or `apt-get install bats` on Debian.

Run the full suite:

```
bats tests/lib/
```

Current state: 107 tests, all green on macOS bash 3.2.

When adding a feature:

1. Write the failing test first in `tests/lib/<module>.bats` (use `tests/helpers/test_helper.bash` for `setup_isolated_tmpdir`, `make_fake_git_repo`, assertions).
2. Run the test and confirm it fails for the right reason.
3. Write the minimum implementation in `lib/<module>.sh` that makes the test pass.
4. Refactor keeping the suite green.
5. Run the full suite before committing.

### Adding a new provider

1. Create `lib/<layer>-providers/<name>.sh` exposing `<layer>_<name_with_underscores>_<action>` functions.
2. Add the name to the matching constant in `lib/known-providers.sh`.
3. Write a new bats test in the corresponding `tests/lib/<layer>-adapter.bats`.
4. Run `bats tests/lib/`. All tests must stay green before opening a PR.

Full details in `CONTRIBUTING.md`.

## License

MIT
