#!/usr/bin/env bash
# lib/linear-client.sh - Shared helper for Linear MCP/API tool calls.
#
# Provides thin wrappers around the Linear MCP tools. Each function prints
# the raw JSON response on stdout and returns 0 on success.
#
# These functions are designed to be overridden in tests (just redefine the
# function before calling the provider). In production, they delegate to
# the Claude Code MCP tool interface.
#
# Required config keys (read via config_get):
#   linear.team_id                     - The Linear team ID
#   linear.status_values.ready         - Value for ready status (default: "Todo")
#   linear.status_values.in_progress   - Value for in_progress status (default: "In Progress")
#   linear.status_values.done          - Value for done status (default: "Done")

# Fetch a Linear issue by ID. Prints the issue JSON on stdout.
# Usage: linear_client_fetch_issue <issue_id>
# Guard: if already defined (e.g. by a test mock), skip re-definition.
if ! declare -f linear_client_fetch_issue >/dev/null 2>&1; then
linear_client_fetch_issue() {
  local issue_id="$1"
  if [[ -z "$issue_id" ]]; then
    echo "linear_client_fetch_issue: issue_id is required" >&2
    return 1
  fi
  echo "__MCP_CALL__:mcp__linear__get_issue:$(jq -nc --arg id "$issue_id" '{issueId: $id}')"
}
fi

# Create a Linear issue. Prints the created issue JSON on stdout.
# Usage: linear_client_create_issue <team_id> <title> <description>
if ! declare -f linear_client_create_issue >/dev/null 2>&1; then
linear_client_create_issue() {
  local team_id="$1"
  local title="$2"
  local description="$3"
  if [[ -z "$team_id" || -z "$title" ]]; then
    echo "linear_client_create_issue: team_id and title are required" >&2
    return 1
  fi
  local args
  args="$(jq -nc \
    --arg team "$team_id" \
    --arg title "$title" \
    --arg desc "$description" \
    '{teamId: $team, title: $title, description: $desc}')"
  echo "__MCP_CALL__:mcp__linear__create_issue:${args}"
}
fi

# Update the state of a Linear issue. Prints the response on stdout.
# Usage: linear_client_update_state <issue_id> <state_name>
if ! declare -f linear_client_update_state >/dev/null 2>&1; then
linear_client_update_state() {
  local issue_id="$1"
  local state_name="$2"
  if [[ -z "$issue_id" || -z "$state_name" ]]; then
    echo "linear_client_update_state: issue_id and state_name are required" >&2
    return 1
  fi
  local args
  args="$(jq -nc \
    --arg id "$issue_id" \
    --arg state "$state_name" \
    '{issueId: $id, state: $state}')"
  echo "__MCP_CALL__:mcp__linear__update_issue:${args}"
}
fi

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
