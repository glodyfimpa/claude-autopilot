#!/bin/bash
# Detect project stack from current directory and output gate commands as JSON
# Input: optional directory argument (defaults to pwd)
# Output: JSON on stdout
# Example: {"stack":"node-ts","test":"npm test","lint":"npm run lint","types":"npx tsc --noEmit","build":"npm run build"}

DIR="${1:-.}"

# Detection priority (first match wins)
if [[ -f "$DIR/tsconfig.json" ]] && [[ -f "$DIR/package.json" ]]; then
  STACK="node-ts"
  TEST="npm test"
  LINT=""; grep -q '"lint"' "$DIR/package.json" && LINT="npm run lint"
  TYPES="npx tsc --noEmit"
  BUILD=""; grep -q '"build"' "$DIR/package.json" && BUILD="npm run build"
elif [[ -f "$DIR/package.json" ]]; then
  STACK="node-js"
  TEST="npm test"
  LINT=""; grep -q '"lint"' "$DIR/package.json" && LINT="npm run lint"
  TYPES=""
  BUILD=""; grep -q '"build"' "$DIR/package.json" && BUILD="npm run build"
elif [[ -f "$DIR/pom.xml" ]]; then
  STACK="java-maven"
  TEST="mvn test -q"
  LINT=""
  TYPES=""
  BUILD="mvn package -q -DskipTests"
elif [[ -f "$DIR/build.gradle" ]] || [[ -f "$DIR/build.gradle.kts" ]]; then
  STACK="java-gradle"
  TEST="./gradlew test"
  LINT=""
  TYPES=""
  BUILD="./gradlew build -x test"
elif [[ -f "$DIR/pyproject.toml" ]] || [[ -f "$DIR/setup.py" ]] || [[ -f "$DIR/requirements.txt" ]]; then
  STACK="python"
  TEST=""; command -v pytest &>/dev/null && TEST="pytest"
  LINT=""; command -v ruff &>/dev/null && LINT="ruff check ." || { command -v flake8 &>/dev/null && LINT="flake8"; }
  TYPES=""; command -v pyright &>/dev/null && TYPES="pyright" || { command -v mypy &>/dev/null && TYPES="mypy ."; }
  BUILD=""
elif [[ -f "$DIR/Cargo.toml" ]]; then
  STACK="rust"
  TEST="cargo test"
  LINT="cargo clippy"
  TYPES=""
  BUILD="cargo build"
elif [[ -f "$DIR/go.mod" ]]; then
  STACK="go"
  TEST="go test ./..."
  LINT=""; command -v golangci-lint &>/dev/null && LINT="golangci-lint run"
  TYPES="go vet ./..."
  BUILD="go build ./..."
else
  STACK="unknown"
  TEST="" LINT="" TYPES="" BUILD=""
fi

# Output JSON (no jq dependency, manual construction)
printf '{"stack":"%s","test":"%s","lint":"%s","types":"%s","build":"%s"}\n' \
  "$STACK" "$TEST" "$LINT" "$TYPES" "$BUILD"
