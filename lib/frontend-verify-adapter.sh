#!/usr/bin/env bash
# lib/frontend-verify-adapter.sh - Dispatcher for frontend verification.
#
# Frontend verification providers run browser-based checks (console errors,
# network failures, accessibility violations) against the implementation.
# Only relevant for web UI projects. The active provider lives in
# frontend_verify.provider in .autopilot-pipeline.json.
#
# Depends on lib/config.sh and lib/adapter-base.sh being sourced first.

FRONTEND_VERIFY_ADAPTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_VERIFY_PROVIDERS_DIR="$FRONTEND_VERIFY_ADAPTER_SELF_DIR/frontend-verify-providers"
FRONTEND_VERIFY_CURRENT_PROVIDER=""

# shellcheck source=/dev/null
source "$FRONTEND_VERIFY_ADAPTER_SELF_DIR/known-providers.sh"
# shellcheck source=/dev/null
source "$FRONTEND_VERIFY_ADAPTER_SELF_DIR/adapter-base.sh"

frontend_verify_validate_provider() {
  adapter_validate_provider "$FRONTEND_VERIFY_KNOWN_PROVIDERS" "$1"
}

_frontend_verify_dispatch() {
  adapter_dispatch \
    "FRONTEND_VERIFY" \
    "frontend_verify" \
    "frontend_verify.provider" \
    "$FRONTEND_VERIFY_KNOWN_PROVIDERS" \
    "$FRONTEND_VERIFY_PROVIDERS_DIR" \
    "frontend_verify" \
    "$@"
}

frontend_verify_run() { _frontend_verify_dispatch "run" "$@"; }
