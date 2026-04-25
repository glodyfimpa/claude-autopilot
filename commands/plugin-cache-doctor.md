---
name: plugin-cache-doctor
description: Diagnose and repair desync between Claude Code plugin manifest and on-disk cache
---

Diagnose stale or orphan Claude Code plugin installations. Argument received: $ARGUMENTS

When a Claude Code plugin "disappears" from the UI (slash commands stop working, `/plugin list` shows it missing), the root cause is almost always a desync between two sources of truth:

- `~/.claude/plugins/installed_plugins.json` (manifest)
- `~/.claude/plugins/cache/<plugin>/<version>/` (filesystem)

The manifest can point to a commit hash whose cache folder no longer exists, typically after a `git pull` on the plugin's source repo changes the SHA.

## Arguments

- `(no argument)` Run a check + suggest fixes (no execution).
- `--check` Same as no-arg: report only, exit 2 if action is needed.
- `--fix` After confirmation, execute the suggested commands.

## Actions

### Step 1: Load the library

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/plugin-cache-doctor.sh"
```

### Step 2: Run diagnosis

```bash
diagnose_plugins
```

Show the user the human-readable report. For each plugin in the manifest:

- `healthy: <name> -> <path>` — manifest path exists on disk, no action needed
- `stale:   <name> -> <path> (missing)` — manifest references a folder that no longer exists
- `orphan:  <path>` — cache folder with no corresponding manifest entry

If the manifest is missing entirely, surface the error and stop.

### Step 3: Suggest fixes (no-arg or --check)

```bash
suggest_fixes
```

Print the proposed commands without running them. Example output:

```
# stale: remove manifest entry then reinstall
claude plugin install claude-autopilot
# orphan: remove cache folder
rm -rf /Users/.../cache/claude-autopilot/0.1.0
```

If the state is healthy, output is empty and the user is told "no action needed".

### Step 4: Execute fixes (--fix only)

If the argument is `--fix`:

1. Run `doctor_check` first; if exit code is 0, tell the user "no action needed" and stop.
2. Show the planned commands from `suggest_fixes`.
3. Ask for explicit confirmation before executing.
4. For each stale plugin: edit `~/.claude/plugins/installed_plugins.json` to remove the entry, then run `claude plugin install <name>`.
5. For each orphan cache: `rm -rf <path>` (after confirmation).
6. Re-run `doctor_check` and confirm the state is now healthy.

## Notes

- Idempotent: running twice on a healthy state is a no-op.
- The library reads `PLUGINS_ROOT` from the environment if set; otherwise defaults to `~/.claude/plugins`.
- All filesystem mutations require explicit user confirmation. The default mode is read-only.
