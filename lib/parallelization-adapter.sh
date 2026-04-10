#!/usr/bin/env bash
# lib/parallelization-adapter.sh - Plan how a batch of tasks should execute.
#
# Given an array of tasks (each carrying a `complexity` object and optional
# `files` hint), decide the overall strategy (sequential|parallel), the max
# concurrency cap, and the groups of tasks that must run sequentially inside
# a single lane because of shared-file dependencies.
#
# Depends on lib/config.sh being sourced before this file.
#
# Config keys consumed:
#   parallelization.strategy        adaptive | always-sequential | always-parallel
#   parallelization.max_concurrency integer (default 3)

PARALLEL_DEFAULT_MAX=3

# Union-find: group task indices that share at least one file path.
# Pure bash so we stay portable and avoid shelling out.
_parallel_group_by_files() {
  local tasks_json="$1"
  local n
  n="$(printf '%s' "$tasks_json" | jq 'length')"
  if (( n == 0 )); then
    echo "[]"
    return 0
  fi

  # parent[i] = i initially
  local parent=()
  local i
  for ((i=0; i<n; i++)); do
    parent[i]=$i
  done

  _uf_find() {
    local x=$1
    while [[ "${parent[x]}" != "$x" ]]; do
      parent[x]=${parent[parent[x]]}
      x=${parent[x]}
    done
    echo "$x"
  }
  _uf_union() {
    local a b ra rb
    a=$1; b=$2
    ra="$(_uf_find "$a")"
    rb="$(_uf_find "$b")"
    if [[ "$ra" != "$rb" ]]; then
      parent[ra]=$rb
    fi
  }

  # For each pair (i,j) with i<j, union if they share a file.
  local i j shared
  for ((i=0; i<n; i++)); do
    for ((j=i+1; j<n; j++)); do
      shared="$(printf '%s' "$tasks_json" | jq -r --argjson i "$i" --argjson j "$j" '
        (.[$i].files // []) as $a |
        (.[$j].files // []) as $b |
        ($a | map(. as $x | $b | index($x)) | map(select(. != null)) | length)
      ')"
      if (( shared > 0 )); then
        _uf_union "$i" "$j"
      fi
    done
  done

  # Build groups without associative arrays (bash 3.2 compat).
  # Strategy: for each distinct root (in order of first appearance), scan
  # all tasks whose root matches and collect their ids.
  local seen_roots=()
  local root
  for ((i=0; i<n; i++)); do
    root="$(_uf_find "$i")"
    local already=0 r
    for r in "${seen_roots[@]}"; do
      [[ "$r" == "$root" ]] && { already=1; break; }
    done
    if (( already == 0 )); then
      seen_roots+=("$root")
    fi
  done

  local out="["
  local first=1 r id
  for r in "${seen_roots[@]}"; do
    local items=()
    for ((i=0; i<n; i++)); do
      local ri
      ri="$(_uf_find "$i")"
      if [[ "$ri" == "$r" ]]; then
        id="$(printf '%s' "$tasks_json" | jq -r --argjson i "$i" '.[$i].id')"
        items+=("$id")
      fi
    done
    local group_json
    group_json="$(printf '%s\n' "${items[@]}" | jq -R . | jq -s '.')"
    if (( first == 1 )); then
      out="${out}${group_json}"
      first=0
    else
      out="${out},${group_json}"
    fi
  done
  out="${out}]"
  printf '%s' "$out" | jq -c '.'
}

# Count tasks whose tier is complex or epic.
_parallel_count_heavy() {
  printf '%s' "$1" | jq '[.[] | select(.complexity.tier == "complex" or .complexity.tier == "epic")] | length'
}

# Count tasks whose tier is trivial.
_parallel_count_trivial() {
  printf '%s' "$1" | jq '[.[] | select(.complexity.tier == "trivial")] | length'
}

plan_execution() {
  local tasks_json="$1"
  if [[ -z "$tasks_json" ]]; then
    tasks_json="$(cat)"
  fi
  if ! printf '%s' "$tasks_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "invalid tasks JSON passed to plan_execution" >&2
    return 1
  fi

  local strategy max
  strategy="$(config_get "parallelization.strategy" 2>/dev/null || true)"
  [[ -z "$strategy" ]] && strategy="adaptive"
  max="$(config_get "parallelization.max_concurrency" 2>/dev/null || true)"
  [[ -z "$max" ]] && max="$PARALLEL_DEFAULT_MAX"

  local n
  n="$(printf '%s' "$tasks_json" | jq 'length')"
  if (( n == 0 )); then
    jq -n --argjson max "$max" '{strategy:"sequential", maxConcurrency:$max, groups:[]}'
    return 0
  fi

  case "$strategy" in
    always-sequential)
      local groups
      groups="$(printf '%s' "$tasks_json" | jq -c '[.[] | [.id]]')"
      jq -n --argjson groups "$groups" \
        '{strategy:"sequential", maxConcurrency:1, groups:$groups}'
      return 0
      ;;
    always-parallel)
      local groups
      groups="$(_parallel_group_by_files "$tasks_json")"
      jq -n --argjson groups "$groups" --argjson max "$max" \
        '{strategy:"parallel", maxConcurrency:$max, groups:$groups}'
      return 0
      ;;
    adaptive)
      local heavy trivial
      heavy="$(_parallel_count_heavy "$tasks_json")"
      trivial="$(_parallel_count_trivial "$tasks_json")"
      if (( heavy > 0 )) || (( trivial == n )); then
        # Heavy tasks need full context; trivial batches don't benefit from
        # parallel overhead. Both fall back to sequential.
        local groups
        groups="$(printf '%s' "$tasks_json" | jq -c '[.[] | [.id]]')"
        jq -n --argjson groups "$groups" \
          '{strategy:"sequential", maxConcurrency:1, groups:$groups}'
      else
        local groups
        groups="$(_parallel_group_by_files "$tasks_json")"
        jq -n --argjson groups "$groups" --argjson max "$max" \
          '{strategy:"parallel", maxConcurrency:$max, groups:$groups}'
      fi
      return 0
      ;;
    *)
      echo "unknown parallelization strategy: $strategy" >&2
      return 1
      ;;
  esac
}
