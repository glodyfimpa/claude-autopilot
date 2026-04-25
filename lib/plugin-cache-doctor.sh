#!/usr/bin/env bash
# plugin-cache-doctor.sh
# Diagnose desync between ~/.claude/plugins/installed_plugins.json (manifest)
# and ~/.claude/plugins/cache/<plugin>/<version>/ (filesystem).
#
# Override target via PLUGINS_ROOT env var (used by tests).

PLUGINS_ROOT="${PLUGINS_ROOT:-$HOME/.claude/plugins}"

_manifest_path() {
  echo "$PLUGINS_ROOT/installed_plugins.json"
}

_cache_root() {
  echo "$PLUGINS_ROOT/cache"
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
    # For each manifest entry: healthy if path exists, stale otherwise.
    local names
    names="$(jq -r '.plugins | keys[]' "$manifest")"
    local name path
    for name in $names; do
      path="$(jq -r --arg n "$name" '.plugins[$n].path' "$manifest")"
      if [ -d "$path" ]; then
        echo "healthy: $name -> $path"
      else
        echo "stale:   $name -> $path (missing)"
      fi
    done
  fi

  # Orphans: cache folders not referenced by any manifest path.
  if [ -d "$cache_root" ]; then
    local plugin_dir version_dir manifest_paths
    manifest_paths="$(jq -r '.plugins | to_entries[] | .value.path' "$manifest" 2>/dev/null)"
    for plugin_dir in "$cache_root"/*/; do
      [ -d "$plugin_dir" ] || continue
      for version_dir in "$plugin_dir"*/; do
        [ -d "$version_dir" ] || continue
        local clean_path
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

  local names
  names="$(jq -r '.plugins | keys[]?' "$manifest")"
  local name path entry
  for name in $names; do
    path="$(jq -r --arg n "$name" '.plugins[$n].path' "$manifest")"
    entry="$(jq -n --arg n "$name" --arg p "$path" '{name:$n,path:$p}')"
    if [ -d "$path" ]; then
      healthy="$(echo "$healthy" | jq --argjson e "$entry" '. + [$e]')"
    else
      stale="$(echo "$stale" | jq --argjson e "$entry" '. + [$e]')"
    fi
  done

  if [ -d "$cache_root" ]; then
    local manifest_paths plugin_dir version_dir clean_path
    manifest_paths="$(jq -r '.plugins | to_entries[]? | .value.path' "$manifest")"
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
