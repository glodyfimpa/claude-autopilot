#!/usr/bin/env bash
# plugin-cache-doctor.sh
# Diagnose desync between ~/.claude/plugins/installed_plugins.json (manifest)
# and ~/.claude/plugins/cache/<plugin>/<version>/ (filesystem).
#
# Override target via PLUGINS_ROOT env var (used by tests).
#
# Real manifest schema:
#   .plugins[<plugin-id>] = [
#     { "scope": "user|project", "installPath": "<abs path>", "version": "...",
#       "projectPath": "...", "gitCommitSha": "...", ... }
#   ]
# A plugin can have multiple install records (e.g. one per scope). Each record
# has its own installPath; we treat each record independently when classifying
# healthy vs stale.

_plugins_root() {
  if [ -n "${PLUGINS_ROOT:-}" ]; then
    echo "$PLUGINS_ROOT"
  else
    echo "$HOME/.claude/plugins"
  fi
}

_manifest_path() {
  echo "$(_plugins_root)/installed_plugins.json"
}

_cache_root() {
  echo "$(_plugins_root)/cache"
}

# Emit lines "<name>\t<installPath>" for every install record in the manifest.
_iter_manifest_records() {
  local manifest="$1"
  jq -r '
    .plugins // {}
    | to_entries[]
    | .key as $name
    | (.value
       | (if type == "array" then . else [.] end)
       | .[]
       | (.installPath // .path // empty)
       | "\($name)\t\(.)"
      )
  ' "$manifest"
}

# diagnose_plugins
# Human-readable scan. Prints one line per plugin/cache entry tagged
# healthy / stale / orphan. Returns 1 if the manifest is missing.
diagnose_plugins() {
  local manifest cache_root
  manifest="$(_manifest_path)"
  cache_root="$(_cache_root)"

  if [ ! -f "$manifest" ]; then
    echo "manifest not found: $manifest"
    return 1
  fi

  local plugin_count
  plugin_count="$(jq '.plugins | length' "$manifest" 2>/dev/null || echo 0)"

  if [ "$plugin_count" = "0" ]; then
    echo "no plugins in manifest"
  else
    local line name path
    while IFS=$'\t' read -r name path; do
      [ -z "$name" ] && continue
      if [ -d "$path" ]; then
        echo "healthy: $name -> $path"
      else
        echo "stale:   $name -> $path (missing)"
      fi
    done < <(_iter_manifest_records "$manifest")
  fi

  if [ -d "$cache_root" ]; then
    local manifest_paths plugin_dir version_dir clean_path
    manifest_paths="$(_iter_manifest_records "$manifest" | cut -f2-)"
    for plugin_dir in "$cache_root"/*/; do
      [ -d "$plugin_dir" ] || continue
      for version_dir in "$plugin_dir"*/; do
        [ -d "$version_dir" ] || continue
        clean_path="${version_dir%/}"
        if ! echo "$manifest_paths" | grep -Fxq "$clean_path"; then
          echo "orphan:  $clean_path"
        fi
      done
    done
  fi
}

# diagnose_plugins_json
# Machine-readable scan. Prints {healthy, stale, orphans} arrays.
diagnose_plugins_json() {
  local manifest cache_root
  manifest="$(_manifest_path)"
  cache_root="$(_cache_root)"

  if [ ! -f "$manifest" ]; then
    echo '{"healthy":[],"stale":[],"orphans":[],"error":"manifest not found"}'
    return 1
  fi

  local healthy='[]' stale='[]' orphans='[]'
  local name path entry

  while IFS=$'\t' read -r name path; do
    [ -z "$name" ] && continue
    entry="$(jq -n --arg n "$name" --arg p "$path" '{name:$n,path:$p}')"
    if [ -d "$path" ]; then
      healthy="$(echo "$healthy" | jq --argjson e "$entry" '. + [$e]')"
    else
      stale="$(echo "$stale" | jq --argjson e "$entry" '. + [$e]')"
    fi
  done < <(_iter_manifest_records "$manifest")

  if [ -d "$cache_root" ]; then
    local manifest_paths plugin_dir version_dir clean_path
    manifest_paths="$(_iter_manifest_records "$manifest" | cut -f2-)"
    for plugin_dir in "$cache_root"/*/; do
      [ -d "$plugin_dir" ] || continue
      for version_dir in "$plugin_dir"*/; do
        [ -d "$version_dir" ] || continue
        clean_path="${version_dir%/}"
        if ! echo "$manifest_paths" | grep -Fxq "$clean_path"; then
          entry="$(jq -n --arg p "$clean_path" '{path:$p}')"
          orphans="$(echo "$orphans" | jq --argjson e "$entry" '. + [$e]')"
        fi
      done
    done
  fi

  jq -n \
    --argjson h "$healthy" \
    --argjson s "$stale" \
    --argjson o "$orphans" \
    '{healthy:$h,stale:$s,orphans:$o}'
}

# doctor_check
# Dry-run mode. Prints a summary, returns:
#   0 = all healthy (or empty manifest)
#   1 = manifest not found
#   2 = stale or orphan entries found (action needed)
doctor_check() {
  local report
  report="$(diagnose_plugins_json)" || return 1

  local stale_count orphan_count
  stale_count="$(echo "$report" | jq '.stale | length')"
  orphan_count="$(echo "$report" | jq '.orphans | length')"

  if [ "$stale_count" -eq 0 ] && [ "$orphan_count" -eq 0 ]; then
    echo "all healthy"
    return 0
  fi

  echo "$stale_count stale, $orphan_count orphan(s) found"
  if [ "$stale_count" -gt 0 ]; then
    echo "stale entries:"
    echo "$report" | jq -r '.stale[] | "  \(.name) -> \(.path)"'
  fi
  if [ "$orphan_count" -gt 0 ]; then
    echo "orphan caches:"
    echo "$report" | jq -r '.orphans[] | "  \(.path)"'
  fi
  return 2
}

# suggest_fixes
# Prints concrete shell commands the user can run to repair the state.
# No execution — output only. Returns 0 always (advisory).
suggest_fixes() {
  local report
  report="$(diagnose_plugins_json)" || return 1

  local stale orphans
  stale="$(echo "$report" | jq -r '.stale[]?.name')"
  orphans="$(echo "$report" | jq -r '.orphans[]?.path')"

  local name
  for name in $stale; do
    echo "# stale: remove manifest entry then reinstall"
    echo "claude plugin install $name"
  done

  local path
  for path in $orphans; do
    echo "# orphan: remove cache folder"
    echo "rm -rf $path"
  done
}
