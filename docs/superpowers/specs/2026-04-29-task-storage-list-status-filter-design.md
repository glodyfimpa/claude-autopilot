# Design — `task_storage_list` status filter

**Date:** 2026-04-29
**Author:** Glody Fimpa (driver) + Claude (pair)
**Status:** Approved — ready for implementation plan
**Touches:** `lib/task-storage-adapter.sh`, `lib/task-storage-providers/*.sh`, `commands/autopilot-sprint.md`, `tests/lib/`

---

## 1. Problem

`task_storage_list` accepts an argument, forwards it to the provider, and the provider silently ignores it. Calling `task_storage_list ready` on a backlog with mixed-status tasks returns the entire set instead of the ready subset. The caller cannot distinguish "I asked for ready and got 30" from "there are 30 ready tasks".

Two failure modes converge:

- **Adapter pass-through.** `task_storage_list` blindly forwards args via `_task_storage_dispatch`. No validation of arity, no validation of vocabulary.
- **Provider list functions ignore args.** Six providers (`backlog`, `local-file`, `chat-paste`, `jira`, `linear`, `notion`) read no positional parameters in their `list` function. Whatever the caller passes is dropped on the floor.

The current command file (`commands/autopilot-sprint.md` Step 2) tells the caller to "run `task_storage_list` and filter to status ready". That instruction implicitly relies on the caller doing two operations: list + jq filter. If the caller compresses them into `task_storage_list ready` (a natural mistake), the filter never happens. Verified incident: 2026-04-29 sprint started with 30 tasks fed to the planner instead of the 2 actual ready tasks.

The instruction itself is also weaker than it should be: the same vocabulary (`ready | in_progress | done`) lives in the adapter's normalize/denormalize helpers, but `list` does not use it. The vocabulary boundary is leaky.

## 2. Goals

1. **No silent failure on arguments.** Every argument passed to `task_storage_list` must produce a visible, deterministic effect: applied filter, or explicit error.
2. **Single source of truth for status vocabulary.** Only canonical status values (`ready | in_progress | done`) flow through the public API. Native vocabulary (e.g. `"To Do"`, `"In Review"`) stays inside the provider.
3. **Backward compatibility.** Every existing call site `task_storage_list` (no argument) keeps working identically. No breaking change for consumers that don't filter.
4. **Server-side filtering for remote providers.** Jira/Notion/Linear must filter at the API layer, not download everything and filter locally. Local providers (backlog/local-file/chat-paste) filter in-process.
5. **Spaghetti-free.** No per-provider `if/else` ladders sprinkled at call sites. The filter belongs in the provider, the validation belongs in the adapter, the consumer just asks.

## 3. Non-goals

- Filter on fields other than status (priority, assignee, labels). Out of scope. The current operational need is status only.
- Multiple statuses in one call (e.g. `list ready,in_progress`). Out of scope. Single status keeps the API simple; the caller can always do two calls + jq union if ever needed.
- Pagination or limits. Existing `list` returns all matches. This design preserves that.
- Refactoring `update_status`, `fetch`, `create`. Those already use the canonical vocabulary. No change.

## 4. Contract

### Public signature

```
task_storage_list [<status>]
```

| Input | Behavior |
|---|---|
| `task_storage_list` | no filter — returns all tasks |
| `task_storage_list ""` | empty filter — returns all tasks (treated identical to no arg) |
| `task_storage_list ready` | returns only tasks with canonical status `ready` |
| `task_storage_list in_progress` | returns only tasks with canonical status `in_progress` |
| `task_storage_list done` | returns only tasks with canonical status `done` |
| `task_storage_list <other>` | exit 1, error to stderr: `invalid status '<other>' (expected: ready\|in_progress\|done)` |
| `task_storage_list ready extra` | exit 1, error to stderr: `too many arguments (expected 0 or 1, got 2)` |

### Output

