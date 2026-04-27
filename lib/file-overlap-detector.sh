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

# _task_touches_metric <task_json> <metric>
# Heuristic: does the task description/criteria mention something that
# makes it "touch" a known shared metric line at merge time?
#   metric = "readme_test_count" -> task adds bats tests
#   metric = "plugin_version"    -> task bumps plugin.json
#   metric = "changelog"         -> task is a release task
_task_touches_metric() {
  local task_json="$1" metric="$2"
  local text
  text="$(echo "$task_json" | jq -r '
    [
      .description // "",
      .title // "",
      ((.acceptanceCriteria // []) | join(" "))
    ] | join(" ")
  ')"

  case "$metric" in
    readme_test_count)
      echo "$text" | grep -Eq '(tests/lib/[a-zA-Z0-9._-]+\.bats|\.bats\b|bats test|bats suite)' && return 0
      return 1
      ;;
    plugin_version)
      echo "$text" | grep -Eq '(\.claude-plugin/plugin\.json|plugin\.json)' && return 0
      return 1
      ;;
    changelog)
      echo "$text" | grep -Eiq '(release v?[0-9]+\.[0-9]+\.[0-9]+|^release\b|hotfix v?[0-9])' && return 0
      return 1
      ;;
  esac
  return 1
}

# compute_metric_overlap <tasks_json>
# Detects shared metric lines that 2+ tasks would touch even when they
# don't share source files. Returns:
#   { "metricOverlaps": [ { "line": "...", "tasks": ["T1","T2"] } ] }
compute_metric_overlap() {
  local tasks="$1"

  local known_metrics='[
    {"key":"readme_test_count","line":"README.md: Current state: NNN tests"},
    {"key":"plugin_version","line":".claude-plugin/plugin.json: version field"},
    {"key":"changelog","line":"CHANGELOG.md: top entry"}
  ]'

  local result_overlaps='[]'
  local key line_label task_ids matching_count

  while IFS=$'\t' read -r key line_label; do
    [ -z "$key" ] && continue
    matching_ids='[]'
    while read -r tid; do
      [ -z "$tid" ] && continue
      task_json="$(echo "$tasks" | jq --arg id "$tid" '.[] | select(.id == $id)')"
      if _task_touches_metric "$task_json" "$key"; then
        matching_ids="$(echo "$matching_ids" | jq --arg id "$tid" '. + [$id]')"
      fi
    done < <(echo "$tasks" | jq -r '.[].id')

    matching_count="$(echo "$matching_ids" | jq 'length')"
    if [ "$matching_count" -ge 2 ]; then
      result_overlaps="$(echo "$result_overlaps" | jq \
        --arg line "$line_label" \
        --argjson ts "$matching_ids" \
        '. + [{line: $line, tasks: $ts}]')"
    fi
  done < <(echo "$known_metrics" | jq -r '.[] | "\(.key)\t\(.line)"')

  jq -n --argjson m "$result_overlaps" '{metricOverlaps: $m}'
}

# compute_overlap <tasks_json>
# Takes a JSON array of tasks and returns a JSON object describing overlap:
#   {
#     "byTask": { "<task-id>": ["file1", "file2", ...] },
#     "overlaps": [
#       { "file": "lib/wizard.sh", "tasks": ["TASK-1", "TASK-2"] }
#     ],
#     "metricOverlaps": [
#       { "line": "README.md: Current state: NNN tests", "tasks": ["T1","T2"] }
#     ],
#     "hasOverlap": true|false      # true if EITHER overlaps OR metricOverlaps is non-empty
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

  # Metric overlap (shared lines that 2+ tasks would touch even without
  # sharing source files: README test count, plugin.json version, CHANGELOG).
  local metric_overlaps_obj metric_overlaps
  metric_overlaps_obj="$(compute_metric_overlap "$tasks")"
  metric_overlaps="$(echo "$metric_overlaps_obj" | jq '.metricOverlaps')"

  local file_overlap_count metric_overlap_count
  file_overlap_count="$(echo "$overlaps" | jq 'length')"
  metric_overlap_count="$(echo "$metric_overlaps" | jq 'length')"

  local has_overlap
  if [ "$file_overlap_count" -gt 0 ] || [ "$metric_overlap_count" -gt 0 ]; then
    has_overlap=true
  else
    has_overlap=false
  fi

  jq -n \
    --argjson by_task "$by_task" \
    --argjson overlaps "$overlaps" \
    --argjson metric_overlaps "$metric_overlaps" \
    --argjson has_overlap "$has_overlap" \
    '{byTask: $by_task, overlaps: $overlaps, metricOverlaps: $metric_overlaps, hasOverlap: $has_overlap}'
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
#   - no overlap                                       -> "separate"
#   - single file-overlap cluster                      -> "bundled"
#   - multiple disjoint file-overlap clusters          -> "grouped"
#   - file-overlap empty AND metric-overlap non-empty  -> "bundled"
#     (cascading conflicts on shared metric lines like README test count)
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

  local file_overlap_count metric_overlap_count
  file_overlap_count="$(echo "$overlap_data" | jq '.overlaps | length')"
  metric_overlap_count="$(echo "$overlap_data" | jq '.metricOverlaps | length')"

  # No file overlap but metric overlap present: bundling avoids the
  # cascading single-line merge conflicts (e.g. README test count).
  if [ "$file_overlap_count" -eq 0 ] && [ "$metric_overlap_count" -gt 0 ]; then
    echo "bundled"
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
