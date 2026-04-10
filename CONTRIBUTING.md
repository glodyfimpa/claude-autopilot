# Contributing to claude-autopilot

Thanks for wanting to improve the autopilot. This file describes the TDD workflow, portability constraints, and how to add a new provider.

## Prerequisites

- `bash` 3.2+ (the plugin must run on stock macOS bash)
- `jq` 1.6+
- `git` 2.20+
- `bats-core` 1.10+ for running the test suite (`brew install bats-core` on macOS, `apt-get install bats` on Debian)

## TDD workflow

Every `lib/` module is built test-first. When you touch or add one:

1. Write a failing test in `tests/lib/<module>.bats`. Use the helpers in `tests/helpers/test_helper.bash`:
   - `setup_isolated_tmpdir` — gives the test a clean working directory
   - `teardown_isolated_tmpdir` — cleans up after the test
   - `make_fake_git_repo <remote_url>` — initializes a scratch repo with a given remote
   - `assert_equal`, `assert_contains`, `assert_file_exists`
2. Run the test and confirm it fails for the right reason (RED):
   ```bash
   bats tests/lib/<module>.bats
   ```
3. Write the minimum implementation in `lib/<module>.sh` that makes the test pass (GREEN).
4. Refactor keeping the tests green.
5. Run the full suite before committing:
   ```bash
   bats tests/lib/
   ```

Do not add features to a module without adding a test first, and do not merge a change that leaves the suite red.

## Portability constraints

The plugin must run on:

- macOS (bash 3.2, BSD coreutils)
- Linux (bash 4+/5, GNU coreutils)
- WSL and Git Bash on Windows

That excludes a few common bash idioms. Use the alternatives listed below.

| Avoid | Use instead | Why |
|---|---|---|
| `${var,,}` / `${var^^}` | `printf '%s' "$var" \| tr '[:upper:]' '[:lower:]'` | bash 4+ only |
| `declare -A buckets=()` | Integer-indexed regular arrays or bash loops | bash 4+ only |
| `sed -i '' 's/x/y/' f` (BSD) or `sed -i 's/x/y/' f` (GNU) | `sed -i.bak 's/x/y/' f && rm -f f.bak` | Works on both BSD and GNU |
| `awk -v RS='\|\|\|'` | `while [[ "$s" == *"\|\|\|"* ]]; do ...; done` | BSD awk only supports single-char RS |
| `readlink -f` | `cd "$(dirname "$f")" && pwd` | `-f` is GNU-only |
| `date --iso-8601` | `date -u '+%Y-%m-%dT%H:%M:%SZ'` | `--iso-8601` is GNU-only |
| `mapfile` / `readarray` | `while IFS= read -r line; do ...; done < file` | bash 4+ only |

When in doubt, test on macOS bash 3.2 first.

## How to add a new provider

Every adapter lives in `lib/<layer>-adapter.sh` and delegates to `lib/<layer>-providers/<name>.sh`. The dispatch is purely by function name convention.

### 1. Choose the layer

- `lib/prd-source-providers/` for PRD inputs
- `lib/task-storage-providers/` for task CRUD
- `lib/pr-providers/` for pull request creation

### 2. Add the provider file

Create `lib/<layer>-providers/<name>.sh`. Each function the adapter dispatches must be named `<layer>_<name_with_underscores>_<action>`. For example, a `github` PR provider exposes `pr_provider_github_create`, and a `local-file` task storage provider exposes `task_storage_local_file_fetch`.

Hyphenated provider names are converted to underscores (`local-file` → `local_file`) by the adapter's `_fn_token` helper. Keep provider files self-contained: they can assume `jq` and `git` are available, and they should return exit 1 on "real" errors and exit 2 on "not implemented / stub" states.

### 3. Register the provider in the adapter's known list

Each adapter has a constant at the top of the file:

```bash
PR_ADAPTER_KNOWN_PROVIDERS="github gitlab bitbucket"
```

Add your provider name there so `validate_provider` accepts it and the wizard offers it as an option.

### 4. Write tests

Add a new `@test` block in the corresponding `tests/lib/<layer>-adapter.bats` covering at least:

- Happy path (returns valid JSON with the expected fields)
- Missing ref / invalid input
- Stub exit code 2 if the provider is intentionally a placeholder

### 5. Update the wizard suggestions if needed

`lib/mcp-detector.sh` has `suggest_<layer>_provider` functions that pick a default based on detected MCPs. If your provider depends on a specific MCP, extend the suggestion logic there.

### 6. Run the full suite

```bash
bats tests/lib/
```

All tests must stay green before you open a PR.

## Branch and commit conventions

The project follows the same Echofold branch strategy it implements:

- Always branch from `main`
- `feat/{PROJECT}-{ticket}-{slug}` for features
- `fix/{PROJECT}-{ticket}-{slug}` for bugfixes
- One PR per logical change; don't bundle unrelated work

Use Conventional Commits for messages:

```
feat(prd-source): add google-drive provider

Fetches a Google Doc via the google_drive MCP and returns a normalized
PRD JSON. Tests cover the happy path and the missing-doc error case.
```

## Questions

Open an issue or start a discussion on the repo.
