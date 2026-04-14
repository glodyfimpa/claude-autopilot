#!/usr/bin/env bash
# lib/code-quality-providers/none.sh - Opt-out provider (no code quality checks)

code_quality_none_scan() {
  printf '{"issues":[]}\n'
  return 0
}

code_quality_none_check() {
  return 0
}
