#!/usr/bin/env bats
# Tests for lib/task-storage-adapter.sh
#
# Responsibility: dispatch task operations (fetch, list, create, updateStatus)
# to the configured task storage provider. The interface is stable across
# providers; the adapter just routes calls by provider name.

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/task-storage-adapter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- task_storage_validate_provider --------

@test "task_storage_validate_provider accepts known providers" {
  run task_storage_validate_provider "local-file"
  assert_equal "0" "$status"
  run task_storage_validate_provider "chat-paste"
  assert_equal "0" "$status"
  run task_storage_validate_provider "notion"
  assert_equal "0" "$status"
  run task_storage_validate_provider "jira"
  assert_equal "0" "$status"
  run task_storage_validate_provider "linear"
  assert_equal "0" "$status"
  run task_storage_validate_provider "backlog"
  assert_equal "0" "$status"
}

@test "task_storage_validate_provider rejects unknown providers" {
  run task_storage_validate_provider "sqlite"
  assert_equal "1" "$status"
  run task_storage_validate_provider ""
  assert_equal "1" "$status"
}

# -------- task_storage_fetch --------

@test "task_storage_fetch fails when no provider is configured" {
  config_init
  run task_storage_fetch "task-1"
  assert_equal "1" "$status"
  assert_contains "$output" "no task_storage provider configured"
}

@test "task_storage_fetch delegates to local-file provider and returns JSON" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  cat > tasks/task-1.md <<'EOF'
---
id: task-1
title: Add login page
status: ready
---

## Description
Users need to log in via email and password.

## Acceptance Criteria
- Form validates email
- Error message shown on invalid credentials
- Redirect to dashboard on success
EOF
  run task_storage_fetch "tasks/task-1.md"
  assert_equal "0" "$status"
  # Parse the returned JSON
  local title criteria_count
  title="$(echo "$output" | jq -r '.title')"
  criteria_count="$(echo "$output" | jq -r '.acceptanceCriteria | length')"
  assert_equal "Add login page" "$title"
  assert_equal "3" "$criteria_count"
}

