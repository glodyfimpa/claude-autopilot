#!/usr/bin/env bash
# lib/mcp-detector.sh - Detect active MCPs and git host, suggest providers
#
# The wizard uses this module to preselect defaults when configuring the
# pipeline for the first time. Detection is best-effort; the user can always
# override the suggestion.
#
# CLAUDE_SETTINGS_PATH can be set to override the settings file location
# (used by tests to avoid touching ~/.claude/settings.json).

: "${CLAUDE_SETTINGS_PATH:=$HOME/.claude/settings.json}"

MCP_DETECTOR_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$MCP_DETECTOR_SELF_DIR/known-providers.sh"

# ---------------------------------------------------------------------------
# Auto-discovery: derive provider lists from files in lib/*-providers/ dirs.
# ---------------------------------------------------------------------------

# Map a wizard stage name to its providers directory name.
# Returns 1 for stages that don't have a providers directory (e.g. parallelization, simplify).
_stage_to_providers_dir() {
  case "$1" in
    pr-target)       echo "pr-providers" ;;
    task-storage)    echo "task-storage-providers" ;;
    prd-source)      echo "prd-source-providers" ;;
    code-quality)    echo "code-quality-providers" ;;
    frontend-verify) echo "frontend-verify-providers" ;;
    *) return 1 ;;
  esac
}

# Discover providers by scanning the providers directory for .sh files.
# Prints one provider name per line (filenames without .sh extension).
# Returns 1 if the stage has no providers directory or the directory is missing.
discover_providers_for_stage() {
  local stage="$1"
  local dir_name
  dir_name="$(_stage_to_providers_dir "$stage")" || return 1
  local providers_dir="$MCP_DETECTOR_SELF_DIR/$dir_name"
  if [[ ! -d "$providers_dir" ]]; then
    return 1
  fi
  local result=""
  local f
  for f in "$providers_dir"/*.sh; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .sh)"
    result="${result:+$result }$name"
  done
  if [[ -z "$result" ]]; then
    return 1
  fi
  echo "$result"
}

# Detect the git hosting provider from the 'origin' remote URL.
# Prints one of: github, gitlab, bitbucket, unknown, none
detect_git_host() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "none"
    return 0
  fi
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    echo "none"
    return 0
  fi
  case "$url" in
    *github.com*)    echo "github" ;;
    *gitlab.com*)    echo "gitlab" ;;
    *bitbucket.org*) echo "bitbucket" ;;
    *)               echo "unknown" ;;
  esac
}

# List the MCP plugin identifiers that are currently enabled.
# Reads two sources from CLAUDE_SETTINGS_PATH:
#   - enabledPlugins: object keyed by plugin id with boolean values
#   - mcpServers:     object keyed by server name
# Prints one identifier per line.
scan_enabled_mcps() {
  if [[ ! -f "$CLAUDE_SETTINGS_PATH" ]]; then
    return 0
  fi
  if ! jq empty "$CLAUDE_SETTINGS_PATH" 2>/dev/null; then
    return 0
  fi
  jq -r '
    ((.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key),
    ((.mcpServers // {}) | keys[])
  ' "$CLAUDE_SETTINGS_PATH"
}

# Check if any enabled MCP identifier matches the given substring (case-insensitive).
# Returns 0 on match, 1 on no match.
_mcp_has_substring() {
  local needle="$1"
  local needle_lc line line_lc
  needle_lc="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r line; do
    line_lc="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    if [[ "$line_lc" == *"$needle_lc"* ]]; then
      return 0
    fi
  done < <(scan_enabled_mcps)
  return 1
}

# Suggest a provider for the pr-target stage based on the git remote.
# Prints the provider name or empty if the host is not recognized.
suggest_pr_target_provider() {
  local host
  host="$(detect_git_host)"
  case "$host" in
    github|gitlab|bitbucket) echo "$host" ;;
    *)                       echo "" ;;
  esac
}

# Suggest a provider for the task-storage stage based on active MCPs.
# Falls back to 'local-file' when no MCP matches.
suggest_task_storage_provider() {
  if _mcp_has_substring "notion"; then
    echo "notion"
    return 0
  fi
  if _mcp_has_substring "atlassian" || _mcp_has_substring "jira"; then
    echo "jira"
    return 0
  fi
  if _mcp_has_substring "linear"; then
    echo "linear"
    return 0
  fi
  if _mcp_has_substring "backlog"; then
    echo "backlog"
    return 0
  fi
  echo "local-file"
}

# Suggest a provider for the prd-source stage based on active MCPs.
# Falls back to 'local-file' when no MCP matches.
suggest_prd_source_provider() {
  if _mcp_has_substring "notion"; then
    echo "notion"
    return 0
  fi
  if _mcp_has_substring "google_drive" || _mcp_has_substring "google-drive" || _mcp_has_substring "drive"; then
    echo "google-drive"
    return 0
  fi
  if _mcp_has_substring "atlassian" || _mcp_has_substring "confluence" || _mcp_has_substring "jira"; then
    echo "jira"
    return 0
  fi
  echo "local-file"
}

# Suggest a provider for the code-quality stage based on active MCPs.
# Falls back to 'none' when no MCP matches.
suggest_code_quality_provider() {
  if _mcp_has_substring "sonarqube" || _mcp_has_substring "sonar"; then
    echo "sonarqube"
    return 0
  fi
  if _mcp_has_substring "semgrep"; then
    echo "semgrep"
    return 0
  fi
  if _mcp_has_substring "codeclimate" || _mcp_has_substring "code-climate"; then
    echo "codeclimate"
    return 0
  fi
  echo "none"
}

# Suggest a provider for the frontend-verify stage based on active MCPs.
# Falls back to 'none' when no MCP matches.
suggest_frontend_verify_provider() {
  local mcps
  mcps="$(scan_enabled_mcps 2>/dev/null || true)"
  if echo "$mcps" | grep -qi "chrome\|devtools"; then
    echo "chrome-devtools"
    return
  fi
  if echo "$mcps" | grep -qi "playwright"; then
    echo "playwright"
    return
  fi
  echo "none"
}

# List all known providers for a given pipeline stage. Returns non-zero for
# unknown stages.
#
# Provider-backed stages (pr-target, task-storage, prd-source, code-quality,
# frontend-verify) use auto-discovery: the providers directory is scanned for
# .sh files. Non-provider stages (parallelization, simplify) fall back to the
# static constants in lib/known-providers.sh.
list_available_providers_for_stage() {
  local stage="$1"

  # Try auto-discovery first (works for stages with a providers directory)
  local discovered
  discovered="$(discover_providers_for_stage "$stage" 2>/dev/null)"
  if [[ -n "$discovered" ]]; then
    # shellcheck disable=SC2086
    printf '%s\n' $discovered
    return 0
  fi

  # Fall back to static lists for non-provider stages
  local list
  case "$stage" in
    parallelization) list="$PARALLELIZATION_KNOWN_STRATEGIES" ;;
    simplify)        list="$KNOWN_SIMPLIFY_MODES" ;;
    *)
      echo "unknown stage: $stage" >&2
      return 1
      ;;
  esac
  # shellcheck disable=SC2086
  printf '%s\n' $list
}
