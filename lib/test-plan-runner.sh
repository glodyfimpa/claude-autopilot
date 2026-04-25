#!/usr/bin/env bash
# test-plan-runner.sh
# Helpers for parsing and classifying the "## Test plan" section of a PR body.
# The autopilot-task command's Step 8.6 calls these to identify which items
# can be executed automatically versus which need manual review.
#
# All functions are pure (no side effects). Execution of the items themselves
# is left to the caller (Claude's main loop), since execution requires
# permission prompts and shell context this library cannot provide.

# extract_test_plan <pr_body>
# Reads a PR body on stdin (or as $1) and emits the lines that belong to the
# "## Test plan" section. The section ends at the next "## " heading or EOF.
extract_test_plan() {
  local body="${1:-$(cat)}"
  echo "$body" | awk '
    /^## Test plan[[:space:]]*$/ { in_section = 1; next }
    /^## / && in_section      { in_section = 0 }
    in_section                { print }
  '
}

# list_unchecked_items <test_plan>
# Emits one line per unchecked item from a test plan section. Strips the
# leading "- [ ] " marker. Empty lines and section headers are ignored.
list_unchecked_items() {
  local plan="${1:-$(cat)}"
  echo "$plan" | awk '
    /^- \[ \] / {
      sub(/^- \[ \] /, "")
      print
    }
  '
}

# classify_item <text>
# Prints "executable" or "manual". An item is classified as executable when
# its text contains any of these signals:
#   - a fenced or inline backtick `<command>` block
#   - a known runner invocation (bats, npm, pytest, gh, jest, cargo, go)
#   - an explicit shell-style invocation (bash <path>, sh <path>, ./<path>)
#   - a path to a bats file (tests/.../*.bats)
classify_item() {
  local text="$1"
  case "$text" in
    *'`'*) echo "executable"; return 0 ;;
    *'bats '*|*'npm test'*|*'npm run '*|*'pytest'*|*'jest'*|*'cargo test'*|*'cargo build'*|*'go test'*|*'go build'*) echo "executable"; return 0 ;;
    *'bash '*|*'sh '*|*'./'*) echo "executable"; return 0 ;;
    *.bats*) echo "executable"; return 0 ;;
    *'gh '*) echo "executable"; return 0 ;;
    *) echo "manual"; return 0 ;;
  esac
}

# extract_command_from_item <text>
# Pulls a runnable command out of an item. Prefers backtick-quoted snippets
# when present; falls back to the whole text otherwise. Returns 1 when the
# item is classified as manual (no command to run).
extract_command_from_item() {
  local text="$1"
  local kind
  kind="$(classify_item "$text")"
  if [ "$kind" != "executable" ]; then
    return 1
  fi

  # Prefer the first backtick-quoted segment when present.
  case "$text" in
    *'`'*)
      echo "$text" | sed -E 's/^[^`]*`([^`]+)`.*/\1/'
      return 0
      ;;
  esac

  # Fall back to the trimmed text.
  echo "$text"
}

# annotate_item <text> <result>
# Builds a markdown checkbox line for the updated PR body.
#   result = "pass"   -> "- [x] <text>"
#   result = "fail"   -> "- [ ] <text> _(failed: see run log)_"
#   result = "manual" -> "- [ ] <text> _(manual review)_"
annotate_item() {
  local text="$1" result="$2"
  case "$result" in
    pass)   echo "- [x] $text" ;;
    fail)   echo "- [ ] $text _(failed: see run log)_" ;;
    manual) echo "- [ ] $text _(manual review)_" ;;
    *)      echo "- [ ] $text"; return 1 ;;
  esac
}
