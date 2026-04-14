#!/usr/bin/env bash
# lib/code-quality-providers/sonarqube.sh - SonarQube code quality provider
#
# Calls the SonarQube REST API to retrieve issues after running sonar-scanner.
# Requires SONAR_HOST_URL and SONAR_PROJECT_KEY environment variables.
# The sonar-scanner CLI must be available on PATH.
#
# Returns normalized JSON: { "issues": [ { "key", "rule", "severity", "message", "component", "line", "type" } ] }

code_quality_sonarqube_check() {
  if ! command -v sonar-scanner >/dev/null 2>&1; then
    echo "sonar-scanner not found on PATH. Install it or configure the SonarQube MCP." >&2
    return 1
  fi
  if [[ -z "${SONAR_HOST_URL:-}" ]]; then
    echo "SONAR_HOST_URL is not set." >&2
    return 1
  fi
  if [[ -z "${SONAR_PROJECT_KEY:-}" ]]; then
    echo "SONAR_PROJECT_KEY is not set." >&2
    return 1
  fi
  return 0
}

code_quality_sonarqube_scan() {
  code_quality_sonarqube_check || return $?

  # Run sonar-scanner to submit analysis
  sonar-scanner \
    -Dsonar.host.url="$SONAR_HOST_URL" \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
    >/dev/null 2>&1

  # Fetch issues from the REST API
  local api_url="${SONAR_HOST_URL}/api/issues/search?componentKeys=${SONAR_PROJECT_KEY}&resolved=false&ps=500"
  local raw_response
  raw_response="$(curl -s "$api_url")"

  # Normalize the response to our standard format
  printf '%s\n' "$raw_response" | jq '{
    issues: [.issues[] | {
      key: .key,
      rule: .rule,
      severity: .severity,
      message: .message,
      component: .component,
      line: (.line // null),
      type: .type
    }]
  }'
}
