#!/usr/bin/env bash
# lib/frontend-verify-providers/none.sh - Opt-out: skip frontend verification.

frontend_verify_none_run() {
  echo "frontend verification skipped (provider: none)"
  printf '{"passed":true,"issues":[],"provider":"none"}\n'
}
