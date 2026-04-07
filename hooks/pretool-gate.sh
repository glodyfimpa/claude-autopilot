#!/bin/bash
# PreToolUse hook - security gate
# Reads JSON from stdin, blocks sensitive files and dangerous commands
# Works in two modes:
#   - Autopilot OFF: only blocks .env files (backward compatible)
#   - Autopilot ON: enhanced blocking for credentials, keys, system dirs, destructive commands

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# --- Base gate (always active, even without autopilot) ---
if [[ "$TOOL" == "Edit" ]] || [[ "$TOOL" == "Write" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
  case "$FILE_PATH" in
    *.env|*.env.*) echo "BLOCKED: Cannot edit .env files - modify them manually" >&2; exit 2;;
  esac
fi

# If autopilot is not active, stop here
if [[ ! -f "$HOME/.claude/.autopilot-enabled" ]]; then
  exit 0
fi

# --- Autopilot active: enhanced gates ---

# Gate for Edit/Write: block credential and system files
if [[ "$TOOL" == "Edit" ]] || [[ "$TOOL" == "Write" ]]; then
  case "$FILE_PATH" in
    *credentials*|*secret*) echo "BLOCKED: credential file" >&2; exit 2;;
    *.pem|*.key|*id_rsa*) echo "BLOCKED: key/certificate file" >&2; exit 2;;
    */etc/*|*/usr/local/*) echo "BLOCKED: system directory" >&2; exit 2;;
  esac
fi

# Gate for Bash: block destructive commands
if [[ "$TOOL" == "Bash" ]]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
  case "$CMD" in
    *"rm -rf /"*) echo "BLOCKED: destructive rm" >&2; exit 2;;
    *"git push --force"*|*"git push -f "*) echo "BLOCKED: force push" >&2; exit 2;;
    *"DROP TABLE"*|*"DROP DATABASE"*) echo "BLOCKED: destructive SQL" >&2; exit 2;;
    *"chmod 777"*) echo "BLOCKED: insecure permissions" >&2; exit 2;;
    *"curl"*"|"*"bash"*|*"curl"*"|"*"sh"*) echo "BLOCKED: pipe to shell" >&2; exit 2;;
  esac
fi

exit 0
