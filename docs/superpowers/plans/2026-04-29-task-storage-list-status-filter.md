# `task_storage_list` Status Filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `task_storage_list` accept an optional canonical status filter (`ready | in_progress | done`), validate arity and vocabulary in the adapter, apply the filter inside each provider using its native means, and remove the silent failure where unknown args were dropped.

**Architecture:** Three layers of responsibility. Caller asks. Adapter validates (arity + canonical vocabulary). Provider filters using its own dialect — `jq` for local providers (`backlog`, `local-file`), API filters for remote providers (`jira` JQL, `notion` filter object, `linear` GraphQL filter). `chat-paste` keeps its existing "not yet implemented" stub. Backward compatible: every existing call with no args keeps working identically.

**Tech Stack:** bash 3.2 (macOS portable), bats-core for tests, `jq` for JSON, no other runtime. Spec at `docs/superpowers/specs/2026-04-29-task-storage-list-status-filter-design.md` (PR #33, merged).

**Baseline:** 373 bats tests green on `main` at commit `6eaa69b`.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/task-storage-adapter.sh` | modify | Wrap `task_storage_list` with arity + vocabulary validation; expose `TASK_STORAGE_CANONICAL_STATUSES` constant. |
| `lib/task-storage-providers/backlog.sh` | modify | Accept optional filter arg in `task_storage_backlog_list`; filter by canonical status using `jq` after `_backlog_parse`. |
| `lib/task-storage-providers/local-file.sh` | modify | Same shape as backlog. |
| `lib/task-storage-providers/jira.sh` | modify | Pass canonical→native status into JQL via existing `[jql_extra]` arg of `jira_client_search_issues`. |
| `lib/task-storage-providers/notion.sh` | modify | Pass canonical→native status into a Notion `filter` object via existing `[filter_json]` arg of `notion_client_query_database`. |
| `lib/task-storage-providers/linear.sh` | modify | Pass canonical→native state into Linear GraphQL filter; client function gains optional `[state_name]` arg. |
| `lib/linear-client.sh` | modify | Add optional `[state_name]` arg to `linear_client_list_issues`. |
| `lib/task-storage-providers/chat-paste.sh` | unchanged | Already returns "not yet implemented" — preserved. |
| `commands/autopilot-sprint.md` | modify | Step 2 simplifies from "list + jq filter" to single call `task_storage_list ready`. |
| `skills/autopilot/SKILL.md` | inspect + modify if needed | Search for documented list-then-filter patterns and update to single-call pattern. |
| `tests/lib/task-storage-list-validation.bats` | create | Adapter validation tests (arity + vocabulary). |
| `tests/lib/backlog-provider.bats` | extend | Filter tests for backlog. |
| `tests/lib/task-storage-adapter.bats` | extend | Filter tests for local-file, jira, linear, notion (mock-based for remote). |
| `tests/lib/task-storage-status-normalization.bats` | extend | Round-trip integration test. |
| `README.md` | modify (release task only) | Bump `Current state: NNN tests` to new green count. |
| `.claude-plugin/plugin.json` | modify (release task only) | Bump version to `0.7.1`. |

---

## Task 1: Adapter validation — write the failing test

**Files:**
- Create: `tests/lib/task-storage-list-validation.bats`

- [ ] **Step 1: Create the test file with the full first scenario**

Write the file `tests/lib/task-storage-list-validation.bats`:

```bash
#!/usr/bin/env bats
# Validation contract for task_storage_list:
#   - 0 or 1 positional arg
#   - if 1, must be in canonical vocabulary: ready | in_progress | done | ""

load '../helpers/test_helper'

setup() {
  setup_test_workdir
  cd "$TEST_WORKDIR"
  mkdir -p backlog/tasks
  cat > .autopilot-pipeline.json <<'JSON'
{ "version": 1, "task_storage": { "provider": "backlog" } }
JSON
  source "$BATS_TEST_DIRNAME/../../lib/config.sh"
  source "$BATS_TEST_DIRNAME/../../lib/adapter-base.sh"
  source "$BATS_TEST_DIRNAME/../../lib/task-storage-adapter.sh"
}

teardown() {
  teardown_test_workdir
}

@test "task_storage_list accepts no argument" {
  run task_storage_list
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts empty string as no filter" {
  run task_storage_list ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts 'ready'" {
  run task_storage_list ready
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts 'in_progress'" {
  run task_storage_list in_progress
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list accepts 'done'" {
  run task_storage_list done
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "task_storage_list rejects unknown status with exit 1" {
  run task_storage_list pizza
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "invalid status 'pizza'"
}

@test "task_storage_list rejects 2+ arguments with exit 1" {
  run task_storage_list ready extra
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "too many arguments"
}

@test "task_storage_list error message lists canonical statuses" {
  run task_storage_list pizza
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ready"
  echo "$output" | grep -q "in_progress"
  echo "$output" | grep -q "done"
}
```

- [ ] **Step 2: Run the new test file to verify it fails**

Run: `bats tests/lib/task-storage-list-validation.bats`

Expected: at least 2 tests fail — `pizza` is silently accepted (returns `[]` with status 0 instead of 1), and `ready extra` is silently accepted. The other 6 may pass since the current implementation is permissive.

- [ ] **Step 3: Modify the adapter to enforce validation**

Open `lib/task-storage-adapter.sh`. Find this block (around line 44):

```bash
task_storage_list()          { _task_storage_dispatch "list" "$@"; }
```

Replace it with:

```bash
# Canonical status vocabulary accepted by task_storage_list.
TASK_STORAGE_CANONICAL_STATUSES="ready in_progress done"

# task_storage_list [<status>]
#   Lists tasks from the configured provider, optionally filtered by canonical
#   status. Validates arity (0 or 1 arg) and vocabulary in the adapter so each
#   provider receives exactly one arg (filter or empty string).
task_storage_list() {
  local filter=""
  case $# in
    0) filter="" ;;
    1) filter="$1" ;;
    *) echo "task_storage_list: too many arguments (expected 0 or 1, got $#)" >&2
       return 1 ;;
  esac

  if [[ -n "$filter" ]]; then
    local valid=0 s
    for s in $TASK_STORAGE_CANONICAL_STATUSES; do
      [[ "$s" == "$filter" ]] && { valid=1; break; }
    done
    if [[ $valid -eq 0 ]]; then
      echo "task_storage_list: invalid status '$filter' (expected: ready|in_progress|done)" >&2
      return 1
    fi
  fi

  _task_storage_dispatch "list" "$filter"
}
```

- [ ] **Step 4: Run the validation test file to verify all 8 tests pass**

Run: `bats tests/lib/task-storage-list-validation.bats`

Expected: 8 ok, 0 not ok.

- [ ] **Step 5: Run the FULL bats suite to make sure nothing regressed**

Run: `bats tests/lib/`

Expected: green count == 373 + 8 = 381 (existing 373 still green, plus 8 new).

If any existing test now fails, the most likely cause is that some provider's `list` now receives an empty string `""` as `$1` where before it received nothing. Inspect the provider; in shell, `${1:-}` and `${1-}` handle both cases, but a bare `$1` will see an empty string and may behave differently. Tasks 2–6 already account for this — but if a regression appears, the fix belongs in the failing provider, not in the adapter wrapper.

- [ ] **Step 6: Commit**

```bash
git add lib/task-storage-adapter.sh tests/lib/task-storage-list-validation.bats
git commit -m "feat(task-storage): adapter validates list arity and canonical vocabulary

