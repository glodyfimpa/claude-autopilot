# Claude Autopilot

Toggleable autopilot mode for Claude Code with deterministic quality gates. Stack-agnostic: works on any project (Node/TypeScript, Java/Maven, Python, Rust, Go).

Inspired by [Echofold's autonomous development pipeline](https://echofold.ai/news/how-to-automate-claude-code-autonomous-development).

## Usage

```
/autopilot on      # Enable autopilot mode
/autopilot off     # Disable autopilot mode
/autopilot status  # Show current state
```

## Quality Gates

When autopilot is enabled, the Stop hook blocks Claude from finishing until all gates pass:

| Gate | What it checks |
|------|---------------|
| **Test** | Runs the project's test suite |
| **Lint** | Checks code style and linting rules |
| **Types** | Verifies type correctness (TypeScript, Python type checkers) |
| **Build** | Ensures the project compiles/builds |

If a gate fails, Claude receives the error output and attempts to fix it automatically. After 5 failed iterations, Claude stops and asks for help.

## Stack Detection

The plugin auto-detects the project stack from the working directory:

| Stack | Detection | Test | Lint | Types | Build |
|-------|-----------|------|------|-------|-------|
| Node/TypeScript | `tsconfig.json` + `package.json` | `npm test` | `npm run lint` | `npx tsc --noEmit` | `npm run build` |
| Node/JavaScript | `package.json` | `npm test` | `npm run lint` | - | `npm run build` |
| Java/Maven | `pom.xml` | `mvn test -q` | - | - | `mvn package -q -DskipTests` |
| Java/Gradle | `build.gradle` | `./gradlew test` | - | - | `./gradlew build -x test` |
| Python | `pyproject.toml` / `setup.py` | `pytest` | `ruff` / `flake8` | `pyright` / `mypy` | - |
| Rust | `Cargo.toml` | `cargo test` | `cargo clippy` | - | `cargo build` |
| Go | `go.mod` | `go test ./...` | `golangci-lint run` | `go vet ./...` | `go build ./...` |

## Security Gates (PreToolUse)

The PreToolUse hook blocks dangerous operations:

- **Always active:** blocks editing `.env` files
- **With autopilot ON:** also blocks credential files (`.pem`, `.key`, `id_rsa`), system directories (`/etc/`, `/usr/local/`), and destructive commands (`rm -rf /`, `git push --force`, `DROP TABLE`, `chmod 777`, `curl | bash`)

## Coexistence with Ralph Loop

When Ralph Loop is active in the same session, the autopilot defers automatically. Both plugins can be enabled simultaneously without conflicts.

## Installation

Add to your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-autopilot": {
      "source": {
        "source": "github",
        "repo": "glodyfimpa/claude-autopilot"
      }
    }
  }
}
```

Then enable via `/plugin`.

## License

MIT
