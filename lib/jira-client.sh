#!/usr/bin/env bash
# lib/jira-client.sh - Shared helper for Jira MCP/API tool calls.
#
# Provides thin wrappers around the Atlassian MCP tools. Each function prints
# the raw JSON response on stdout and returns 0 on success.
#
# These functions are designed to be overridden in tests (just redefine the
# function before calling the provider). In production, they delegate to
# the Claude Code MCP tool interface.
#
# Required config keys (read via config_get):
#   jira.project_key                   - The Jira project key (e.g. "PROJ")
#   jira.issue_type                    - Issue type for creation (default: "Task")
#   jira.status_values.ready           - Value for ready status (default: "To Do")
#   jira.status_values.in_progress     - Value for in_progress status (default: "In Progress")
#   jira.status_values.done            - Value for done status (default: "Done")

# Fetch a Jira issue by key. Prints the issue JSON on stdout.
# Usage: jira_client_fetch_issue <issue_key>
# Guard: if already defined (e.g. by a test mock), skip re-definition.
if ! declare -f jira_client_fetch_issue >/dev/null 2>&1; then
jira_client_fetch_issue() {
  local issue_key="$1"
  if [[ -z "$issue_key" ]]; then
    echo "jira_client_fetch_issue: issue_key is required" >&2
    return 1
  fi
  echo "__MCP_CALL__:mcp__atlassian__get_issue:$(jq -nc --arg key "$issue_key" '{issueKey: $key}')"
}
fi

# Create a Jira issue. Prints the created issue JSON on stdout.
# Usage: jira_client_create_issue <project_key> <summary> <description> <issue_type>
if ! declare -f jira_client_create_issue >/dev/null 2>&1; then
jira_client_create_issue() {
  local project_key="$1"
  local summary="$2"
  local description="$3"
  local issue_type="$4"
  if [[ -z "$project_key" || -z "$summary" ]]; then
    echo "jira_client_create_issue: project_key and summary are required" >&2
    return 1
  fi
  local args
  args="$(jq -nc \
    --arg proj "$project_key" \
    --arg sum "$summary" \
    --arg desc "$description" \
    --arg type "$issue_type" \
    '{projectKey: $proj, summary: $sum, description: $desc, issueType: $type}')"
  echo "__MCP_CALL__:mcp__atlassian__create_issue:${args}"
}
fi

# Transition a Jira issue to a new status. Prints the response on stdout.
# Usage: jira_client_transition_issue <issue_key> <transition_name>
if ! declare -f jira_client_transition_issue >/dev/null 2>&1; then
jira_client_transition_issue() {
  local issue_key="$1"
  local transition_name="$2"
  if [[ -z "$issue_key" || -z "$transition_name" ]]; then
    echo "jira_client_transition_issue: issue_key and transition_name are required" >&2
    return 1
  fi
  local args
  args="$(jq -nc \
    --arg key "$issue_key" \
    --arg transition "$transition_name" \
    '{issueKey: $key, transition: $transition}')"
  echo "__MCP_CALL__:mcp__atlassian__transition_issue:${args}"
}
fi

# Search Jira issues by project key and optional JQL. Prints results JSON on stdout.
# Usage: jira_client_search_issues <project_key> [jql_extra]
if ! declare -f jira_client_search_issues >/dev/null 2>&1; then
jira_client_search_issues() {
  local project_key="$1"
  local jql_extra="${2:-}"
  if [[ -z "$project_key" ]]; then
    echo "jira_client_search_issues: project_key is required" >&2
    return 1
  fi
  local jql="project = ${project_key}"
  if [[ -n "$jql_extra" ]]; then
    jql="${jql} AND ${jql_extra}"
  fi
  local args
  args="$(jq -nc --arg jql "$jql" '{jql: $jql}')"
  echo "__MCP_CALL__:mcp__atlassian__search_issues:${args}"
}
fi
