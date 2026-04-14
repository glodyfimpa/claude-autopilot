#!/usr/bin/env bash
# lib/task-storage-providers/jira.sh - Task storage backed by Jira.
#
# Uses the Atlassian MCP tools via lib/jira-client.sh:
#   - jira_client_fetch_issue       for fetching a single issue
#   - jira_client_search_issues     for listing issues
#   - jira_client_create_issue      for creating a new issue
#   - jira_client_transition_issue  for updating issue status
#
# Required config keys:
#   jira.project_key                    - The Jira project key (e.g. "PROJ")
#   jira.issue_type                     - Issue type for creation (default: "Task")
#   jira.status_values.ready            - Value for ready status (default: "To Do")
#   jira.status_values.in_progress      - Value for in_progress status (default: "In Progress")
#   jira.status_values.done             - Value for done status (default: "Done")

JIRA_TS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$JIRA_TS_SELF_DIR/../jira-client.sh"

# Map an internal status name (ready, in_progress, done) to the Jira value.
_jira_ts_status_value() {
  local internal="$1"
  local val
  val="$(config_get "jira.status_values.${internal}" 2>/dev/null || true)"
  if [[ -n "$val" ]]; then
    printf '%s\n' "$val"
    return 0
  fi
  # Defaults
  case "$internal" in
    ready)       echo "To Do" ;;
    in_progress) echo "In Progress" ;;
    done)        echo "Done" ;;
    *)           echo "$internal" ;;
  esac
}

# Reverse-map a Jira status string to an internal status name.
_jira_ts_internal_status() {
  local jira_status="$1"
  local ready_val in_prog_val done_val
  ready_val="$(_jira_ts_status_value "ready")"
  in_prog_val="$(_jira_ts_status_value "in_progress")"
  done_val="$(_jira_ts_status_value "done")"
  if [[ "$jira_status" == "$ready_val" ]]; then
    echo "ready"
  elif [[ "$jira_status" == "$in_prog_val" ]]; then
    echo "in_progress"
  elif [[ "$jira_status" == "$done_val" ]]; then
    echo "done"
  else
    echo "$jira_status"
  fi
}

# Parse acceptance criteria from description text (lines starting with "- ").
_jira_ts_parse_criteria() {
  local description="$1"
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
  printf '%s' "$criteria_raw"
}

# Fetch a single task from Jira by issue key.
# Returns normalized JSON: { id, title, description, status, parent, acceptanceCriteria }
task_storage_jira_fetch() {
  local issue_key="$1"
  if [[ -z "$issue_key" ]]; then
    echo "jira task-storage fetch requires an issue key" >&2
    return 1
  fi

  local response
  response="$(jira_client_fetch_issue "$issue_key")" || return 1

  local id title status_val description
  id="$(echo "$response" | jq -r '.key // ""')"
  title="$(echo "$response" | jq -r '.fields.summary // ""')"
  status_val="$(echo "$response" | jq -r '.fields.status.name // ""')"
  description="$(echo "$response" | jq -r '.fields.description // ""')"

  local internal_status
  internal_status="$(_jira_ts_internal_status "$status_val")"

  local criteria_raw
  criteria_raw="$(_jira_ts_parse_criteria "$description")"

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

# Update the status of a Jira issue via transition.
task_storage_jira_update_status() {
  local issue_key="$1"
  local new_status="$2"
  if [[ -z "$issue_key" || -z "$new_status" ]]; then
    echo "jira task-storage update_status requires issue_key and new_status" >&2
    return 1
  fi

  local jira_status
  jira_status="$(_jira_ts_status_value "$new_status")"
  jira_client_transition_issue "$issue_key" "$jira_status" >/dev/null || return 1
}

# Create a new issue in the configured Jira project.
# Usage: task_storage_jira_create <title> <description> <criteria_csv> [parent]
task_storage_jira_create() {
  local title="$1"
  local description="$2"
  local criteria_csv="$3"

  local project_key
  project_key="$(config_get "jira.project_key" 2>/dev/null || true)"
  if [[ -z "$project_key" ]]; then
    echo "jira.project_key not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local issue_type
  issue_type="$(config_get "jira.issue_type" 2>/dev/null || true)"
  issue_type="${issue_type:-Task}"

  # Build the description with acceptance criteria
  local body="$description"
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

  local response
  response="$(jira_client_create_issue "$project_key" "$title" "$body" "$issue_type")" || return 1

  local issue_key
  issue_key="$(echo "$response" | jq -r '.key // ""')"
  printf '%s\n' "$issue_key"
}

# List all issues in the configured Jira project.
task_storage_jira_list() {
  local project_key
  project_key="$(config_get "jira.project_key" 2>/dev/null || true)"
  if [[ -z "$project_key" ]]; then
    echo "jira.project_key not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local response
  response="$(jira_client_search_issues "$project_key")" || return 1

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
