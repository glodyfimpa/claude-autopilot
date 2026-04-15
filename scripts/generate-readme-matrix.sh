#!/usr/bin/env bash
# scripts/generate-readme-matrix.sh
#
# Generates the provider matrix markdown table from lib/known-providers.sh
# and the actual provider files. Providers whose every function exits with
# "return 2" are classified as stubs; the rest are implemented.
#
# Usage:
#   bash scripts/generate-readme-matrix.sh
#
# Output goes to stdout. Pipe to update README.md or compare with existing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/known-providers.sh
source "$PLUGIN_ROOT/lib/known-providers.sh"

# A provider is a stub when every function in the file returns 2.
# Compares the count of function definitions with the count of "return 2" lines.
# Files that mix real implementations with "return 2" on some actions are NOT stubs.
_is_stub() {
  local file="$1"
  if [ ! -f "$file" ]; then
    # Missing file: treat as stub (provider declared but no file exists)
    return 0
  fi
  local func_count=0 return2_count=0
  func_count="$(grep -c '() {' "$file" 2>/dev/null)" || func_count=0
  # Count only non-comment lines with "return 2"
  return2_count="$(grep -v '^ *#' "$file" 2>/dev/null | grep -c 'return 2')" || return2_count=0
  if [ "$func_count" -eq 0 ]; then
    # No functions at all: not a meaningful provider
    return 1
  fi
  if [ "$return2_count" -gt 0 ] && [ "$func_count" -eq "$return2_count" ]; then
    return 0
  fi
  return 1
}

# Build a pipe-separated table row for one stage.
# Arguments: stage_label providers_string providers_directory
_generate_stage_row() {
  local stage_label="$1"
  local providers="$2"
  local providers_dir="$3"
  local implemented=""
  local stubs=""
  local p
  for p in $providers; do
    local file="$providers_dir/${p}.sh"
    if _is_stub "$file"; then
      if [ -n "$stubs" ]; then
        stubs="$stubs, $p"
      else
        stubs="$p"
      fi
    else
      if [ -n "$implemented" ]; then
        implemented="$implemented, $p"
      else
        implemented="$p"
      fi
    fi
  done
  echo "| $stage_label | $implemented | $stubs |"
}

echo "| Stage | Implemented | Stubs available |"
echo "|-------|-------------|-----------------|"
_generate_stage_row "PRD source"       "$PRD_SOURCE_KNOWN_PROVIDERS"       "$PLUGIN_ROOT/lib/prd-source-providers"
_generate_stage_row "Task storage"     "$TASK_STORAGE_KNOWN_PROVIDERS"     "$PLUGIN_ROOT/lib/task-storage-providers"
_generate_stage_row "PR target"        "$PR_ADAPTER_KNOWN_PROVIDERS"       "$PLUGIN_ROOT/lib/pr-providers"
_generate_stage_row "Code quality"     "$CODE_QUALITY_KNOWN_PROVIDERS"     "$PLUGIN_ROOT/lib/code-quality-providers"
_generate_stage_row "Frontend verify"  "$FRONTEND_VERIFY_KNOWN_PROVIDERS"  "$PLUGIN_ROOT/lib/frontend-verify-providers"
