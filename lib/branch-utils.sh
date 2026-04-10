#!/usr/bin/env bash
# lib/branch-utils.sh - Echofold-style branch naming and creation
#
# Branch convention (from Echofold's autonomous development pipeline):
#   feat/{PROJECT}-{ticket}-{slug}   for features
#   fix/{PROJECT}-{ticket}-{slug}    for bugfixes
#
# Branches are always created from main. Slugs are kebab-cased versions of the
# task title, bounded to 40 characters.

BRANCH_SLUG_MAX=40

# slugify <title>
#   Transform a free-form title into a kebab-case slug bounded by
#   BRANCH_SLUG_MAX. Returns "untitled" for empty input.
#
# iconv falls back to the raw input when TRANSLIT is unavailable; the
# subsequent tr + sed still strips anything that isn't [a-z0-9-].
slugify() {
  local input="$1"
  local slug
  slug="$(printf '%s' "$input" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$input")"
  slug="$(printf '%s' "$slug" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
  if [[ ${#slug} -gt $BRANCH_SLUG_MAX ]]; then
    slug="${slug:0:$BRANCH_SLUG_MAX}"
    slug="${slug%-}"
  fi
  [[ -z "$slug" ]] && slug="untitled"
  printf '%s\n' "$slug"
}

# Build a full branch name from its components.
# Kind must be "feat" or "fix". Ticket may be empty (fallback used).
build_branch_name() {
  local kind="$1"
  local project="$2"
  local ticket="$3"
  local title="$4"

  case "$kind" in
    feat|fix) ;;
    *)
      echo "unsupported kind: $kind (expected feat or fix)" >&2
      return 1
      ;;
  esac

  if [[ -z "$ticket" ]]; then
    # Deterministic fallback when no ticket id is available: short timestamp.
    ticket="t$(date +%s | tail -c 7)"
  fi

  local slug
  slug="$(slugify "$title")"
  printf '%s/%s-%s-%s\n' "$kind" "$project" "$ticket" "$slug"
}

# Infer a project prefix from the current git repository.
# Strategy: basename of the repo's working directory, uppercased,
# trailing '.git' stripped.
infer_project_prefix() {
  local base
  base="$(basename "$(pwd)")"
  base="${base%.git}"
  # Uppercase, replace non-alphanumeric with '-', trim
  base="$(echo "$base" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_-' '-' | sed 's/-*$//' | sed 's/^-*//')"
  if [[ -z "$base" ]]; then
    base="PROJECT"
  fi
  echo "$base"
}

# Create the named branch from main and check it out.
# Idempotent: if the branch already exists, just check it out.
create_branch_from_main() {
  local branch_name="$1"

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "not a git repository" >&2
    return 1
  fi

  # If the branch exists, check it out.
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    git checkout --quiet "$branch_name"
    return 0
  fi

  # Determine the base branch (main preferred, fallback to master).
  local base="main"
  if ! git show-ref --verify --quiet refs/heads/main; then
    if git show-ref --verify --quiet refs/heads/master; then
      base="master"
    else
      echo "neither main nor master branch exists" >&2
      return 1
    fi
  fi

  # Check out base, then create new branch from it.
  git checkout --quiet "$base"
  git checkout --quiet -b "$branch_name"
}
