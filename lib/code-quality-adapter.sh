#!/usr/bin/env bash
# lib/code-quality-adapter.sh - Dispatcher for code quality operations.
#
# Code quality providers run semantic analysis (code smells, complexity,
# duplication, security hotspots) that lint and type checks cannot see.
# The active provider lives in code_quality.provider in .autopilot-pipeline.json.
#
# Includes a retry loop (max 5 iterations) that re-scans after fixes.
#
# Depends on lib/config.sh and lib/adapter-base.sh being sourced first.

CODE_QUALITY_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_QUALITY_PROVIDERS_DIR="$CODE_QUALITY_ADAPTER_SELF_DIR/code-quality-providers"
CODE_QUALITY_CURRENT_PROVIDER=""
CODE_QUALITY_MAX_RETRIES=5

# shellcheck source=/dev/null
source "$CODE_QUALITY_ADAPTER_SELF_DIR/known-providers.sh"
# shellcheck source=/dev/null
source "$CODE_QUALITY_ADAPTER_SELF_DIR/adapter-base.sh"

code_quality_validate_provider() {
  adapter_validate_provider "$CODE_QUALITY_KNOWN_PROVIDERS" "$1"
}

_code_quality_dispatch() {
  adapter_dispatch \
    "CODE_QUALITY" \
    "code_quality" \
    "code_quality.provider" \
    "$CODE_QUALITY_KNOWN_PROVIDERS" \
    "$CODE_QUALITY_PROVIDERS_DIR" \
    "code_quality" \
    "$@"
}

code_quality_scan()  { _code_quality_dispatch "scan" "$@"; }
code_quality_check() { _code_quality_dispatch "check" "$@"; }

# Retry loop: run scan, check if issues remain, repeat up to MAX_RETRIES.
# Returns 0 when scan returns 0 issues, 1 when max retries exceeded.
# Prints each scan result to stdout so the caller can see progress.
code_quality_retry_loop() {
  local iteration=0
  local result issues_count

  while [ "$iteration" -lt "$CODE_QUALITY_MAX_RETRIES" ]; do
    iteration=$((iteration + 1))
    result="$(code_quality_scan)" || {
      local rc=$?
      # Provider not implemented (stub) or check failed
      echo "$result"
      return $rc
    }

    issues_count="$(printf '%s\n' "$result" | jq '.issues | length')"
    if [ "$issues_count" -eq 0 ]; then
      echo "code quality pass: 0 issues found (iteration $iteration)"
      return 0
    fi

    echo "code quality iteration $iteration: $issues_count issue(s) found" >&2
    printf '%s\n' "$result"

    if [ "$iteration" -ge "$CODE_QUALITY_MAX_RETRIES" ]; then
      echo "code quality failed after $CODE_QUALITY_MAX_RETRIES iterations. $issues_count issue(s) remain." >&2
      return 1
    fi
  done
}
