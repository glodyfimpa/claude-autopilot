#!/usr/bin/env bash
# lib/complexity-estimator.sh - Heuristic first-pass complexity scorer.
#
# Input: a task JSON object (stdin or argument) with at least:
#   { title, description, acceptanceCriteria: [...] }
#
# Output: JSON { tier, score, signals: { criteriaCount, descriptionWords } }
#
# Tier thresholds (configurable via the four globals below so callers can
# override them from .autopilot-pipeline.json once the wizard is in place):
#
#   trivial:  criteria <= TRIVIAL_CRIT  AND words <= TRIVIAL_WORDS
#   standard: criteria <= STANDARD_CRIT AND words <= STANDARD_WORDS
#   complex:  criteria <= COMPLEX_CRIT  OR  words >  STANDARD_WORDS
#   epic:     criteria >  COMPLEX_CRIT
#
# The rules are deliberately simple. A second-pass LLM refinement (Phase 4.5)
# can adjust the tier if it spots dependencies or architectural hints in the
# body that the heuristic cannot see.

: "${CE_TRIVIAL_CRIT:=2}"
: "${CE_TRIVIAL_WORDS:=25}"
: "${CE_STANDARD_CRIT:=5}"
: "${CE_STANDARD_WORDS:=150}"
: "${CE_COMPLEX_CRIT:=10}"

# Count words in a string using awk (POSIX), portable across macOS/Linux.
_ce_word_count() {
  if [[ -z "$1" ]]; then
    echo "0"
    return
  fi
  printf '%s' "$1" | awk '{ total += NF } END { print total + 0 }'
}

estimate_complexity() {
  local task_json="$1"
  if [[ -z "$task_json" ]]; then
    # Allow reading from stdin if no arg was provided.
    task_json="$(cat)"
  fi

  # Validate input as JSON.
  if ! printf '%s' "$task_json" | jq -e . >/dev/null 2>&1; then
    echo "invalid task JSON passed to estimate_complexity" >&2
    return 1
  fi

  local criteria_count description
  criteria_count="$(printf '%s' "$task_json" | jq -r '(.acceptanceCriteria // []) | length')"
  description="$(printf '%s' "$task_json" | jq -r '.description // ""')"

  local word_count
  word_count="$(_ce_word_count "$description")"

  local tier score
  if (( criteria_count > CE_COMPLEX_CRIT )); then
    tier="epic"
  elif (( criteria_count > CE_STANDARD_CRIT )); then
    tier="complex"
  elif (( word_count > CE_STANDARD_WORDS )); then
    tier="complex"
  elif (( criteria_count > CE_TRIVIAL_CRIT )) || (( word_count > CE_TRIVIAL_WORDS )); then
    tier="standard"
  else
    tier="trivial"
  fi

  # Score: arbitrary 0-100 mapping useful for sorting/logging.
  score=$(( criteria_count * 5 + word_count / 5 ))
  (( score > 100 )) && score=100

  jq -n \
    --arg tier "$tier" \
    --argjson score "$score" \
    --argjson cc "$criteria_count" \
    --argjson wc "$word_count" \
    '{
      tier: $tier,
      score: $score,
      signals: { criteriaCount: $cc, descriptionWords: $wc }
    }'
}
