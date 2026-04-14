#!/usr/bin/env bash
# lib/task-storage-providers/linear.sh - Task storage backed by Linear.
#
# Uses the Linear MCP tools via lib/linear-client.sh:
#   - linear_client_fetch_issue     for fetching a single issue
#   - linear_client_list_issues     for listing issues
#   - linear_client_create_issue    for creating a new issue
#   - linear_client_update_state    for updating issue state
#
# Required config keys:
#   linear.team_id                      - The Linear team ID
#   linear.status_values.ready          - Value for ready status (default: "Todo")
#   linear.status_values.in_progress    - Value for in_progress status (default: "In Progress")
#   linear.status_values.done           - Value for done status (default: "Done")

LINEAR_TS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$LINEAR_TS_SELF_DIR/../linear-client.sh"

# Map an internal status name (ready, in_progress, done) to the Linear value.
_linear_ts_status_value() {
  local internal="$1"
  local val
  val="$(config_get "linear.status_values.${internal}" 2>/dev/null || true)"
  if [[ -n "$val" ]]; then
    printf '%s\n' "$val"
    return 0
  fi
  # Defaults
  case "$internal" in
    ready)       echo "Todo" ;;
    in_progress) echo "In Progress" ;;
    done)        echo "Done" ;;
    *)           echo "$internal" ;;
  esac
}

# Reverse-map a Linear state string to an internal status name.
_linear_ts_internal_status() {
  local linear_state="$1"
  local ready_val in_prog_val done_val
  ready_val="$(_linear_ts_status_value "ready")"
  in_prog_val="$(_linear_ts_status_value "in_progress")"
  done_val="$(_linear_ts_status_value "done")"
  if [[ "$linear_state" == "$ready_val" ]]; then
    echo "ready"
  elif [[ "$linear_state" == "$in_prog_val" ]]; then
    echo "in_progress"
  elif [[ "$linear_state" == "$done_val" ]]; then
    echo "done"
  else
    echo "$linear_state"
  fi
}

# Parse acceptance criteria from description text (lines starting with "- ").
_linear_ts_parse_criteria() {
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

# Fetch a single task from Linear by issue ID.
# Returns normalized JSON: { id, title, description, status, parent, acceptanceCriteria }
task_storage_linear_fetch() {
  local issue_id="$1"
  if [[ -z "$issue_id" ]]; then
    echo "linear task-storage fetch requires an issue id" >&2
    return 1
  fi

  local response
  response="$(linear_client_fetch_issue "$issue_id")" || return 1

  local id title state_val description
  id="$(echo "$response" | jq -r '.id // ""')"
  title="$(echo "$response" | jq -r '.title // ""')"
  state_val="$(echo "$response" | jq -r '.state.name // ""')"
  description="$(echo "$response" | jq -r '.description // ""')"

  local internal_status
  internal_status="$(_linear_ts_internal_status "$state_val")"

  local criteria_raw
  criteria_raw="$(_linear_ts_parse_criteria "$description")"

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

# Update the state of a Linear issue.
task_storage_linear_update_status() {
  local issue_id="$1"
  local new_status="$2"
  if [[ -z "$issue_id" || -z "$new_status" ]]; then
    echo "linear task-storage update_status requires issue_id and new_status" >&2
    return 1
  fi

  local linear_state
  linear_state="$(_linear_ts_status_value "$new_status")"
  linear_client_update_state "$issue_id" "$linear_state" >/dev/null || return 1
}

# Create a new issue in the configured Linear team.
# Usage: task_storage_linear_create <title> <description> <criteria_csv> [parent]
task_storage_linear_create() {
  local title="$1"
  local description="$2"
  local criteria_csv="$3"

  local team_id
  team_id="$(config_get "linear.team_id" 2>/dev/null || true)"
  if [[ -z "$team_id" ]]; then
    echo "linear.team_id not configured. Run /autopilot-configure first." >&2
    return 1
  fi

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
  response="$(linear_client_create_issue "$team_id" "$title" "$body")" || return 1

  local issue_id
  issue_id="$(echo "$response" | jq -r '.id // ""')"
  printf '%s\n' "$issue_id"
}

# List all issues in the configured Linear team.
task_storage_linear_list() {
  local team_id
  team_id="$(config_get "linear.team_id" 2>/dev/null || true)"
  if [[ -z "$team_id" ]]; then
    echo "linear.team_id not configured. Run /autopilot-configure first." >&2
    return 1
  fi

  local response
  response="$(linear_client_list_issues "$team_id")" || return 1

  local ready_val in_prog_val done_val
  ready_val="$(_linear_ts_status_value "ready")"
  in_prog_val="$(_linear_ts_status_value "in_progress")"
  done_val="$(_linear_ts_status_value "done")"

  echo "$response" | jq \
    --arg ready_val "$ready_val" \
    --arg in_prog_val "$in_prog_val" \
    --arg done_val "$done_val" \
    '[.issues // [] | .[] | {
      id: .id,
      title: .title,
      description: (.description // ""),
      status: (
        (.state.name // "") as $s |
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
