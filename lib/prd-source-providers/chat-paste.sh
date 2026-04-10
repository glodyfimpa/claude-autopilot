#!/usr/bin/env bash
# lib/prd-source-providers/chat-paste.sh
#
# "Paste-in-chat" PRD source: the caller passes the full PRD text as the ref.
# Title extraction:
#   - prefer a leading "# ..." H1
#   - otherwise the first non-empty line

prd_source_chat_paste_fetch() {
  local ref="$1"
  if [[ -z "$ref" ]]; then
    echo "chat-paste prd source requires the PRD text as its argument" >&2
    return 1
  fi

  local title=""
  local first_nonempty=""
  local line
  while IFS= read -r line; do
    if [[ -z "$first_nonempty" && -n "$line" ]]; then
      first_nonempty="$line"
    fi
    if [[ "$line" =~ ^#[[:space:]]+(.+)$ ]]; then
      title="${BASH_REMATCH[1]}"
      break
    fi
  done <<< "$ref"

  if [[ -z "$title" ]]; then
    title="${first_nonempty:-Untitled PRD}"
  fi

  jq -n \
    --arg title "$title" \
    --arg description "$ref" \
    --arg source "chat-paste" \
    '{
      title: $title,
      description: $description,
      context: "",
      metadata: { source: $source }
    }'
}
