---
name: autopilot
description: Autopilot mode with deterministic quality gates. Loaded when user activates /autopilot on
---

# Autopilot Mode

When autopilot is active, follow this workflow:

## Work cycle
1. ANALYZE the task before writing code (read relevant files, understand context)
2. PLAN the changes (files to modify, order, dependencies between files)
3. IMPLEMENT in logical, coherent blocks
4. The Stop hook will automatically verify: test, lint, types, build
5. If the stop hook blocks you, read the error and fix the specific problem
6. After all gates pass, launch the security-reviewer agent: "use a security-reviewer subagent to check the changes"
7. Create a commit with a descriptive message

## Operating rules
- Work autonomously: implement, verify, fix without asking confirmation for code operations
- The hook system protects you from dangerous operations (you cannot touch .env, credentials, etc.)
- If you reach the 5-iteration limit without passing the gates, STOP and clearly explain what is failing
- Use subagents for investigations that require reading many files (protect the main context)
- If context fills up, use /compact to free space
- Never skip gates: if tests don't exist, create them before implementing the feature
