#!/usr/bin/env bash
# lib/task-storage-providers/chat-paste.sh
#
# "Paste-in-chat" provider: the user provides the task content directly in
# chat. This provider exists so that commands treat chat input uniformly with
# other sources. The "ref" for fetch is the raw task text.
#
# Notes:
#   - update_status is a no-op (returns 0)
#   - create is not supported (return 2)
#   - list is not supported (return 2)

task_storage_chat_paste_fetch() {
  local ref="$1"
  if [[ -z "$ref" ]]; then
    echo "chat-paste fetch requires the task text as its argument" >&2
    return 1
  fi
  # Naive parse: first non-empty line is the title, rest is description.
  local first_line="" remaining=""
  local line found=0
  while IFS= read -r line; do
    if [[ $found -eq 0 && -n "$line" ]]; then
      first_line="$line"
      found=1
      continue
    fi
    if [[ $found -eq 1 ]]; then
      if [[ -z "$remaining" ]]; then
        remaining="$line"
      else
        remaining="${remaining}
${line}"
      fi
    fi
  done <<< "$ref"

  jq -n \
    --arg title "${first_line:-Untitled}" \
    --arg description "$remaining" \
    '{
      id: "chat-paste",
      title: $title,
      description: $description,
      status: "ready",
      parent: null,
      acceptanceCriteria: []
    }'
}

task_storage_chat_paste_update_status() {
  # No-op: chat paste has no persistent storage.
  return 0
}

task_storage_chat_paste_create() {
  echo "chat-paste provider does not support task creation" >&2
  return 2
}

task_storage_chat_paste_list() {
  echo "chat-paste provider does not support task listing" >&2
  return 2
}
