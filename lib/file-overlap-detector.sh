#!/usr/bin/env bash
# file-overlap-detector.sh
# Detect file overlap between sprint tasks and recommend a PR strategy.
#
# Sprint Step 5 calls these helpers to decide whether parallel tasks will
# create cascading merge conflicts. When overlap is found, the user is
# offered three strategies:
#   (a) separate  — current behavior, one PR per task
#   (b) bundled   — cherry-pick all task commits into one integration branch
#   (c) grouped   — one PR per overlap-cluster
#
# Inputs are normalized task JSON objects with a `description` field and
# optional `acceptanceCriteria` array. The detector extracts file paths
# mentioned in those texts as a heuristic for "this task touches X".

# extract_files_from_text <text>
# Pulls likely filesystem paths from arbitrary text. A path is recognised
# as a backtick-quoted string OR a bare token containing a slash and a
# common code/config extension (sh, md, json, ts, js, py, yml, yaml, sql,
# bash, bats). Returns one path per line, sorted unique.
extract_files_from_text() {
  local text="$1"
  printf '%s\n' "$text" \
    | tr '`,()[]{}' '         ' \
    | tr '\n' ' ' \
    | tr ' ' '\n' \
    | grep -E '^[a-zA-Z0-9._/-]+/[a-zA-Z0-9._-]+\.(sh|md|json|ts|tsx|js|jsx|py|yml|yaml|sql|bash|bats)$' \
    | sort -u
}

# extract_files_from_task <task_json>
# Combines description + acceptanceCriteria text and runs the file extractor.
extract_files_from_task() {
  local task_json="$1"
  local combined
  combined="$(echo "$task_json" | jq -r '
    [
      .description // "",
      ((.acceptanceCriteria // []) | join(" "))
    ] | join(" ")
  ')"
  extract_files_from_text "$combined"
}

# compute_overlap <tasks_json>
# Takes a JSON array of tasks and returns a JSON object describing overlap:
#   {
#     "byTask": { "<task-id>": ["file1", "file2", ...] },
#     "overlaps": [
#       { "file": "lib/wizard.sh", "tasks": ["TASK-1", "TASK-2"] }
#     ],
#     "hasOverlap": true|false
#   }
compute_overlap() {
  local tasks="$1"

  # Build the per-task map.
  local by_task='{}'
  local task_id files entry
  while read -r task_id; do
    [ -z "$task_id" ] && continue
    local task_json
    task_json="$(echo "$tasks" | jq --arg id "$task_id" '.[] | select(.id == $id)')"
    files="$(extract_files_from_task "$task_json")"
    if [ -z "$files" ]; then
      entry='[]'
    else
      entry="$(echo "$files" | jq -R . | jq -s .)"
    fi
    by_task="$(echo "$by_task" | jq --arg id "$task_id" --argjson f "$entry" '. + {($id): $f}')"
  done < <(echo "$tasks" | jq -r '.[].id')

  # For each file mentioned in 2+ tasks, build an overlap entry.
  local overlaps
  overlaps="$(echo "$by_task" | jq '
    [
      to_entries
      | map(.value[] as $f | {file: $f, task: .key})
      | flatten
      | group_by(.file)
      | map(select(length > 1) | {file: .[0].file, tasks: (map(.task) | unique)})
    ]
    | flatten
  ')"

  local has_overlap
  if [ "$(echo "$overlaps" | jq 'length')" -gt 0 ]; then
    has_overlap=true
  else
    has_overlap=false
  fi

  jq -n \
    --argjson by_task "$by_task" \
    --argjson overlaps "$overlaps" \
    --argjson has_overlap "$has_overlap" \
    '{byTask: $by_task, overlaps: $overlaps, hasOverlap: $has_overlap}'
}

# group_by_overlap <tasks_json>
# Groups tasks transitively by shared files. Two tasks are in the same group
# if they share at least one file, directly or via a chain. Returns:
#   { "groups": [["TASK-1", "TASK-2"], ["TASK-3"]] }
group_by_overlap() {
  local tasks="$1"
  local overlap_data
  overlap_data="$(compute_overlap "$tasks")"

  # Build adjacency: each pair of tasks sharing a file is connected.
  local task_ids
  task_ids="$(echo "$tasks" | jq -r '.[].id')"

  local edges
  edges="$(echo "$overlap_data" | jq -c '
    [
      .overlaps[]
      | .tasks as $ts
      | range(0; ($ts | length)) as $i
      | range($i+1; ($ts | length)) as $j
      | [$ts[$i], $ts[$j]]
    ]
  ')"

  # Union-find via simple iteration. For each edge, merge groups.
  local groups='[]'
  local id
  for id in $task_ids; do
    groups="$(echo "$groups" | jq --arg id "$id" '. + [[$id]]')"
  done

  local pair a b ai bi
  while read -r pair; do
    [ -z "$pair" ] && continue
    a="$(echo "$pair" | jq -r '.[0]')"
    b="$(echo "$pair" | jq -r '.[1]')"
    ai="$(echo "$groups" | jq --arg id "$a" 'map(any(. == $id)) | index(true)')"
    bi="$(echo "$groups" | jq --arg id "$b" 'map(any(. == $id)) | index(true)')"
    if [ "$ai" != "$bi" ] && [ "$ai" != "null" ] && [ "$bi" != "null" ]; then
      groups="$(echo "$groups" | jq --argjson ai "$ai" --argjson bi "$bi" '
        . as $g
        | [
            .[$ai] + .[$bi],
            (range(0; length) | select(. != $ai and . != $bi) | $g[.])
          ]
      ')"
    fi
  done < <(echo "$edges" | jq -c '.[]')

  jq -n --argjson g "$groups" '{groups: $g}'
}

# recommend_pr_strategy <tasks_json>
# Maps the overlap state to a recommended strategy:
#   - no overlap            -> "separate"
#   - single overlap group  -> "bundled"
#   - multiple overlap grps -> "grouped"
recommend_pr_strategy() {
  local tasks="$1"
  local overlap_data
  overlap_data="$(compute_overlap "$tasks")"

  local has_overlap
  has_overlap="$(echo "$overlap_data" | jq -r '.hasOverlap')"
  if [ "$has_overlap" != "true" ]; then
    echo "separate"
    return 0
  fi

  local grouped
  grouped="$(group_by_overlap "$tasks")"
  local cluster_count
  cluster_count="$(echo "$grouped" | jq '[.groups[] | select(length > 1)] | length')"

  if [ "$cluster_count" -le 1 ]; then
    echo "bundled"
  else
    echo "grouped"
  fi
}