- stdout: a JSON array, always valid JSON, possibly empty (`[]`)
- Each element carries the canonical status (the adapter normalizes via `normalize_status_value` if the provider hasn't already done so)
- stderr: empty on success, error message on failure

### Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | input error (invalid status, too many args, missing config) |
| `2` | provider does not implement `list` (e.g. chat-paste) — preserved from existing dispatcher contract |

## 5. Architecture

### Layer responsibilities

```
                       ┌─────────────────────────────────────┐
                       │ /autopilot-sprint, /autopilot-task, │
                       │ skills, future commands             │
                       │                                     │
caller layer:          │ task_storage_list ready             │
                       └────────────┬────────────────────────┘
                                    │
                                    ▼
                       ┌─────────────────────────────────────┐
                       │ task_storage_list (adapter wrapper) │
                       │                                     │
adapter layer:         │ - validates arity (0 or 1 arg)      │
(generic, vocabulary)  │ - validates canonical status        │
                       │ - dispatches to provider with one   │
                       │   arg always: filter or ""          │
                       └────────────┬────────────────────────┘
                                    │
                                    ▼
                       ┌─────────────────────────────────────┐
                       │ task_storage_<provider>_list        │
                       │                                     │
provider layer:        │ - takes exactly 1 arg (filter or "")│
(provider-specific)    │ - empty arg → returns everything    │
                       │ - non-empty arg → filters using     │
                       │   provider-native means             │
                       │   (jq for local, API for remote)    │
                       │ - normalizes status to canonical    │
                       │   in the output                     │
                       └─────────────────────────────────────┘
```

### Why split adapter vs provider this way

- **Vocabulary validation is global.** If we ever change the canonical set (e.g. add `blocked`), we touch one file. Doing validation in each provider would mean six edits and a high probability of drift.
- **Filtering is local.** Backlog filters by parsing YAML; Jira filters by adding a JQL clause; Notion filters by adding a `filter` object to the database query. Each provider knows how to do this efficiently in its own dialect. Centralizing it would force everyone to download all tasks and filter in shell, defeating the purpose of remote APIs.
- **Arity validation upstream simplifies providers.** Providers can rely on receiving exactly 1 arg. Their internal logic stays trivial: `if [[ -z "$1" ]] return all; else filter`.

## 6. Component changes

### 6.1 `lib/task-storage-adapter.sh`

Replace the current `task_storage_list() { _task_storage_dispatch "list" "$@"; }` one-liner with a wrapper that does validation:

```bash
TASK_STORAGE_CANONICAL_STATUSES="ready in_progress done"

task_storage_list() {
  local filter=""
  case $# in
    0) filter="" ;;
    1) filter="$1" ;;
    *) echo "task_storage_list: too many arguments (expected 0 or 1, got $#)" >&2
       return 1 ;;
  esac

  if [[ -n "$filter" ]]; then
    local valid=0
    local s
    for s in $TASK_STORAGE_CANONICAL_STATUSES; do
      [[ "$s" == "$filter" ]] && { valid=1; break; }
    done
    if [[ $valid -eq 0 ]]; then
      echo "task_storage_list: invalid status '$filter' (expected: ready|in_progress|done)" >&2
      return 1
    fi
  fi

  _task_storage_dispatch list "$filter"
}
```

Constants live next to the existing canonical-vocabulary documentation (top of file). No other adapter helper changes.

### 6.2 `lib/task-storage-providers/backlog.sh`

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

The `_backlog_parse` helper already normalizes status via `_backlog_status_to_normalized` — no extra normalization needed here.

### 6.3 `lib/task-storage-providers/local-file.sh`

Same shape as backlog: parse → check `.status` against filter via jq → keep or skip.

### 6.4 `lib/task-storage-providers/chat-paste.sh`

`chat-paste` does not implement `list` today (returns "not yet implemented"). No change. Status quo preserved.

### 6.5 `lib/task-storage-providers/jira.sh`

Modify `task_storage_jira_list` to accept the filter and pass it into the JQL:

```bash
task_storage_jira_list() {
  local filter="${1:-}"
  local project_key
  project_key="$(config_get "jira.project_key" 2>/dev/null || true)"
  [[ -z "$project_key" ]] && {
    echo "jira.project_key not configured. Run /autopilot-configure first." >&2
    return 1
  }

  local jql_extra=""
  if [[ -n "$filter" ]]; then
    local native
    native="$(_jira_ts_status_value "$filter")"
    jql_extra=" AND status = \"$native\""
  fi

  local response
  response="$(jira_client_search_issues "$project_key" "$jql_extra")" || return 1

  # ... existing normalization (unchanged)
}
```

`jira_client_search_issues` gains an optional second argument `extra_jql` appended to the base JQL. Tests cover both shapes.

### 6.6 `lib/task-storage-providers/notion.sh`

Notion's database query accepts a `filter` object in the body. Convert canonical status to native via `_notion_ts_status_value`, then pass a `filter` object to `notion_client_query_database`. Function gains the same `(filter)` arg shape.

### 6.7 `lib/task-storage-providers/linear.sh`

Linear's GraphQL query accepts `filter: { state: { name: { eq: $state } } }`. Same shape: optional filter arg, build the GraphQL filter object when provided.

### 6.8 `commands/autopilot-sprint.md`

Step 2 simplifies from:

> Run `task_storage_list` and filter to tasks with status `ready`. If zero tasks are returned, stop and tell the user the queue is empty.

to:

> Run `task_storage_list ready`. If zero tasks are returned, stop and tell the user the queue is empty.

No more "list + filter" two-step. The skill that consumes this command just makes one call.

### 6.9 Skill `skills/autopilot/SKILL.md`

Search for any code snippet that documents the list-then-filter pattern and update it to the single-call pattern. (Investigation will confirm exact locations during implementation.)

## 7. Data flow — happy paths

### Backlog with 2 ready, 28 done

```
caller: task_storage_list ready
  └─> adapter: validate "ready" ∈ canonical → OK
       └─> dispatch: task_storage_backlog_list "ready"
            └─> for each *.md: parse → status from frontmatter
                 → "Done" normalized to "done", filter wants "ready" → skip
                 → "To Do" normalized to "ready", filter wants "ready" → keep
            └─> 2 elements
       <─ JSON array of 2
  <─ JSON array of 2
caller proceeds with 2 tasks
```

### Jira project with 5000 issues, 3 in "To Do"

```
caller: task_storage_list ready
  └─> adapter: validate → OK
       └─> dispatch: task_storage_jira_list "ready"
            └─> _jira_ts_status_value "ready" → "To Do" (or whatever's mapped)
            └─> jql: project = X AND status = "To Do"
            └─> API returns 3 issues (not 5000)
            └─> normalize status to canonical
       <─ JSON array of 3
  <─ JSON array of 3
```

The Jira savings illustrate why filter-in-provider matters at scale.

## 8. Error paths

| Trigger | Outcome |
|---|---|
| `task_storage_list pizza` | adapter rejects, exit 1, stderr message — never reaches provider |
| `task_storage_list a b c` | adapter rejects, exit 1, stderr message — never reaches provider |
| `task_storage_list ready` on chat-paste | adapter validates, dispatch returns 2 (not implemented), unchanged behavior |
| `task_storage_list ready` on backlog with no `backlog/tasks/` | provider returns `[]`, exit 0 |
| Jira API failure | provider returns 1, error to stderr — unchanged from today |

## 9. Testing strategy

### Adapter validation tests (new file: `tests/lib/task-storage-list-validation.bats`)

- accepts no arg
- accepts empty string
- accepts `ready`, `in_progress`, `done`
- rejects unknown status with exit 1 + stderr message
- rejects 2+ args with exit 1 + stderr message
- empty string is treated as "no filter" by the dispatched provider

### Per-provider list filter tests (extend existing test files)

For backlog (`tests/lib/backlog-provider.bats`):

- `list` returns all when no filter
- `list ""` returns all
- `list ready` returns only ready tasks
- `list ready` returns `[]` when no ready tasks exist
- `list done` returns only done tasks (sanity check, all-statuses coverage)

For local-file (`tests/lib/task-storage-adapter.bats`): same shape.

For jira/notion/linear: mock the underlying API client to assert that the filter is passed through (JQL contains status clause, Notion filter object built, Linear GraphQL filter built). These are already mock-based tests, so we extend the assertions.

For chat-paste: assert that `list` and `list ready` both return the existing "not yet implemented" exit code 2 — no regression.

### Round-trip integration test (extend `tests/lib/task-storage-status-normalization.bats`)

- create a task, verify `list ready` includes it
- mark it `in_progress`, verify `list ready` excludes it and `list in_progress` includes it
- mark it `done`, verify only `list done` includes it

### Smoke test from real backlog (one-shot)

After implementation, run on the actual `backlog/tasks/` of this repo:

```
$ task_storage_list ready | jq 'length'
2
$ task_storage_list done | jq 'length'
28
$ task_storage_list | jq 'length'
30
$ task_storage_list pizza
task_storage_list: invalid status 'pizza' (expected: ready|in_progress|done)
```

Numbers must match the actual file system state. This is the canary that catches the original bug.

## 10. Migration

The change is **additive** — every existing call site keeps working. No call site needs to change immediately. The `commands/autopilot-sprint.md` Step 2 update is a follow-on simplification, not a prerequisite.

Order of operations during implementation:

1. Adapter validation (Section 6.1) + tests
2. Backlog provider filter (Section 6.2) + tests
3. Local-file provider filter (Section 6.3) + tests
4. Jira/Notion/Linear filters (Sections 6.5–6.7) + tests
5. Smoke test on real backlog
6. Update `commands/autopilot-sprint.md` Step 2 (Section 6.8) + skill text (Section 6.9)
7. Release as v0.7.1 (patch — no breaking change)

Each step is committable on its own.

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Tests in `backlog-provider.bats` already assert `list` returns all tasks. They should keep passing because the no-arg call is unchanged. | Run full suite after step 2; if any test fails, the change is wrong. |
| Provider filter logic for remote APIs (Jira JQL, Notion filter object) is fragile to mock. | Mock the API client at the HTTP boundary, not the API contract. Existing tests already do this for `list` — extend the same pattern. |
| Two callers compress `list + jq filter` into separate steps and forget to update during migration. | Step 6 (command/skill text update) is part of the same release. Search-replace `task_storage_list` followed by jq status filter in command and skill files; replace with single call. |
| Backward compat assumption is wrong: some external consumer uses positional args today expecting them to be ignored. | Highly unlikely (no documented usage). The validation rejects unknown status, so a stray `task_storage_list "some random string"` becomes an error instead of silently returning everything — net safer. |

## 12. Release plan

- Branch name: `feat/task-storage-list-status-filter` (single branch with sequential commits, one per step in Section 10). Cherry-pick / multi-branch only if conflicts surface during implementation; the writing-plans step decides the final structure.
- Version bump: v0.7.0 → v0.7.1
- Changelog entry: "feat(task-storage): `list` accepts an optional canonical status filter; arity and vocabulary validated by the adapter"
- The release runs through `scripts/release.sh v0.7.1` per CLAUDE.md release flow

## 13. Open questions

None. All decisions resolved during brainstorming on 2026-04-29.
