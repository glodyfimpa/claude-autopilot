#!/usr/bin/env bats
# Tests for lib/prd-source-adapter.sh
#
# Responsibility: read a PRD (Product Requirements Document) from the configured
# source provider and return a normalized JSON object that the decomposition
# step can consume.
#
# Interface:
#   prd_source_fetch <ref>
#     -> { title, description, context, metadata }
#     exit 0 on success, 1 on config error, 2 on stub / not implemented
#
# Known providers: local-file, chat-paste, notion, jira, google-drive

load "../helpers/test_helper"

setup() {
  setup_isolated_tmpdir
  # shellcheck source=/dev/null
  source "$LIB_DIR/config.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/prd-source-adapter.sh"
}

teardown() {
  teardown_isolated_tmpdir
}

# -------- prd_source_validate_provider --------

@test "prd_source_validate_provider accepts known providers" {
  run prd_source_validate_provider "local-file"
  assert_equal "0" "$status"
  run prd_source_validate_provider "chat-paste"
  assert_equal "0" "$status"
  run prd_source_validate_provider "notion"
  assert_equal "0" "$status"
  run prd_source_validate_provider "jira"
  assert_equal "0" "$status"
  run prd_source_validate_provider "google-drive"
  assert_equal "0" "$status"
}

@test "prd_source_validate_provider rejects unknown providers" {
  run prd_source_validate_provider "confluence"
  assert_equal "1" "$status"
  run prd_source_validate_provider ""
  assert_equal "1" "$status"
}

# -------- prd_source_fetch --------

@test "prd_source_fetch fails when no provider is configured" {
  config_init
  run prd_source_fetch "prd/feature.md"
  assert_equal "1" "$status"
  assert_contains "$output" "no prd_source provider configured"
}

@test "prd_source_fetch fails with clear error for unknown provider" {
  config_init
  config_set "prd_source.provider" "confluence"
  run prd_source_fetch "whatever"
  assert_equal "1" "$status"
  assert_contains "$output" "unknown prd_source provider"
}

@test "prd_source_fetch delegates to local-file provider and returns JSON" {
  config_init
  config_set "prd_source.provider" "local-file"
  mkdir -p prd
  cat > prd/feature-x.md <<'EOF'
# Checkout redesign

The current checkout loses 18% of carts on the payment step. We need to
rebuild the flow around a single-page summary with inline validation.

## Context

- Target launch: Q2
- Primary KPI: conversion rate on payment step
- Non-goals: changes to the product catalog
EOF
  run prd_source_fetch "prd/feature-x.md"
  assert_equal "0" "$status"
  local title description_len
  title="$(echo "$output" | jq -r '.title')"
  description_len="$(echo "$output" | jq -r '.description | length')"
  assert_equal "Checkout redesign" "$title"
  [[ "$description_len" -gt 50 ]]
}

@test "prd_source_fetch delegates to chat-paste provider with raw text" {
  config_init
  config_set "prd_source.provider" "chat-paste"
  local prd_text="# Offline mode

Users in low-connectivity regions need the app to queue writes and sync later.

- Android first, iOS later
- No new backend endpoints"
  run prd_source_fetch "$prd_text"
  assert_equal "0" "$status"
  local title
  title="$(echo "$output" | jq -r '.title')"
  assert_equal "Offline mode" "$title"
}

@test "prd_source_fetch returns stub message for notion provider" {
  config_init
  config_set "prd_source.provider" "notion"
  run prd_source_fetch "page-id-123"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

@test "prd_source_fetch returns stub message for jira provider" {
  config_init
  config_set "prd_source.provider" "jira"
  run prd_source_fetch "EPIC-42"
  assert_equal "2" "$status"
  assert_contains "$output" "not yet implemented"
}

# -------- local-file: markdown parsing edge cases --------

@test "local-file provider treats first H1 as title" {
  config_init
  config_set "prd_source.provider" "local-file"
  mkdir -p prd
  cat > prd/doc.md <<'EOF'
Some preamble line.

# The Real Title

Body text.
EOF
  run prd_source_fetch "prd/doc.md"
  assert_equal "0" "$status"
  local title
  title="$(echo "$output" | jq -r '.title')"
  assert_equal "The Real Title" "$title"
}

@test "local-file provider falls back to filename when no H1 is present" {
  config_init
  config_set "prd_source.provider" "local-file"
  mkdir -p prd
  cat > prd/untitled-prd.md <<'EOF'
Just a body, no heading.
EOF
  run prd_source_fetch "prd/untitled-prd.md"
  assert_equal "0" "$status"
  local title
  title="$(echo "$output" | jq -r '.title')"
  assert_equal "untitled-prd" "$title"
}

@test "local-file provider fails when the file does not exist" {
  config_init
  config_set "prd_source.provider" "local-file"
  run prd_source_fetch "prd/missing.md"
  assert_equal "1" "$status"
  assert_contains "$output" "not found"
}
