# Claude Autopilot

A Claude Code plugin that turns the editor into a self-driving development loop. It combines two layers:

1. **Quality gates loop** (original feature) — deterministic `test`, `lint`, `types`, `build` checks after every Claude iteration, with stack auto-detection and safe defaults.
2. **Full PRD→PR pipeline** (v0.2+) — a tool-agnostic orchestrator that reads a PRD, decomposes it into tasks, executes each one on its own branch, and opens one PR per task on the configured host.

Inspired by [Echofold's autonomous development pipeline](https://echofold.ai/news/how-to-automate-claude-code-autonomous-development).

---

## Quick start

### 1. Install

Add to your `~/.claude/settings.json`:

```json
{
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

Enable the plugin via `/plugin`.

### 2. Requirements

- `bash` 3.2 or newer (works out of the box on macOS, Linux, WSL, and Git Bash on Windows)
- `jq` (`brew install jq`, `apt-get install jq`, or equivalent)
- `git`
- For the PR target you pick: `gh` for GitHub, `glab` for GitLab, `bb` for Bitbucket

### 3. Turn on quality gates

```
/autopilot on
```

This detects the stack, registers permission rules for the gate commands, and activates the Stop hook.

### 4. Configure the pipeline (one-off per project)

```
/autopilot-configure
```

The wizard detects your MCPs and git remote, proposes sensible defaults, and writes everything to `.autopilot-pipeline.json` in the project root. Rerun at any time to reconfigure a single stage (`/autopilot-configure task-storage`).

### 5. Run something

```
/autopilot-task tasks/t1.md             # execute one task end-to-end
/autopilot-prd prd/checkout.md          # decompose a PRD into tasks
/autopilot-sprint                       # run every ready task in the storage
/autopilot-run prd/checkout.md          # full pipeline: PRD → tasks → PRs
```

---

## Architecture

The pipeline is made of four tool-agnostic adapters. Each one dispatches to a pluggable provider; the selection lives in `.autopilot-pipeline.json`.

```
PRD source ──▶ decomposition ──▶ task storage ──▶ task execution ──▶ PR target
  (adapter)      (Claude LLM)       (adapter)         (adapter)         (adapter)
                                                          │
                                                          ▼
                                                 parallelization
                                                    (adapter)
```

### PRD source adapter (`lib/prd-source-adapter.sh`)

Reads a Product Requirements Document and returns a normalized JSON object. Providers:

| Provider | Status | Ref semantics |
|---|---|---|
| `local-file` | ✅ | Path to a markdown file |
| `chat-paste` | ✅ | Raw PRD text |
| `notion` | stub | Notion page id (requires Notion MCP) |
| `jira` | stub | Jira epic key (requires Atlassian MCP) |
| `google-drive` | stub | Google Doc id (requires Google Drive MCP) |

### Task storage adapter (`lib/task-storage-adapter.sh`)

Persists and retrieves decomposed tasks. Providers:

| Provider | Status | Notes |
|---|---|---|
| `local-file` | ✅ | Markdown files with YAML frontmatter under `tasks/` |
| `chat-paste` | ✅ | In-conversation, no persistence |
| `notion` | stub | Database page under a parent |
| `jira` | stub | Issues in a project |
| `linear` | stub | Issues in a team |
| `backlog` | stub | Tickets via the Backlog.md MCP |

### PR target adapter (`lib/pr-adapter.sh`)

Opens the final PR. Providers:

| Provider | Status | CLI required |
|---|---|---|
| `github` | ✅ | `gh` |
| `gitlab` | stub | `glab` |
| `bitbucket` | stub | `bb` |

### Parallelization adapter (`lib/parallelization-adapter.sh`)

Decides how a batch of tasks should run. Strategies:

- `adaptive` (default) — trivial batches run sequentially; mixed batches with complex tasks also run sequentially; all-standard batches run in parallel up to `max_concurrency`.
- `always-sequential` — one task at a time, no matter what.
- `always-parallel` — every task goes into a parallel lane, grouped by shared-file dependencies.

Complexity tiers come from `lib/complexity-estimator.sh` which scores tasks by number of acceptance criteria and description length.

---

## Config file

`.autopilot-pipeline.json` in the project root:

```json
{
  "version": 1,
  "prd_source":      { "provider": "local-file" },
  "task_storage":    { "provider": "local-file" },
  "pr_target":       { "provider": "github", "config": { "base_branch": "main" } },
  "parallelization": { "strategy": "adaptive", "max_concurrency": 3 },
  "branch_convention": {
    "project_prefix": "MYAPP",
    "feature_pattern": "feat/{project}-{ticket}-{slug}",
    "fix_pattern":     "fix/{project}-{ticket}-{slug}"
  }
}
```

You can edit this by hand or re-run `/autopilot-configure` to update any stage.

---

## Quality gates (original feature)

When `/autopilot on` is active, the Stop hook runs the four gates after every Claude iteration. Details below.

### Stacks supported

| Stack | Detection | Test | Lint | Types | Build |
|-------|-----------|------|------|-------|-------|
| Node/TypeScript | `tsconfig.json` + `package.json` | `npm test` | `npm run lint` | `npx tsc --noEmit` | `npm run build` |
| Node/JavaScript | `package.json` | `npm test` | `npm run lint` | — | `npm run build` |
| Java/Maven | `pom.xml` | `mvn test -q` | — | — | `mvn package -q -DskipTests` |
| Java/Gradle | `build.gradle` | `./gradlew test` | — | — | `./gradlew build -x test` |
| Python | `pyproject.toml` / `setup.py` | `pytest` | `ruff` / `flake8` | `pyright` / `mypy` | — |
| Rust | `Cargo.toml` | `cargo test` | `cargo clippy` | — | `cargo build` |
| Go | `go.mod` | `go test ./...` | `golangci-lint run` | `go vet ./...` | `go build ./...` |

Unknown stacks pass the gates unchanged.

### Security gates (PreToolUse)

- **Always active:** blocks edits to `.env` files.
- **With autopilot ON:** also blocks credential files (`.pem`, `.key`, `id_rsa`), system directories (`/etc/`, `/usr/local/`), and destructive commands (`rm -rf /`, `git push --force`, `DROP TABLE`, `chmod 777`, `curl | bash`).

### Iteration limit

Up to 5 consecutive failing iterations per session. After the 5th failure the autopilot stops and asks the user for help.

### Task-complete marker

The outer pipeline (`/autopilot-task`) relies on a marker file (`~/.claude/.autopilot-task-complete`) to distinguish "gates passed for the Nth time" from "this task is actually done". The autopilot skill writes the marker only when:

1. Every acceptance criterion is satisfied by code.
2. All four gates pass.
3. The `security-reviewer` subagent returns no blocking findings.

When the Stop hook sees the marker, it emits a "task complete" signal instead of asking for another iteration.

---

## Branch strategy

Every task runs on a fresh branch cut from `main`:

- Feature: `feat/{PROJECT}-{ticket}-{slug}`
- Fix: `fix/{PROJECT}-{ticket}-{slug}`

`{PROJECT}` comes from `branch_convention.project_prefix` (falls back to the repo name). `{ticket}` comes from the task storage provider. `{slug}` is a kebab-case version of the task title, max 40 chars, generated by `lib/branch-utils.sh`.

See `lib/branch-utils.sh` for the exact slug algorithm.

---

## Coexistence with Ralph Loop

When Ralph Loop is active in the same session, the Stop hook defers automatically. Both plugins can run together without conflicts.

---

## Portability

The entire plugin runs in plain POSIX-friendly bash with `jq` + `git` as the only mandatory dependencies. Explicitly supported environments:

- macOS (default `bash` 3.2, BSD coreutils)
- Linux (bash 4+/5, GNU coreutils)
- WSL (Ubuntu, Debian, etc.)
- Git Bash on Windows

Known portability gotchas the plugin avoids:

- No `${var,,}` (bash 4+). Uses `tr '[:upper:]' '[:lower:]'` instead.
- No `declare -A` / associative arrays. Uses integer-indexed arrays.
- No `sed -i ''` vs `sed -i`. Uses `sed -i.bak` + `rm -f *.bak`.
- No `awk -v RS='multi-char'`. Uses bash string manipulation for delimiters.

---

## Testing

Every `lib/` module is covered by `bats-core` tests in `tests/lib/`. Run them with:

```bash
bats tests/lib/
```

107 tests pass on macOS bash 3.2 as of v0.2.0. See `CONTRIBUTING.md` for the TDD workflow.

---

## License

MIT
