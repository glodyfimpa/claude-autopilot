#!/usr/bin/env bash
# lib/known-providers.sh - Single source of truth for the provider allowlists.
#
# The adapters read their own namespace constant from here, and the wizard +
# mcp-detector read them all to advertise what's available. Adding a new
# provider means editing one line in this file plus creating the provider
# file under the matching lib/<layer>-providers/ directory.

PR_ADAPTER_KNOWN_PROVIDERS="github gitlab bitbucket"
TASK_STORAGE_KNOWN_PROVIDERS="local-file chat-paste notion jira linear backlog"
PRD_SOURCE_KNOWN_PROVIDERS="local-file chat-paste notion jira google-drive"
CODE_QUALITY_KNOWN_PROVIDERS="sonarqube semgrep codeclimate none"
PARALLELIZATION_KNOWN_STRATEGIES="adaptive always-sequential always-parallel"
KNOWN_SIMPLIFY_MODES="auto manual off"
