---
name: autopilot
description: Toggle autopilot mode with deterministic quality gates
---

Manage autopilot mode. Argument received: $ARGUMENTS

## Actions

### If argument is "on":
1. Create file `~/.claude/.autopilot-enabled` with content: `enabled`
2. Confirm with: "Autopilot ENABLED. Quality gates active: test, lint, types, build. Max 5 iterations per cycle. Use `/autopilot off` to disable."
3. Read `~/.claude/skills/autopilot/SKILL.md` and follow the behavioral instructions for the rest of the session

### If argument is "off":
1. Remove `~/.claude/.autopilot-enabled`
2. Remove any state files matching `~/.claude/.autopilot-*.json`
3. Confirm with: "Autopilot DISABLED. Standard interactive mode."

### If argument is "status":
1. Check if `~/.claude/.autopilot-enabled` exists
2. If exists, show active status and look for `.autopilot-*.json` files for ongoing iterations
3. If not, show inactive status

### If no argument:
Show a message with available options: `/autopilot on`, `/autopilot off`, `/autopilot status`