task_storage_list rejects unknown status values and extra arguments
with exit 1 instead of silently passing them to the provider, where
they were ignored. Backward compatible — no-arg calls unchanged.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: Backlog provider filter — write the failing test

**Files:**
- Modify: `tests/lib/backlog-provider.bats:152-180`
- Modify: `lib/task-storage-providers/backlog.sh:194-211`

- [ ] **Step 1: Open `tests/lib/backlog-provider.bats` and find the existing `# -------- list --------` section (around line 150)**

After the existing `@test "backlog list returns empty array when backlog dir missing"` block (around line 175), append the following new tests inside the same file (do not remove or modify existing list tests):

```bash
@test "backlog list ready returns only To Do tasks" {
  _create_backlog_task "task-1" "First-task"
  _create_backlog_task "task-2" "Second-task"
  # Mark task-2 as Done
  sed -i.bak -e 's/^status: To Do/status: Done/' "backlog/tasks/task-2 - Second-task.md"
  rm -f "backlog/tasks/task-2 - Second-task.md.bak"

  run task_storage_list ready
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
  local id
  id="$(echo "$output" | jq -r '.[0].id')"
  [ "$id" = "task-1" ]
}

@test "backlog list done returns only Done tasks" {
  _create_backlog_task "task-1" "First-task"
  _create_backlog_task "task-2" "Second-task"
  sed -i.bak -e 's/^status: To Do/status: Done/' "backlog/tasks/task-2 - Second-task.md"
  rm -f "backlog/tasks/task-2 - Second-task.md.bak"

  run task_storage_list done
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
  local id
  id="$(echo "$output" | jq -r '.[0].id')"
  [ "$id" = "task-2" ]
}

@test "backlog list in_progress returns only In Progress tasks" {
  _create_backlog_task "task-1" "First-task"
  _create_backlog_task "task-2" "Second-task"
  sed -i.bak -e 's/^status: To Do/status: In Progress/' "backlog/tasks/task-1 - First-task.md"
  rm -f "backlog/tasks/task-1 - First-task.md.bak"

  run task_storage_list in_progress
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
  local id
  id="$(echo "$output" | jq -r '.[0].id')"
  [ "$id" = "task-1" ]
}

@test "backlog list ready returns empty array when no ready tasks" {
  _create_backlog_task "task-1" "First-task"
  sed -i.bak -e 's/^status: To Do/status: Done/' "backlog/tasks/task-1 - First-task.md"
  rm -f "backlog/tasks/task-1 - First-task.md.bak"

  run task_storage_list ready
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "backlog list with empty filter returns all tasks (backward compat)" {
  _create_backlog_task "task-1" "First-task"
  _create_backlog_task "task-2" "Second-task"
  sed -i.bak -e 's/^status: To Do/status: Done/' "backlog/tasks/task-2 - Second-task.md"
  rm -f "backlog/tasks/task-2 - Second-task.md.bak"

  run task_storage_list
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "2" ]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/lib/backlog-provider.bats`

