#!/usr/bin/env bash
# lib/task-storage-providers/backlog.sh - Task storage backed by Backlog.md
# directory structure (backlog/tasks/*.md).
#
# Backlog tasks use a richer frontmatter than local-file:
#   id, title, status, assignee, created_date, labels, dependencies,
#   parent_task_id, priority
#
# Acceptance criteria use checkbox format: - [ ] #N text
# Status mapping: "To Do" <-> ready, "In Progress" <-> in_progress, "Done" <-> done

BACKLOG_TASKS_DIR="backlog/tasks"

# Map internal status names to Backlog.md display names
_backlog_status_to_display() {
  case "$1" in
    ready|"To Do")       echo "To Do";;
    in_progress|"In Progress") echo "In Progress";;
    done|"Done")         echo "Done";;
    *)                   echo "$1";;
  esac
}

# Map Backlog.md display names to normalized internal names
_backlog_status_to_normalized() {
  case "$1" in
    "To Do")       echo "ready";;
    "In Progress") echo "in_progress";;
    "Done")        echo "done";;
    *)             echo "$1";;
  esac
}

# Find the task file matching a given ID (case-insensitive).
# Prints the file path on stdout; returns 1 if not found.
_backlog_find_file() {
  local ref="$1"
  local ref_lower
  ref_lower="$(echo "$ref" | tr '[:upper:]' '[:lower:]')"
  if [[ ! -d "$BACKLOG_TASKS_DIR" ]]; then
    return 1
  fi
  local f
  for f in "$BACKLOG_TASKS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    local basename
    basename="$(basename "$f")"
    # File naming: "task-1.3 - Title-slug.md" — the ID prefix is before " - "
    local file_id
    file_id="$(echo "$basename" | sed 's/ - .*//')"
    local file_id_lower
    file_id_lower="$(echo "$file_id" | tr '[:upper:]' '[:lower:]')"
    if [[ "$file_id_lower" == "$ref_lower" ]]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

# Parse a backlog task file into JSON.
_backlog_parse() {
  local file="$1"
  local in_fm=0 fm_done=0
  local id="" title="" status="" priority="" parent=""
  local section="" description="" criteria_csv=""
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $fm_done -eq 0 ]]; then
      if [[ "$line" == "---" ]]; then
        if [[ $in_fm -eq 0 ]]; then
          in_fm=1; continue
        else
          fm_done=1; continue
        fi
      fi
      if [[ $in_fm -eq 1 ]]; then
        case "$line" in
          id:*)             id="${line#id:}";             id="${id# }";;
          title:*)          title="${line#title:}";       title="${title# }";;
          status:*)         status="${line#status:}";     status="${status# }";;
          priority:*)       priority="${line#priority:}"; priority="${priority# }";;
          parent_task_id:*) parent="${line#parent_task_id:}"; parent="${parent# }";;
        esac
        continue
      fi
    fi

    # Strip HTML comments (section markers)
    [[ "$line" =~ ^"<!--" ]] && continue

    # Detect section headers
    case "$line" in
      "## Description")         section="description"; continue;;
      "## Acceptance Criteria")  section="criteria";    continue;;
      "##"*)                    section=""; continue;;
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
        # Match checkbox format: - [ ] #N text  or  - [x] #N text
        if [[ "$line" =~ ^-[[:space:]]+\[.\][[:space:]]+(#[0-9]+[[:space:]]+)?(.+)$ ]]; then
          local item="${BASH_REMATCH[2]}"
          if [[ -z "$criteria_csv" ]]; then
            criteria_csv="$item"
          else
            criteria_csv="${criteria_csv}|||${item}"
          fi
        fi
        ;;
    esac
  done < "$file"

  # Normalize status
  local norm_status
  norm_status="$(_backlog_status_to_normalized "$status")"

  jq -n \
    --arg id "$id" \
    --arg title "$title" \
    --arg description "$description" \
    --arg status "$norm_status" \
    --arg priority "$priority" \
    --arg parent "$parent" \
    --arg criteria_raw "$criteria_csv" \
    '{
      id: $id,
      title: $title,
      description: $description,
      status: $status,
      priority: $priority,
      parent: (if $parent == "" then null else $parent end),
      acceptanceCriteria: (
        if $criteria_raw == "" then []
        else ($criteria_raw | split("|||"))
        end
      )
    }'
}

task_storage_backlog_fetch() {
  local ref="$1"
  local file
  file="$(_backlog_find_file "$ref")"
  if [[ $? -ne 0 ]] || [[ -z "$file" ]]; then
    echo "task not found: $ref" >&2
    return 1
  fi
  _backlog_parse "$file"
}

task_storage_backlog_update_status() {
  local ref="$1"
  local new_status="$2"
  local file
  file="$(_backlog_find_file "$ref")"
  if [[ $? -ne 0 ]] || [[ -z "$file" ]]; then
    echo "task not found: $ref" >&2
    return 1
  fi
  local display_status
  display_status="$(_backlog_status_to_display "$new_status")"
  # Guard: only allow known status values to reach sed
  if ! [[ "$display_status" =~ ^(To\ Do|In\ Progress|Done)$ ]]; then
    echo "invalid status: $new_status" >&2
    return 1
  fi
  sed -i.bak -e "s/^status:.*/status: ${display_status}/" "$file"
  rm -f "${file}.bak"
}

task_storage_backlog_list() {
  if [[ ! -d "$BACKLOG_TASKS_DIR" ]]; then
    echo "[]"
    return 0
  fi
  local items=()
  local f
  for f in "$BACKLOG_TASKS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    items+=("$(_backlog_parse "$f")")
  done
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  printf '%s\n' "${items[@]}" | jq -s '.'
}

task_storage_backlog_create() {
  local title="$1"
  local description="$2"
  local criteria_csv="$3"
  local parent="${4:-}"

  mkdir -p "$BACKLOG_TASKS_DIR"

  local id
  id="task-$(date +%s)$(( RANDOM % 1000 ))"
  local slug
  slug="$(echo "$title" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g' | cut -c1-40)"
  local file="$BACKLOG_TASKS_DIR/${id} - ${slug}.md"

  {
    printf '%s\n' "---"
    printf '%s\n' "id: $(echo "$id" | tr '[:lower:]' '[:upper:]')"
    printf '%s\n' "title: $title"
    printf '%s\n' "status: To Do"
    [[ -n "$parent" ]] && printf '%s\n' "parent_task_id: $parent"
    printf '%s\n' "priority: medium"
    printf '%s\n' "---"
    printf '%s\n' ""
    printf '%s\n' "## Description"
    printf '%s\n' "$description"
    printf '%s\n' ""
    printf '%s\n' "## Acceptance Criteria"
    local IFS=','
    local n=1
    for c in $criteria_csv; do
      c="${c#"${c%%[![:space:]]*}"}"
      c="${c%"${c##*[![:space:]]}"}"
      [[ -n "$c" ]] && printf '%s\n' "- [ ] #${n} ${c}"
      n=$((n + 1))
    done
  } > "$file"

  printf '%s\n' "$file"
}
