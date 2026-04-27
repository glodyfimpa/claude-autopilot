#!/usr/bin/env bash
# lib/release-utils.sh
#
# Pure helpers used by scripts/release.sh. No git/gh/editor side effects:
# the orchestrator script reads/writes files and shells out, while the
# functions below are pure transformations and predicates that can be
# unit-tested in isolation.
#
# All functions are side-effect free except for echoing to stdout.
#
# Public API:
#   validate_version_format <version>            -> 0 if X.Y.Z, 1 otherwise
#   version_greater_than <a> <b>                 -> 0 if a > b, 1 otherwise
#   update_readme_test_count <content> <count>   -> echoes patched content
#   update_plugin_version <content> <version>    -> echoes patched JSON
#   extract_pr_merges_from_log <log_text>        -> echoes one PR-merge subject per line

# ---------- validate_version_format ----------

validate_version_format() {
  local version="$1"
  [ -n "$version" ] || return 1
  echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# ---------- version_greater_than ----------
#
# Numeric (not lexical) compare of two semver MAJOR.MINOR.PATCH strings.
# Returns 0 iff $1 > $2.

version_greater_than() {
  local a="$1" b="$2"
  local a_major a_minor a_patch b_major b_minor b_patch
  a_major=$(echo "$a" | cut -d. -f1)
  a_minor=$(echo "$a" | cut -d. -f2)
  a_patch=$(echo "$a" | cut -d. -f3)
  b_major=$(echo "$b" | cut -d. -f1)
  b_minor=$(echo "$b" | cut -d. -f2)
  b_patch=$(echo "$b" | cut -d. -f3)

  if [ "$a_major" -gt "$b_major" ]; then return 0; fi
  if [ "$a_major" -lt "$b_major" ]; then return 1; fi
  if [ "$a_minor" -gt "$b_minor" ]; then return 0; fi
  if [ "$a_minor" -lt "$b_minor" ]; then return 1; fi
  if [ "$a_patch" -gt "$b_patch" ]; then return 0; fi
  return 1
}

# ---------- update_readme_test_count ----------
#
# Replaces the `Current state: NNN tests, all green on macOS bash 3.2.` line
# with the new count. Returns 1 if the marker line is missing.

update_readme_test_count() {
  local content="$1" count="$2"
  if ! echo "$content" | grep -q "Current state: [0-9]\\+ tests, all green on macOS bash 3.2."; then
    return 1
  fi
  echo "$content" | sed -E "s/Current state: [0-9]+ tests, all green on macOS bash 3\\.2\\./Current state: ${count} tests, all green on macOS bash 3.2./"
}

# ---------- update_plugin_version ----------
#
# Replaces the `"version": "X.Y.Z"` line in plugin.json content. Returns 1
# if no version field exists.

update_plugin_version() {
  local content="$1" version="$2"
  if ! echo "$content" | grep -q '"version":[[:space:]]*"[^"]*"'; then
    return 1
  fi
  echo "$content" | sed -E "s/\"version\":[[:space:]]*\"[^\"]*\"/\"version\": \"${version}\"/"
}

# ---------- extract_pr_merges_from_log ----------
#
# Filters a `git log --format=%s` output to keep only lines that look like
# PR merges:
#   - GitHub squash-merge style: subject ends with `(#NNN)`
#   - GitHub classic merge commit: subject starts with `Merge pull request #NNN`
# Empty input echoes nothing with status 0.

extract_pr_merges_from_log() {
  local input="$1"
  [ -n "$input" ] || return 0
  echo "$input" | grep -E '\(#[0-9]+\)$|^Merge pull request #[0-9]+' || true
}
