#!/usr/bin/env bash
# lib/prd-source-providers/local-file.sh
#
# Reads a PRD from a markdown file in the working directory. Extracts:
#   - title: the first H1 heading (# ...); falls back to the filename stem
#   - description: the full body of the document
#   - context: free-form metadata section (currently empty; providers may
#     evolve this later)

prd_source_local_file_fetch() {
  local ref="$1"
  if [[ -z "$ref" ]]; then
    echo "local-file prd source requires a file path" >&2
    return 1
  fi
  if [[ ! -f "$ref" ]]; then
    echo "prd file not found: $ref" >&2
    return 1
  fi

  local raw
  raw="$(cat "$ref")"

  # Extract the first H1 heading from the document.
  local title=""
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ ^#[[:space:]]+(.+)$ ]]; then
      title="${BASH_REMATCH[1]}"
      break
    fi
  done <<< "$raw"

  # Fall back to the filename stem if no H1 was found.
  if [[ -z "$title" ]]; then
    local base="${ref##*/}"
    title="${base%.*}"
  fi

  jq -n \
    --arg title "$title" \
    --arg description "$raw" \
    --arg source "local-file" \
    --arg ref "$ref" \
    '{
      title: $title,
      description: $description,
      context: "",
      metadata: { source: $source, ref: $ref }
    }'
}
