#!/usr/bin/env bash
# lib/task-storage-providers/notion.sh - Task storage backed by a Notion database.
#
# Uses the Notion MCP tools via lib/notion-client.sh:
#   - notion-fetch           for fetching a single task page
#   - notion-query-database-view  for listing tasks
#   - notion-create-pages    for creating a new task
#   - notion-update-page     for updating task status
#
# Required config keys:
#   notion.database_id              - The Notion database ID
#   notion.status_property          - Name of the status property (default: "Status")
#   notion.status_values.ready      - Value for ready status (default: "Ready")
#   notion.status_values.in_progress - Value for in_progress status (default: "In Progress")
#   notion.status_values.done       - Value for done status (default: "Done")

NOTION_TS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$NOTION_TS_SELF_DIR/../notion-client.sh"

# Read the configured status property name, with fallback.
_notion_ts_status_property() {
  local prop
  prop="$(config_get "notion.status_property" 2>/dev/null || true)"
  printf '%s\n' "${prop:-Status}"
}

# Map an internal status name (ready, in_progress, done) to the Notion value.
_notion_ts_status_value() {
  local internal="$1"
  local val
  val="$(config_get "notion.status_values.${internal}" 2>/dev/null || true)"
  if [[ -n "$val" ]]; then
    printf '%s\n' "$val"
    return 0
  fi
  # Defaults
  case "$internal" in
    ready)       echo "Ready" ;;
    in_progress) echo "In Progress" ;;
    done)        echo "Done" ;;
    *)           echo "$internal" ;;
  esac
}

# Fetch a single task from Notion by page ID.
# Returns normalized JSON: { id, title, description, status, parent, acceptanceCriteria }
task_storage_notion_fetch() {
  local page_id="$1"
  if [[ -z "$page_id" ]]; then
    echo "notion task-storage fetch requires a page id" >&2
    return 1
  fi

  local response
  response="$(notion_client_fetch_page "$page_id")" || return 1

  local status_prop
  status_prop="$(_notion_ts_status_property)"

  # Extract fields from the Notion page response
  local id title status_val description
  id="$(echo "$response" | notion_client_extract_id)"
  title="$(echo "$response" | notion_client_extract_title "Name")"
  status_val="$(echo "$response" | notion_client_extract_status "$status_prop")"
  description="$(echo "$response" | notion_client_extract_markdown)"

  # Map Notion status back to internal status
  local internal_status="$status_val"
  local ready_val in_prog_val done_val
  ready_val="$(_notion_ts_status_value "ready")"
  in_prog_val="$(_notion_ts_status_value "in_progress")"
  done_val="$(_notion_ts_status_value "done")"
  if [[ "$status_val" == "$ready_val" ]]; then
    internal_status="ready"
  elif [[ "$status_val" == "$in_prog_val" ]]; then
    internal_status="in_progress"
  elif [[ "$status_val" == "$done_val" ]]; then
    internal_status="done"
  fi

  # Parse acceptance criteria from the description markdown (lines starting with "- ")
  local criteria_raw=""
  local line
  local in_ac=0
  while IFS= read -r line; do
    if [[ "$line" == "## Acceptance Criteria"* ]]; then
      in_ac=1
      continue
    fi
    if [[ $in_ac -eq 1 && "$line" == "##"* ]]; then
      break
    fi
    if [[ $in_ac -eq 1 ]] && [[ "$line" =~ ^-[[:space:]]+(.+)$ ]]; then
      local item="${BASH_REMATCH[1]}"
      if [[ -z "$criteria_raw" ]]; then
        criteria_raw="$item"
      else
        criteria_raw="${criteria_raw}|||${item}"
      fi
    fi
  done <<< "$description"

  jq -n \
    --arg id "$id" \
    --arg title "$title" \
    --arg description "$description" \
    --arg status "$internal_status" \
    --arg criteria_raw "$criteria_raw" \
    '{
      id: $id,
      title: $title,
      description: $description,
      status: $status,
      parent: null,
      acceptanceCriteria: (
        if $criteria_raw == "" then []
        else ($criteria_raw | split("|||"))
        end
      )
    }'
}

# Update the status of a Notion task page.
task_storage_notion_update_status() {
  local page_id="$1"
  local new_status="$2"
  if [[ -z "$page_id" || -z "$new_status" ]]; then
    echo "notion task-storage update_status requires page_id and new_status" >&2
    return 1
  fi

  local status_prop notion_status props_json
  status_prop="$(_notion_ts_status_property)"
  notion_status="$(_notion_ts_status_value "$new_status")"

  props_json="$(jq -nc --arg prop "$status_prop" --arg val "$notion_status" \
    '{($prop): {status: {name: $val}}}')"

  notion_client_update_page "$page_id" "$props_json" >/dev/null || return 1
}

# Create a new task in the configured Notion database.
# Usage: task_storage_notion_create <title> <description> <criteria_csv> [parent]
task_storage_notion_create() {
  local title="$1"
  local description="$2"
  local criteria_csv="$3"
  local parent="${4:-}"

  local database_id
  database_id="$(config_get "notion.database_id" 2>/dev/null || true)"
  if [[ -z "$database_id" ]]; then
    echo "notion.database_id not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local status_prop ready_val
  status_prop="$(_notion_ts_status_property)"
  ready_val="$(_notion_ts_status_value "ready")"

  # Build the body content with description and acceptance criteria
  local body="## Description\n${description}"
  if [[ -n "$criteria_csv" ]]; then
    body="${body}\n\n## Acceptance Criteria"
    local IFS=','
    local c
    for c in $criteria_csv; do
      c="${c#"${c%%[![:space:]]*}"}"
      c="${c%"${c##*[![:space:]]}"}"
      [[ -n "$c" ]] && body="${body}\n- ${c}"
    done
  fi

  local props_json
  props_json="$(jq -nc \
    --arg title "$title" \
    --arg prop "$status_prop" \
    --arg status "$ready_val" \
    '{
      Name: {title: [{text: {content: $title}}]},
      ($prop): {status: {name: $status}}
    }')"

  local response
  response="$(notion_client_create_page "$database_id" "$props_json")" || return 1

  local page_id
  page_id="$(echo "$response" | notion_client_extract_id)"
  printf '%s\n' "$page_id"
}

# List all tasks in the configured Notion database (optionally filtered by status).
task_storage_notion_list() {
  local database_id
  database_id="$(config_get "notion.database_id" 2>/dev/null || true)"
  if [[ -z "$database_id" ]]; then
    echo "notion.database_id not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local response
  response="$(notion_client_query_database "$database_id")" || return 1

  local status_prop
  status_prop="$(_notion_ts_status_property)"

  local ready_val in_prog_val done_val
  ready_val="$(_notion_ts_status_value "ready")"
  in_prog_val="$(_notion_ts_status_value "in_progress")"
  done_val="$(_notion_ts_status_value "done")"

  echo "$response" | jq \
    --arg status_prop "$status_prop" \
    --arg ready_val "$ready_val" \
    --arg in_prog_val "$in_prog_val" \
    --arg done_val "$done_val" \
    '[.results // [] | .[] | {
      id: .id,
      title: (.properties.Name.title // [] | map(.plain_text // "") | join("")),
      description: "",
      status: (
        (.properties[$status_prop].status.name // .properties[$status_prop].select.name // "") as $s |
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
