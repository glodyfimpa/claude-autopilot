---
name: autopilot
description: Toggle autopilot mode with deterministic quality gates
---

Manage autopilot mode. Argument received: $ARGUMENTS

## Actions

### If argument is "on":

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/hooks/detect-stack.sh` to detect the current project stack
2. Create file `~/.claude/.autopilot-enabled` with content: `enabled`
3. Add permission allowlist rules to `~/.claude/settings.local.json` for the detected gate commands:
   - Parse the JSON output from detect-stack.sh (fields: test, lint, types, build)
   - For each non-empty command, add a `Bash(<command>:*)` entry to `permissions.allow` array
   - Also add these universal rules needed by the stop hook: `Bash(git diff:*)`, `Bash(git status:*)`
   - Save the list of added rules to `~/.claude/.autopilot-permissions.json` so they can be removed later
   - If a rule already exists in the allowlist, skip it (don't duplicate)
4. Confirm with a message showing:
   - "Autopilot ENABLED. Quality gates active: test, lint, types, build."
   - "Stack detected: <stack_name>"
   - "Permission rules added: <list of added rules>"
   - "Max 5 iterations per cycle. Use `/autopilot off` to disable."
   - "TIP: For fully autonomous mode, restart with `claude --permission-mode auto`"
5. Read the autopilot skill from the plugin's `skills/autopilot/SKILL.md` and follow the behavioral instructions for the rest of the session

### If argument is "off":

1. Remove `~/.claude/.autopilot-enabled`
2. Remove any state files matching `~/.claude/.autopilot-*.json` EXCEPT `~/.claude/.autopilot-permissions.json` (read it first)
3. Read `~/.claude/.autopilot-permissions.json` to get the list of rules that were added
4. Remove those specific rules from `~/.claude/settings.local.json` `permissions.allow` array
5. Remove `~/.claude/.autopilot-permissions.json`
6. Confirm with: "Autopilot DISABLED. Permission rules removed. Standard interactive mode."

### If argument is "status":

1. Check if `~/.claude/.autopilot-enabled` exists
2. If exists:
   - Show "Autopilot: ACTIVE"
   - Run detect-stack.sh and show detected stack
   - Show permission rules from `~/.claude/.autopilot-permissions.json` if it exists
   - Look for `.autopilot-*.json` state files and show iteration count if any
3. If not: show "Autopilot: INACTIVE"

### If no argument:

Show a message with available options: `/autopilot on`, `/autopilot off`, `/autopilot status`

## Example permission rules by stack

- **node-ts**: `Bash(npm test:*)`, `Bash(npm run lint:*)`, `Bash(npx tsc --noEmit:*)`, `Bash(npm run build:*)`
- **java-maven**: `Bash(mvn test:*)`, `Bash(mvn package:*)`
- **python**: `Bash(pytest:*)`, `Bash(ruff check:*)`, `Bash(pyright:*)`
- **rust**: `Bash(cargo test:*)`, `Bash(cargo clippy:*)`, `Bash(cargo build:*)`
- **go**: `Bash(go test:*)`, `Bash(golangci-lint run:*)`, `Bash(go vet:*)`, `Bash(go build:*)`