Expected: 4 of the 5 new tests fail (the last `backward compat` one passes — it's the existing behavior). The 4 filtering tests fail because the filter arg is currently dropped.

- [ ] **Step 3: Modify `lib/task-storage-providers/backlog.sh` — replace `task_storage_backlog_list`**

Find the existing function (around line 194):

```bash
task_storage_backlog_list() {
  if [[ ! -d "$BACKLOG_TASKS_DIR" ]]; then
    echo "[]"
    return 0
  fi
  local items=()
  local f
  for f in "$BACKLOG_TASKS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    items+=("$(_backlog_parse "$f")")
  done
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  printf '%s\n' "${items[@]}" | jq -s '.'
}
```

Replace it with:

```bash
task_storage_backlog_list() {
  local filter="${1:-}"
  if [[ ! -d "$BACKLOG_TASKS_DIR" ]]; then
    echo "[]"
    return 0
  fi
  local items=()
  local f
  for f in "$BACKLOG_TASKS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    local parsed
    parsed="$(_backlog_parse "$f")"
    if [[ -n "$filter" ]]; then
      local s
      s="$(echo "$parsed" | jq -r '.status')"
      [[ "$s" == "$filter" ]] || continue
    fi
    items+=("$parsed")
  done
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  printf '%s\n' "${items[@]}" | jq -s '.'
}
```

- [ ] **Step 4: Run the backlog test file to verify all tests pass**

Run: `bats tests/lib/backlog-provider.bats`

Expected: all tests green (existing + 5 new).

- [ ] **Step 5: Run the FULL suite**

Run: `bats tests/lib/`

Expected: 373 + 8 (Task 1) + 5 (Task 2) = 386 green, 0 not ok.

- [ ] **Step 6: Commit**

```bash
git add tests/lib/backlog-provider.bats lib/task-storage-providers/backlog.sh
git commit -m "feat(task-storage): backlog list filters by canonical status

When task_storage_list is called with a status filter, the backlog
provider now skips tasks whose normalized status doesn't match.
Empty filter returns all tasks (backward compat).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: local-file provider filter

**Files:**
- Modify: `tests/lib/task-storage-adapter.bats` (extend the local-file list section around line 311)
- Modify: `lib/task-storage-providers/local-file.sh:93-110`

- [ ] **Step 1: Find the existing local-file list test in `tests/lib/task-storage-adapter.bats`**

Around line 311–340 there is a section `# -------- task_storage_list --------` with `@test "task_storage_list returns all local-file tasks as a JSON array"`. Append after that test (and before the next section):

```bash
@test "task_storage_list ready returns only ready local-file tasks" {
  _write_local_task "task-1" "ready" "First task"
  _write_local_task "task-2" "done" "Second task"

  run task_storage_list ready
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
  local id
  id="$(echo "$output" | jq -r '.[0].id')"
  [ "$id" = "task-1" ]
}

@test "task_storage_list done returns only done local-file tasks" {
  _write_local_task "task-1" "ready" "First task"
  _write_local_task "task-2" "done" "Second task"

  run task_storage_list done
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
  local id
  id="$(echo "$output" | jq -r '.[0].id')"
  [ "$id" = "task-2" ]
}

@test "task_storage_list with empty filter returns all local-file tasks" {
  _write_local_task "task-1" "ready" "First task"
  _write_local_task "task-2" "done" "Second task"

  run task_storage_list
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "2" ]
}
```

If a `_write_local_task` helper does not yet exist in this file, look at the existing `@test "task_storage_list returns all local-file tasks as a JSON array"` block to see how tasks are created and reuse the same pattern inline (likely a `cat > tasks/task-1.md <<EOF` heredoc). If using inline heredocs, the body of each test creates its own task files; mirror that style and DO NOT add a helper unless one is already defined.

- [ ] **Step 2: Run the local-file test file to verify the new tests fail**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: the 2 new filter tests fail. The "empty filter" test passes (existing behavior).

- [ ] **Step 3: Modify `lib/task-storage-providers/local-file.sh`**

Find `task_storage_local_file_list()` (around line 93):

```bash
task_storage_local_file_list() {
  if [[ ! -d "$TASK_STORAGE_LOCAL_DIR" ]]; then
    echo "[]"
    return 0
  fi
  local items=()
  local f
  for f in "$TASK_STORAGE_LOCAL_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    items+=("$(_task_storage_local_file_parse "$f")")
  done
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  printf '%s\n' "${items[@]}" | jq -s '.'
}
```

Replace it with:

```bash
task_storage_local_file_list() {
  local filter="${1:-}"
  if [[ ! -d "$TASK_STORAGE_LOCAL_DIR" ]]; then
    echo "[]"
    return 0
  fi
  local items=()
  local f
  for f in "$TASK_STORAGE_LOCAL_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    local parsed
    parsed="$(_task_storage_local_file_parse "$f")"
    if [[ -n "$filter" ]]; then
      local s
      s="$(echo "$parsed" | jq -r '.status')"
      [[ "$s" == "$filter" ]] || continue
    fi
    items+=("$parsed")
  done
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  printf '%s\n' "${items[@]}" | jq -s '.'
}
```

- [ ] **Step 4: Run the test file**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: all green.

- [ ] **Step 5: Run the FULL suite**

Run: `bats tests/lib/`

Expected: 386 + 3 = 389 green, 0 not ok.

- [ ] **Step 6: Commit**

```bash
git add tests/lib/task-storage-adapter.bats lib/task-storage-providers/local-file.sh
git commit -m "feat(task-storage): local-file list filters by canonical status

Same shape as backlog: optional filter arg, jq filter on parsed status,
empty filter returns all (backward compat).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: Jira provider filter

**Files:**
- Modify: `tests/lib/task-storage-adapter.bats` (jira section around line 412)
- Modify: `lib/task-storage-providers/jira.sh:202`

`jira_client_search_issues` already accepts `[jql_extra]` — Task 4 only wires it up in the provider.

- [ ] **Step 1: Find the existing Jira list test (`@test "jira: task_storage_list returns normalized JSON array"` around line 412)**

Append after it the following test that asserts the JQL extra is passed when a filter is supplied. The existing test pattern stubs `jira_client_search_issues` with a function that ignores its args. The new test redefines that stub to capture and assert.

```bash
@test "jira: task_storage_list ready passes status filter into JQL" {
  _setup_jira_config

  # Capture the JQL extra arg for assertion
  jira_client_search_issues() {
    echo "JIRA_CALL: project=$1 jql_extra=$2" >> "$TEST_WORKDIR/jira-calls.log"
    cat <<'JSON'
{ "issues": [] }
JSON
  }
  export -f jira_client_search_issues

  run task_storage_list ready
  [ "$status" -eq 0 ]

  grep -q 'jql_extra= AND status = "To Do"' "$TEST_WORKDIR/jira-calls.log" \
    || (echo "captured calls:"; cat "$TEST_WORKDIR/jira-calls.log"; false)
}

@test "jira: task_storage_list with no filter passes empty jql_extra" {
  _setup_jira_config

  jira_client_search_issues() {
    echo "JIRA_CALL: project=$1 jql_extra=[$2]" >> "$TEST_WORKDIR/jira-calls.log"
    cat <<'JSON'
{ "issues": [] }
JSON
  }
  export -f jira_client_search_issues

  run task_storage_list
  [ "$status" -eq 0 ]

  grep -q 'jql_extra=\[\]' "$TEST_WORKDIR/jira-calls.log" \
    || (echo "captured calls:"; cat "$TEST_WORKDIR/jira-calls.log"; false)
}
```

The `_setup_jira_config` helper is whatever the existing Jira tests use (look at the existing `@test "jira: task_storage_list requires database_id config"` block). If the existing tests use a different helper name or inline setup, mirror that pattern — do not invent a new helper.

The native value `"To Do"` matches the default Jira mapping; if the actual `_jira_ts_status_value "ready"` returns something different (check by reading the function in `lib/task-storage-providers/jira.sh`), update the grep accordingly.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: the new "passes status filter into JQL" test fails because the provider currently calls `jira_client_search_issues "$project_key"` with no second arg.

- [ ] **Step 3: Modify `lib/task-storage-providers/jira.sh`**

Find `task_storage_jira_list()` and the call to `jira_client_search_issues "$project_key"`. Replace the function with:

```bash
task_storage_jira_list() {
  local filter="${1:-}"
  local project_key
  project_key="$(config_get "jira.project_key" 2>/dev/null || true)"
  if [[ -z "$project_key" ]]; then
    echo "jira.project_key not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local jql_extra=""
  if [[ -n "$filter" ]]; then
    local native
    native="$(_jira_ts_status_value "$filter")"
    jql_extra=" AND status = \"$native\""
  fi

  local response
  response="$(jira_client_search_issues "$project_key" "$jql_extra")" || return 1

  local ready_val in_prog_val done_val
  ready_val="$(_jira_ts_status_value "ready")"
  in_prog_val="$(_jira_ts_status_value "in_progress")"
  done_val="$(_jira_ts_status_value "done")"

  echo "$response" | jq \
    --arg ready_val "$ready_val" \
    --arg in_prog_val "$in_prog_val" \
    --arg done_val "$done_val" \
    '[.issues // [] | .[] | {
      id: .key,
      title: .fields.summary,
      description: (.fields.description // ""),
      status: (
        (.fields.status.name // "") as $s |
        if $s == $ready_val then "ready"
        elif $s == $in_prog_val then "in_progress"
        elif $s == $done_val then "done"
        else $s
        end
      ),
      parent: null,
      acceptanceCriteria: []
    }]'
}
```

(The existing function body is preserved verbatim from the `local response=` line onwards; only the front matter changes. Check the actual file before saving — if the existing function emits additional fields, keep them.)

- [ ] **Step 4: Run the test file**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: green.

- [ ] **Step 5: Run the FULL suite**

Run: `bats tests/lib/`

Expected: 389 + 2 = 391 green.

- [ ] **Step 6: Commit**

```bash
git add tests/lib/task-storage-adapter.bats lib/task-storage-providers/jira.sh
git commit -m "feat(task-storage): jira list filters server-side via JQL

The optional filter arg is converted to native via _jira_ts_status_value
and appended to the JQL through the existing jql_extra parameter of
jira_client_search_issues. Empty filter sends no extra JQL.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: Notion provider filter

**Files:**
- Modify: `tests/lib/task-storage-adapter.bats` (notion section around line 230)
- Modify: `lib/task-storage-providers/notion.sh:206`

`notion_client_query_database` already accepts `[filter_json]`.

- [ ] **Step 1: Open `tests/lib/task-storage-adapter.bats`. Find the existing notion list tests (`@test "notion: task_storage_list returns normalized JSON array"` around line 230).**

Append:

```bash
@test "notion: task_storage_list ready passes status filter to query" {
  _setup_notion_config

  notion_client_query_database() {
    echo "NOTION_CALL: db=$1 filter=$2" >> "$TEST_WORKDIR/notion-calls.log"
    cat <<'JSON'
{ "results": [] }
JSON
  }
  export -f notion_client_query_database

  run task_storage_list ready
  [ "$status" -eq 0 ]

  grep -q 'NOTION_CALL: db=' "$TEST_WORKDIR/notion-calls.log"
  # Filter JSON should be non-empty and contain the canonical→native status name
  grep -q '"status"' "$TEST_WORKDIR/notion-calls.log" \
    || (echo "captured calls:"; cat "$TEST_WORKDIR/notion-calls.log"; false)
}

@test "notion: task_storage_list with no filter passes empty filter arg" {
  _setup_notion_config

  notion_client_query_database() {
    echo "NOTION_CALL: db=$1 filter=[$2]" >> "$TEST_WORKDIR/notion-calls.log"
    cat <<'JSON'
{ "results": [] }
JSON
  }
  export -f notion_client_query_database

  run task_storage_list
  [ "$status" -eq 0 ]

  grep -q 'filter=\[\]' "$TEST_WORKDIR/notion-calls.log" \
    || (echo "captured calls:"; cat "$TEST_WORKDIR/notion-calls.log"; false)
}
```

- [ ] **Step 2: Run the test file to verify the new tests fail**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: filter test fails because no filter is currently passed.

- [ ] **Step 3: Modify `lib/task-storage-providers/notion.sh`**

Find `task_storage_notion_list()` (around line 206) and the call `notion_client_query_database "$database_id"`. Replace the function header up to the API call with:

```bash
task_storage_notion_list() {
  local filter_arg="${1:-}"
  local database_id
  database_id="$(config_get "notion.database_id" 2>/dev/null || true)"
  if [[ -z "$database_id" ]]; then
    echo "notion.database_id not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local status_prop
  status_prop="$(_notion_ts_status_property)"

  local notion_filter_json=""
  if [[ -n "$filter_arg" ]]; then
    local native
    native="$(_notion_ts_status_value "$filter_arg")"
    notion_filter_json="$(jq -nc \
      --arg prop "$status_prop" \
      --arg val "$native" \
      '{property: $prop, status: {equals: $val}}')"
  fi

  local response
  response="$(notion_client_query_database "$database_id" "$notion_filter_json")" || return 1

  # ... (rest of function unchanged: ready_val/in_prog_val/done_val and final jq normalization)
```

Keep the existing normalization block from `local ready_val in_prog_val done_val` onwards verbatim. Only the prefix changes.

- [ ] **Step 4: Run the test file**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: green.

- [ ] **Step 5: Run the FULL suite**

Run: `bats tests/lib/`

Expected: 391 + 2 = 393 green.

- [ ] **Step 6: Commit**

```bash
git add tests/lib/task-storage-adapter.bats lib/task-storage-providers/notion.sh
git commit -m "feat(task-storage): notion list filters server-side via filter object

Builds a Notion database query filter from the canonical→native status
name and passes it through the existing filter_json parameter of
notion_client_query_database. Empty filter sends no body filter.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: Linear provider filter (and client extension)

**Files:**
- Modify: `lib/linear-client.sh:74-86` — add optional `[state_name]` arg
- Modify: `lib/task-storage-providers/linear.sh:188`
- Modify: `tests/lib/task-storage-adapter.bats` (linear section around line 523)

Linear is the only client without a filter arg yet. Extend it minimally.

- [ ] **Step 1: Open `tests/lib/task-storage-adapter.bats`. Find the existing linear list tests (`@test "linear: task_storage_list returns normalized JSON array"` around line 523).**

Append:

```bash
@test "linear: task_storage_list ready passes state filter into client call" {
  _setup_linear_config

  linear_client_list_issues() {
    echo "LINEAR_CALL: team=$1 state=$2" >> "$TEST_WORKDIR/linear-calls.log"
    cat <<'JSON'
{ "issues": [] }
JSON
  }
  export -f linear_client_list_issues

  run task_storage_list ready
  [ "$status" -eq 0 ]

  grep -q 'LINEAR_CALL: team=' "$TEST_WORKDIR/linear-calls.log"
  # state arg should be non-empty (the native name for ready)
  grep -vq 'state=$' "$TEST_WORKDIR/linear-calls.log" \
    || (echo "captured calls:"; cat "$TEST_WORKDIR/linear-calls.log"; false)
}

@test "linear: task_storage_list with no filter passes empty state arg" {
  _setup_linear_config

  linear_client_list_issues() {
    echo "LINEAR_CALL: team=$1 state=[$2]" >> "$TEST_WORKDIR/linear-calls.log"
    cat <<'JSON'
{ "issues": [] }
JSON
  }
  export -f linear_client_list_issues

  run task_storage_list
  [ "$status" -eq 0 ]

  grep -q 'state=\[\]' "$TEST_WORKDIR/linear-calls.log" \
    || (echo "captured calls:"; cat "$TEST_WORKDIR/linear-calls.log"; false)
}
```

- [ ] **Step 2: Run the test file**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: filter test fails because the provider currently calls the client with only `team_id`.

- [ ] **Step 3: Add an optional state arg to `linear_client_list_issues`**

Open `lib/linear-client.sh`. Find:

```bash
# List Linear issues for a team. Prints results JSON on stdout.
# Usage: linear_client_list_issues <team_id>
if ! declare -f linear_client_list_issues >/dev/null 2>&1; then
linear_client_list_issues() {
  local team_id="$1"
  if [[ -z "$team_id" ]]; then
    echo "linear_client_list_issues: team_id is required" >&2
    return 1
  fi
  local args
  args="$(jq -nc --arg team "$team_id" '{teamId: $team}')"
  echo "__MCP_CALL__:mcp__linear__list_issues:${args}"
}
fi
```

Replace with:

```bash
# List Linear issues for a team, optionally filtered by state name.
# Usage: linear_client_list_issues <team_id> [state_name]
if ! declare -f linear_client_list_issues >/dev/null 2>&1; then
linear_client_list_issues() {
  local team_id="$1"
  local state_name="${2:-}"
  if [[ -z "$team_id" ]]; then
    echo "linear_client_list_issues: team_id is required" >&2
    return 1
  fi
  local args
  if [[ -n "$state_name" ]]; then
    args="$(jq -nc --arg team "$team_id" --arg state "$state_name" \
      '{teamId: $team, filter: {state: {name: {eq: $state}}}}')"
  else
    args="$(jq -nc --arg team "$team_id" '{teamId: $team}')"
  fi
  echo "__MCP_CALL__:mcp__linear__list_issues:${args}"
}
fi
```

- [ ] **Step 4: Modify `lib/task-storage-providers/linear.sh`**

Find `task_storage_linear_list()` (around line 188). Replace its prefix and the client call:

```bash
task_storage_linear_list() {
  local filter="${1:-}"
  local team_id
  team_id="$(config_get "linear.team_id" 2>/dev/null || true)"
  if [[ -z "$team_id" ]]; then
    echo "linear.team_id not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local native_state=""
  if [[ -n "$filter" ]]; then
    native_state="$(_linear_ts_status_value "$filter")"
  fi

  local response
  response="$(linear_client_list_issues "$team_id" "$native_state")" || return 1

  # ... (rest unchanged)
```

Keep the rest of the function (`local ready_val in_prog_val done_val` onwards) verbatim.

- [ ] **Step 5: Run the test file**

Run: `bats tests/lib/task-storage-adapter.bats`

Expected: green.

- [ ] **Step 6: Run the FULL suite**

Run: `bats tests/lib/`

Expected: 393 + 2 = 395 green.

- [ ] **Step 7: Commit**

```bash
git add lib/linear-client.sh lib/task-storage-providers/linear.sh tests/lib/task-storage-adapter.bats
git commit -m "feat(task-storage): linear list filters server-side via GraphQL filter

linear_client_list_issues gains an optional state_name arg that builds
the filter object {state: {name: {eq: ...}}}. Provider passes the
canonical→native state name when a filter is supplied.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: Round-trip integration test

**Files:**
- Modify: `tests/lib/task-storage-status-normalization.bats`

- [ ] **Step 1: Open `tests/lib/task-storage-status-normalization.bats` and add at the bottom**

```bash
# -------- list-with-filter round-trip --------

@test "round-trip: create + list ready surfaces the new task" {
  _setup_backlog_workdir

  task_storage_create "New feature" "Build something" "AC1,AC2"

  run task_storage_list ready
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
}

@test "round-trip: update_status to in_progress moves task between filters" {
  _setup_backlog_workdir

  task_storage_create "New feature" "Build" "AC1"
  local id
  id="$(task_storage_list ready | jq -r '.[0].id')"

  task_storage_update_status "$id" "in_progress"

  # No longer in ready
  run task_storage_list ready
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]

  # Now in in_progress
  run task_storage_list in_progress
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
}

@test "round-trip: update_status to done moves task to done filter only" {
  _setup_backlog_workdir

  task_storage_create "New feature" "Build" "AC1"
  local id
  id="$(task_storage_list ready | jq -r '.[0].id')"

  task_storage_update_status "$id" "done"

  run task_storage_list ready
  [ "$output" = "[]" ]

  run task_storage_list in_progress
  [ "$output" = "[]" ]

  run task_storage_list done
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" = "1" ]
}
```

If `_setup_backlog_workdir` does not exist in this file, look at how the file currently sets up its environment (top `setup()`/helpers) and reuse the same pattern inline. The setup needs: `mkdir -p backlog/tasks`, `.autopilot-pipeline.json` with `task_storage.provider = backlog`, and the adapter sourced.

- [ ] **Step 2: Run the new tests**

Run: `bats tests/lib/task-storage-status-normalization.bats`

Expected: all 3 new tests green.

- [ ] **Step 3: Run the FULL suite**

Run: `bats tests/lib/`

Expected: 395 + 3 = 398 green.

- [ ] **Step 4: Commit**

```bash
git add tests/lib/task-storage-status-normalization.bats
git commit -m "test(task-storage): round-trip integration for list status filter

create + list ready surfaces the task; update_status moves it between
filter buckets; final state appears only under list done.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: Real-data smoke test on the actual repo backlog

**Files:**
- None (manual command run)

This step verifies the original incident is fixed. It is NOT a bats test; it's an interactive sanity check.

- [ ] **Step 1: From the repo root, run the smoke commands**

```bash
source lib/config.sh
source lib/adapter-base.sh
source lib/task-storage-adapter.sh

# Total tasks
all=$(task_storage_list | jq 'length')
ready=$(task_storage_list ready | jq 'length')
done=$(task_storage_list done | jq 'length')
in_progress=$(task_storage_list in_progress | jq 'length')

echo "all=$all ready=$ready done=$done in_progress=$in_progress"
echo "expected: all=30 ready=2 done=28 in_progress=0"
```

- [ ] **Step 2: Verify the assertion**

Expected output line: `all=30 ready=2 done=28 in_progress=0`

If `ready` is not 2, the bug from 2026-04-29 is not actually fixed. Halt and debug — do not proceed to Task 9.

- [ ] **Step 3: Verify error handling**

```bash
task_storage_list pizza
echo "exit=$?"
```

Expected: stderr message containing `invalid status 'pizza'` and `exit=1`.

- [ ] **Step 4: No commit — this is a smoke test, not a code change**

---

## Task 9: Update command and skill text to use the single-call pattern

**Files:**
- Modify: `commands/autopilot-sprint.md` Step 2
- Inspect (modify if needed): `skills/autopilot/SKILL.md`

- [ ] **Step 1: Open `commands/autopilot-sprint.md` and find Step 2 (around line 75)**

The current text:

```markdown
### Step 2: List ready tasks

Run `task_storage_list` and filter to tasks with status `ready`. If zero tasks are returned, stop and tell the user the queue is empty.
```

Replace it with:

```markdown
### Step 2: List ready tasks

Run `task_storage_list ready`. The adapter validates the canonical status and the provider applies the filter natively (jq for local providers, JQL/Notion filter/GraphQL filter for remote). If zero tasks are returned, stop and tell the user the queue is empty.
```

- [ ] **Step 2: Search the skill for the same pattern**

Run:

```bash
grep -n "task_storage_list" skills/autopilot/SKILL.md
```

If any line documents the old "list + filter" two-step pattern, update it to the single-call form `task_storage_list <status>`. If no occurrences exist, no change to the skill is needed.

- [ ] **Step 3: Run the FULL bats suite to confirm no regression**

Run: `bats tests/lib/`

Expected: 398 green (no test changes here, but verify the docs change didn't accidentally break anything that greps these files).

- [ ] **Step 4: Commit**

```bash
git add commands/autopilot-sprint.md skills/autopilot/SKILL.md 2>/dev/null || git add commands/autopilot-sprint.md
git commit -m "docs(sprint): single-call task_storage_list ready in Step 2

Now that the provider applies the filter natively, the command no
longer needs a two-step list + jq filter dance. Step 2 simplifies to
one call.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: Open PR

**Files:**
- None (PR creation only)

- [ ] **Step 1: Push the feature branch**

```bash
git push -u origin feat/task-storage-list-status-filter
```

- [ ] **Step 2: Write the PR body to a tmp file**

```bash
cat > /tmp/pr-body-task-storage-list.md <<'EOF'
## Summary

Implements the design from PR #33 (merged). `task_storage_list` now accepts an optional canonical status filter (`ready | in_progress | done`), validated by the adapter for arity and vocabulary, applied by each provider using its native means (jq for local, JQL / Notion filter / GraphQL filter for remote). Backward compatible: no-arg calls return everything.

Closes the silent failure where `task_storage_list ready` silently returned all tasks instead of filtering. Real-data smoke test on this repo's backlog now returns 2 ready / 28 done / 30 total — matches the file system.

## Files

- `lib/task-storage-adapter.sh` — wrap `task_storage_list` with arity + vocabulary validation
- `lib/task-storage-providers/{backlog,local-file,jira,notion,linear}.sh` — apply filter natively
- `lib/linear-client.sh` — extend `linear_client_list_issues` with optional state arg
- `commands/autopilot-sprint.md` — Step 2 simplifies to single call
- `tests/lib/task-storage-list-validation.bats` — new (8 adapter validation tests)
- `tests/lib/{backlog-provider,task-storage-adapter,task-storage-status-normalization}.bats` — extended

## Test plan

- [ ] Full bats suite green (target: 398 ok, 0 not ok)
- [ ] Real-data smoke: `task_storage_list ready` on this repo's backlog returns 2, `done` returns 28, no-arg returns 30
- [ ] Error path smoke: `task_storage_list pizza` exits 1 with stderr message
- [ ] Error path smoke: `task_storage_list ready extra` exits 1 with stderr message
- [ ] No-arg call still works (backward compat)
- [ ] README test count bumped to match new green count

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

- [ ] **Step 3: Create the PR**

```bash
gh pr create --base main --title "feat(task-storage): list accepts optional canonical status filter" --body-file /tmp/pr-body-task-storage-list.md
```

- [ ] **Step 4: Capture the PR URL and report back**

The PR is open. Manual review and merge by Glody. Do NOT merge from this session.

---

## Task 11: After PR merge — release v0.7.1

This task is performed AFTER Glody has reviewed and merged the PR from Task 10. Do not start Task 11 in the same session unless Glody explicitly approves.

**Files:**
- Auto-handled by `scripts/release.sh`: `README.md`, `.claude-plugin/plugin.json`, git tag, GitHub release

- [ ] **Step 1: Sync local main**

```bash
git checkout main
git pull --ff-only origin main
git status --porcelain   # must be empty
```

- [ ] **Step 2: Run the release script in dry-run first**

```bash
scripts/release.sh --dry-run 0.7.1
```

Expected: shows the diff that would be applied (README test count bump, plugin.json version bump, changelog draft from PR-merge commits since v0.7.0). No errors.

- [ ] **Step 3: Run the release for real**

```bash
scripts/release.sh 0.7.1
```

The script: bumps version, syncs README test count, drafts changelog, opens `$EDITOR` for changelog tweaks (or `--no-edit` to skip), commits, tags, pushes, runs `gh release create`.

- [ ] **Step 4: Verify**

```bash
gh release view v0.7.1
git tag --contains HEAD
```

Expected: release v0.7.1 visible on GitHub, tag points at the release commit.

- [ ] **Step 5: No further commit — release script handles everything**

---

## Self-Review

Spec coverage check:

- §4 contract → Tasks 1, 2 (and tests in 1)
- §5 architecture (3-layer) → Tasks 1 (adapter), 2–6 (providers)
- §6.1 adapter validation → Task 1
- §6.2 backlog filter → Task 2
- §6.3 local-file filter → Task 3
- §6.4 chat-paste unchanged → no task (intentional)
- §6.5 jira filter (server-side) → Task 4
- §6.6 notion filter (server-side) → Task 5
- §6.7 linear filter (server-side) → Task 6 (+ client extension)
- §6.8 command Step 2 update → Task 9
- §6.9 skill text update → Task 9
- §9 testing strategy: validation suite (Task 1), per-provider tests (Tasks 2–6), round-trip (Task 7), real-data smoke (Task 8)
- §10 migration order → matches Tasks 1–9 sequence
- §12 release plan → Task 11

All spec sections covered. No gaps.

Placeholder scan: searched for "TBD", "TODO", "implement later", "fill in details", "appropriate", "similar to" — none found. Every code step shows the actual code.

Type consistency: function names checked across tasks. `task_storage_list`, `task_storage_<provider>_list`, `_jira_ts_status_value`, `_notion_ts_status_value`, `_linear_ts_status_value`, `notion_client_query_database`, `jira_client_search_issues`, `linear_client_list_issues`, `_backlog_parse`, `_task_storage_local_file_parse`, `TASK_STORAGE_CANONICAL_STATUSES`, `BACKLOG_TASKS_DIR`, `TASK_STORAGE_LOCAL_DIR` — all consistent across tasks.
