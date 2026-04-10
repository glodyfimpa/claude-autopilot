#!/usr/bin/env bash
# lib/task-storage-providers/local-file.sh - Task storage backed by markdown
# files under a tasks/ directory. Each task is a markdown file with YAML
# frontmatter containing: id, title, status, (optional) parent.
#
# Task file format:
#   ---
#   id: task-42
#   title: Add login page
#   status: ready
#   parent: prd-1         # optional
#   ---
#
#   ## Description
#   Free-form text describing the work.
#
#   ## Acceptance Criteria
#   - First criterion
#   - Second criterion

TASK_STORAGE_LOCAL_DIR="tasks"

# Parse a task file and print a JSON representation.
# JSON shape:
#   { id, title, description, status, acceptanceCriteria: [...] }
task_storage_local_file_fetch() {
  local ref="$1"
  if [[ ! -f "$ref" ]]; then
    echo "task file not found: $ref" >&2
    return 1
  fi
  _task_storage_local_file_parse "$ref"
}

task_storage_local_file_update_status() {
  local ref="$1"
  local new_status="$2"
  if [[ ! -f "$ref" ]]; then
    echo "task file not found: $ref" >&2
    return 1
  fi
  # Update the `status:` line inside the frontmatter.
  # Portable sed on macOS: -i requires an argument (empty string).
  sed -i.bak -e "s/^status:.*/status: ${new_status}/" "$ref"
  rm -f "${ref}.bak"
}

# Create a new task file under tasks/. Returns the file path on stdout.
# Usage: task_storage_local_file_create <title> <description> <comma_separated_criteria>
task_storage_local_file_create() {
  local title="$1"
  local description="$2"
  local criteria_csv="$3"
  local parent="${4:-}"

  mkdir -p "$TASK_STORAGE_LOCAL_DIR"

  # Deterministic id: t + epoch seconds + short random suffix
  local id
  id="t$(date +%s)$(( RANDOM % 1000 ))"
  local file="$TASK_STORAGE_LOCAL_DIR/${id}.md"

  {
    echo "---"
    echo "id: $id"
    echo "title: $title"
    echo "status: ready"
    [[ -n "$parent" ]] && echo "parent: $parent"
    echo "---"
    echo ""
    echo "## Description"
    echo "$description"
    echo ""
    echo "## Acceptance Criteria"
    local IFS=','
    for c in $criteria_csv; do
      # Trim leading/trailing whitespace
      c="${c#"${c%%[![:space:]]*}"}"
      c="${c%"${c##*[![:space:]]}"}"
      [[ -n "$c" ]] && echo "- $c"
    done
  } > "$file"

  printf '%s\n' "$file"
}

# List all task files in the tasks/ directory and return them as a JSON array
# of fetched task objects.
task_storage_local_file_list() {
  if [[ ! -d "$TASK_STORAGE_LOCAL_DIR" ]]; then
    echo "[]"
    return 0
  fi
  local items=()
  local f
  for f in "$TASK_STORAGE_LOCAL_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    items+=("$(_task_storage_local_file_parse "$f")")
  done
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  # Combine into a single JSON array
  printf '%s\n' "${items[@]}" | jq -s '.'
}

# --- Internal: YAML frontmatter + sections parser ---
#
# Strategy: two-pass read. First extract the frontmatter block between --- lines,
# then extract sections by header. Keeps the parser simple and testable.
_task_storage_local_file_parse() {
  local file="$1"
  local in_fm=0 fm_done=0
  local id="" title="" status="" parent=""
  local section="" description="" criteria_csv=""
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $fm_done -eq 0 ]]; then
      if [[ "$line" == "---" ]]; then
        if [[ $in_fm -eq 0 ]]; then
          in_fm=1
          continue
        else
          fm_done=1
          continue
        fi
      fi
      if [[ $in_fm -eq 1 ]]; then
        case "$line" in
          id:*)     id="${line#id:}";     id="${id# }";;
          title:*)  title="${line#title:}"; title="${title# }";;
          status:*) status="${line#status:}"; status="${status# }";;
          parent:*) parent="${line#parent:}"; parent="${parent# }";;
        esac
        continue
      fi
    fi
    # Body: detect section headers
    case "$line" in
      "## Description")          section="description"; continue;;
      "## Acceptance Criteria")  section="criteria";    continue;;
      "##"*)                     section=""; continue;;
    esac
    case "$section" in
      description)
        if [[ -n "$line" ]]; then
          if [[ -z "$description" ]]; then
            description="$line"
          else
            description="${description} ${line}"
          fi
        fi
        ;;
      criteria)
        if [[ "$line" =~ ^-[[:space:]]+(.+)$ ]]; then
          local item="${BASH_REMATCH[1]}"
          if [[ -z "$criteria_csv" ]]; then
            criteria_csv="$item"
          else
            criteria_csv="${criteria_csv}|||${item}"
          fi
        fi
        ;;
    esac
  done < "$file"

  # BSD awk does not support multi-char RS, so pass the raw pipe-delimited
  # list to jq and let jq do the splitting + object construction in one call.
  jq -n \
    --arg id "$id" \
    --arg title "$title" \
    --arg description "$description" \
    --arg status "$status" \
    --arg parent "$parent" \
    --arg criteria_raw "$criteria_csv" \
    '{
      id: $id,
      title: $title,
      description: $description,
      status: $status,
      parent: (if $parent == "" then null else $parent end),
      acceptanceCriteria: (
        if $criteria_raw == "" then []
        else ($criteria_raw | split("|||"))
        end
      )
    }'
}
