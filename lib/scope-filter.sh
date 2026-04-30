#!/usr/bin/env bash
# scope-filter.sh — Deterministic scope filtering for autopilot sprints.
# Implements TASK-1777750800005 zero-prompt hand-off contract: tasks with
# scope ambiguities are excluded by rule, never by interactive question.
#
# Public function:
#   scope_filter_apply "$tasks_json" — returns JSON {kept, excluded}.
#
# Rules (conservative — false negatives are preferable to false positives):
#   A — explicit precondition not satisfied (description regex)
#   B — deliverable outside current repo (description regex)
#   C — broken dependency graph (depends on a task not in the input)
#   D — contradictory acceptance criteria (reserved; not yet implemented)

# _matches_rule_a — emit "1" if the task matches Rule A.
# Rule A signals: phrases of the form
#   - "don't build [this] until X"
#   - "wait until N more X have happened"
#   - "blocked until X"
# combined with a hint that the precondition is unmet ("not yet", a
# count target, a future condition). We require BOTH a "don't/wait/blocked
# until" anchor AND a count or "more"/"yet" follow-up to avoid catching
# unrelated "don't add new features" or "don't merge until tested" notes.
_matches_rule_a() {
  local desc="$1"
  local lc
  lc=$(echo "$desc" | tr '[:upper:]' '[:lower:]')
  # Combined anchor + future-condition signal.
  # Anchor patterns:
  #   "don't build .* until"
  #   "do not build .* until"
  #   "wait until"
  #   "blocked until"
  # Future-condition patterns following the anchor on the same paragraph:
  #   "more <noun>", "additional", "have happened", "are completed", a digit followed by "more"
  if echo "$lc" | grep -Eq "(don'?t build[^.]*until|do not build[^.]*until|wait until|blocked until)" \
     && echo "$lc" | grep -Eq "(have happened|are complete|are completed|more |additional|[0-9]+ )"; then
    echo 1
    return 0
  fi
  echo 0
}

# _matches_rule_b — emit "1" if the task targets an external repo.
# Rule B signals: the description AND/OR an acceptance criterion mentions
# a deliverable on a named external project AND the AC text confirms it
# (e.g. "validation report committed under docs/validation/...-report.md"
# or "merged PR on Freelance Compass"). Avoid catching mere mentions
# ("inspired by Freelance Compass last month") by requiring an action verb
# (run, validate, build, deploy, write, commit, deliver) on the external name.
_matches_rule_b() {
  local desc="$1"
  local ac="$2"
  local combined
  combined=$(printf "%s\n%s" "$desc" "$ac" | tr '[:upper:]' '[:lower:]')
  # Action verbs paired with known external project signals or generic
  # "external repo / other project" markers.
  # Known projects (extend as needed): freelance compass, resevo,
  # bnb investment toolkit, life-os.
  local known_projects="freelance compass|resevo|bnb investment toolkit|life-os"
  # Pattern 1: action verb on the project (run/validate/build/deploy/etc.)
  #   e.g. "run pipeline on Freelance Compass and write a report"
  if echo "$combined" | grep -Eq "(run|validate|build|deploy|write|commit|deliver)[^.]*\b(${known_projects})" \
     && echo "$combined" | grep -Eq "(report|deliverable|pr on|on the|end-to-end)"; then
    echo 1
    return 0
  fi
  # Pattern 2: nominalized deliverable on the project (NO verb required)
  #   e.g. "validation report on Freelance Compass"
  if echo "$combined" | grep -Eq "(validation|status|progress|migration|integration|rollout) report on \b(${known_projects})"; then
    echo 1
    return 0
  fi
  echo 0
}

# _matches_rule_c — emit "1" if the task depends on a task not in $all_ids.
# Pure graph check; no regex. $all_ids is a newline-separated list.
_matches_rule_c() {
  local task_json="$1"
  local all_ids="$2"
  local deps dep
  deps=$(echo "$task_json" | jq -r '.dependencies // [] | .[]' 2>/dev/null)
  if [ -z "$deps" ]; then
    echo 0
    return 0
  fi
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    if ! echo "$all_ids" | grep -Fxq "$dep"; then
      echo 1
      return 0
    fi
  done <<EOF
$deps
EOF
  echo 0
}

# scope_filter_apply — public entry point.
# Input: $1 = JSON array of enriched tasks (must include id, description;
#        acceptanceCriteria and dependencies optional).
# Output: JSON {kept: [ids...], excluded: [{id, rule, reason}, ...]}.
scope_filter_apply() {
  local tasks_json="$1"

  # Empty array shortcut.
  local count
  count=$(echo "$tasks_json" | jq 'length')
  if [ "$count" = "0" ]; then
    echo '{"kept":[],"excluded":[]}'
    return 0
  fi

  # Pre-compute the set of all ids for Rule C dependency check.
  local all_ids
  all_ids=$(echo "$tasks_json" | jq -r '.[].id')

  local kept='[]'
  local excluded='[]'
  local i task task_id desc ac_text rule reason matched

  for i in $(seq 0 $((count - 1))); do
    task=$(echo "$tasks_json" | jq -c ".[$i]")
    task_id=$(echo "$task" | jq -r '.id')
    desc=$(echo "$task" | jq -r '.description // ""')
    ac_text=$(echo "$task" | jq -r '.acceptanceCriteria // [] | .[]' 2>/dev/null | tr '\n' ' ')

    matched=0
    rule=""
    reason=""

    if [ "$(_matches_rule_a "$desc")" = "1" ]; then
      matched=1
      rule="A"
      reason="explicit precondition unmet (task description states it should not be built until a future condition is satisfied)"
    elif [ "$(_matches_rule_b "$desc" "$ac_text")" = "1" ]; then
      matched=1
      rule="B"
      reason="deliverable targets a repository or project outside the current working tree"
    elif [ "$(_matches_rule_c "$task" "$all_ids")" = "1" ]; then
      matched=1
      rule="C"
      reason="declared dependency on a task that is not present in the current sprint backlog"
    fi

    if [ "$matched" = "1" ]; then
      excluded=$(echo "$excluded" | jq --arg id "$task_id" --arg rule "$rule" --arg reason "$reason" \
        '. + [{id: $id, rule: $rule, reason: $reason}]')
    else
      kept=$(echo "$kept" | jq --arg id "$task_id" '. + [$id]')
    fi
  done

  jq -n --argjson kept "$kept" --argjson excluded "$excluded" \
    '{kept: $kept, excluded: $excluded}'
}