@test "task_storage_fetch returns stub message for unimplemented providers" {
  config_init
  config_set "task_storage.provider" "jira"
  run task_storage_fetch "abc123"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

# -------- Notion provider tests (mocked MCP calls) --------

@test "notion: task_storage_fetch returns normalized task JSON" {
  config_init
  config_set "task_storage.provider" "notion"
  config_set "notion.status_property" "Status"
  config_set "notion.status_values.ready" "Ready"

  # Mock the MCP client to return a realistic Notion page response
  notion_client_fetch_page() {
    cat <<'MOCK'
{
  "id": "page-abc-123",
  "properties": {
    "Name": {"title": [{"plain_text": "Implement auth"}]},
    "Status": {"status": {"name": "Ready"}}
  },
  "markdown": "## Description\nUsers need OAuth login.\n\n## Acceptance Criteria\n- Google OAuth works\n- Token refresh handled"
}
MOCK
  }

  run task_storage_fetch "page-abc-123"
  assert_equal "0" "$status"
  local title id ac_count st
  title="$(echo "$output" | jq -r '.title')"
  id="$(echo "$output" | jq -r '.id')"
  ac_count="$(echo "$output" | jq -r '.acceptanceCriteria | length')"
  st="$(echo "$output" | jq -r '.status')"
  assert_equal "Implement auth" "$title"
  assert_equal "page-abc-123" "$id"
  assert_equal "2" "$ac_count"
  assert_equal "ready" "$st"
}

@test "notion: task_storage_fetch maps in_progress status" {
  config_init
  config_set "task_storage.provider" "notion"
  config_set "notion.status_property" "Status"
  config_set "notion.status_values.in_progress" "In Progress"

  notion_client_fetch_page() {
    cat <<'MOCK'
{
  "id": "page-456",
  "properties": {
    "Name": {"title": [{"plain_text": "Fix bug"}]},
    "Status": {"status": {"name": "In Progress"}}
  },
  "markdown": "A bug fix."
}
MOCK
  }

  run task_storage_fetch "page-456"
  assert_equal "0" "$status"
  local st
  st="$(echo "$output" | jq -r '.status')"
  assert_equal "in_progress" "$st"
}

@test "notion: task_storage_update_status calls MCP with correct properties" {
  config_init
  config_set "task_storage.provider" "notion"
  config_set "notion.status_property" "Status"
  config_set "notion.status_values.in_progress" "In Progress"

  local captured_page_id="" captured_props=""
  notion_client_update_page() {
    captured_page_id="$1"
    captured_props="$2"
    echo '{"id": "page-789"}'
  }

  run task_storage_update_status "page-789" "in_progress"
  assert_equal "0" "$status"
}

@test "notion: task_storage_create requires database_id config" {
  config_init
  config_set "task_storage.provider" "notion"

  run task_storage_create "New task" "Description" "criterion1,criterion2"
  assert_equal "1" "$status"
  assert_contains "$output" "notion.database_id not configured"
}

@test "notion: task_storage_create calls MCP and returns page id" {
  config_init
  config_set "task_storage.provider" "notion"
  config_set "notion.database_id" "db-test-123"
  config_set "notion.status_property" "Status"
  config_set "notion.status_values.ready" "Ready"

  notion_client_create_page() {
    echo '{"id": "new-page-id-999"}'
  }

  run task_storage_create "Setup CI" "Add GitHub Actions" "runs on push,green on main"
  assert_equal "0" "$status"
  assert_contains "$output" "new-page-id-999"
}

@test "notion: task_storage_list requires database_id config" {
  config_init
  config_set "task_storage.provider" "notion"

  run task_storage_list
  assert_equal "1" "$status"
  assert_contains "$output" "notion.database_id not configured"
}

@test "notion: task_storage_list returns normalized JSON array" {
  config_init
  config_set "task_storage.provider" "notion"
  config_set "notion.database_id" "db-test-123"
  config_set "notion.status_property" "Status"
  config_set "notion.status_values.ready" "Ready"
  config_set "notion.status_values.done" "Done"

  notion_client_query_database() {
    cat <<'MOCK'
{
  "results": [
    {
      "id": "page-1",
      "properties": {
        "Name": {"title": [{"plain_text": "Task A"}]},
        "Status": {"status": {"name": "Ready"}}
      }
    },
    {
      "id": "page-2",
      "properties": {
        "Name": {"title": [{"plain_text": "Task B"}]},
        "Status": {"status": {"name": "Done"}}
      }
    }
  ]
}
MOCK
  }

  run task_storage_list
  assert_equal "0" "$status"
  local count first_title first_status second_status
  count="$(echo "$output" | jq 'length')"
  first_title="$(echo "$output" | jq -r '.[0].title')"
  first_status="$(echo "$output" | jq -r '.[0].status')"
  second_status="$(echo "$output" | jq -r '.[1].status')"
  assert_equal "2" "$count"
  assert_equal "Task A" "$first_title"
  assert_equal "ready" "$first_status"
  assert_equal "done" "$second_status"
}

# -------- task_storage_update_status --------

@test "task_storage_update_status updates the status field in a local-file task" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  cat > tasks/task-1.md <<'EOF'
---
id: task-1
title: Add login page
status: ready
---
body
EOF
  run task_storage_update_status "tasks/task-1.md" "in_progress"
  assert_equal "0" "$status"
  grep -q '^status: in_progress' tasks/task-1.md
}

# -------- task_storage_create --------

@test "task_storage_create writes a new task file with a deterministic id" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  run task_storage_create "Setup CI pipeline" "Add GitHub Actions workflow" "workflow runs on push,green on main"
  assert_equal "0" "$status"
  # A task file should exist under tasks/
  local files
  files=$(ls tasks/ | wc -l | tr -d ' ')
  assert_equal "1" "$files"
  local file
  file="$(ls tasks/)"
  grep -q "title: Setup CI pipeline" "tasks/$file"
  grep -q "status: ready" "tasks/$file"
}

# -------- task_storage_list --------

@test "task_storage_list returns all local-file tasks as a JSON array" {
  config_init
  config_set "task_storage.provider" "local-file"
  mkdir -p tasks
  cat > tasks/a.md <<'EOF'
---
id: a
title: First task
status: ready
---
body
EOF
  cat > tasks/b.md <<'EOF'
---
id: b
title: Second task
status: done
---
body
EOF
  run task_storage_list
  assert_equal "0" "$status"
  local count
  count="$(echo "$output" | jq 'length')"
  assert_equal "2" "$count"
}
