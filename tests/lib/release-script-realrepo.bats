#!/usr/bin/env bats
# Real-repo smoke test for scripts/release.sh.
#
# WHY THIS FILE EXISTS (separate from release-script.bats):
#
# release-script.bats uses a fake git repo (make_fake_git_repo + a synthetic
# plugin.json + README.md fixture). That fixture lacks anything the real repo
# accumulates over time: a .claude/ directory from Claude Code state files,
# a .vscode/ directory from IDE settings, the actual .gitignore, real bats
# tests, and so on. As a result, the v0.7.0 release attempt on 2026-04-27 was
# the FIRST time scripts/release.sh ever ran against the real repo — and it
# tripped immediately on `ERROR: working tree is not clean. Commit or stash
# changes first.` because an untracked .claude/ directory was present on
# main. The 28 fake-fixture tests had every dirty-tree path covered in
# theory, but none of them exercised the script against a tree that looks
# like the actual claude-autopilot repo.
#
# Fix: clone the real repo into TEST_TMPDIR (so the test never mutates the
# host clone), run the dry-run flow against it, and assert the dirty-tree
# refusal fires for files that would have caused the v0.7.0 incident if not
# for the /.claude/ rule that landed in commit 79728f5.
#
# COST: the clean-clone dry-run path runs `bats tests/lib/` internally. On
# the real suite that is ~60-90s; multiplied across the 3 clean-tree tests
# in this file the smoke test would cost minutes per run. Since the bats
# invocation is unrelated to the dirty-tree check we're smoke-testing, we
# prepend a stub `bats` on PATH for the duration of each test (the stub
# emits a few `ok N` lines so the script's `grep -c "^ok "` still produces
# a non-zero count). The clone is shared across tests via setup_file /
# teardown_file. Total file wall time lands around ~2s with the stub, vs
# ~5min without.

load "../helpers/test_helper"

# ---------- shared clone (one per file, not per test) ----------

setup_file() {
  # Locate the main repo even when running inside a git worktree.
  # `git rev-parse --git-common-dir` resolves to the shared `.git` directory
  # (e.g. <repo>/.git) regardless of whether $PLUGIN_ROOT is the main checkout
  # or a linked worktree. The repo working tree is its parent.
  local common_dir
  common_dir="$(cd "$PLUGIN_ROOT" && git rev-parse --git-common-dir)"
  # `git rev-parse` may return a relative path; normalize.
  if [ "${common_dir#/}" = "$common_dir" ]; then
    common_dir="$PLUGIN_ROOT/$common_dir"
  fi
  REAL_REPO_ROOT="$(cd "$common_dir/.." && pwd)"
  export REAL_REPO_ROOT

  # Stable scratch dir for the whole file (BATS_FILE_TMPDIR is bats-native).
  CLONE_DIR="${BATS_FILE_TMPDIR:-${TMPDIR:-/tmp}}/claude-autopilot-realrepo-clone"
  rm -rf "$CLONE_DIR"
  git clone --quiet --depth=1 "file://$REAL_REPO_ROOT" "$CLONE_DIR"
  export CLONE_DIR

  # Build a `bats` stub that mimics a green run without actually executing
  # the suite (the real suite was already run by the host bats invocation
  # that brought us here — running it again per-test is wasteful, and this
  # file is about preconditions, not bats coverage). The stub lives in a
  # dedicated bin dir so each test can prepend it on PATH.
  BATS_STUB_DIR="${BATS_FILE_TMPDIR:-${TMPDIR:-/tmp}}/release-realrepo-stubs"
  mkdir -p "$BATS_STUB_DIR"
  cat > "$BATS_STUB_DIR/bats" <<'STUB'
#!/usr/bin/env bash
# Test stub: pretend the real bats suite ran and emit 3 green lines so the
# release script's `grep -c "^ok "` returns a positive count.
echo "1..3"
echo "ok 1 stub"
echo "ok 2 stub"
echo "ok 3 stub"
exit 0
STUB
  chmod +x "$BATS_STUB_DIR/bats"
  export BATS_STUB_DIR
}

teardown_file() {
  if [ -n "${CLONE_DIR:-}" ] && [ -d "$CLONE_DIR" ]; then
    rm -rf "$CLONE_DIR"
  fi
}

# Every test starts from a clean clone state: drop any leftover untracked
# files from previous tests (we never touch tracked files, so `git clean -fd`
# is enough — `-x` is intentionally omitted to keep .gitignore semantics).
setup() {
  cd "$CLONE_DIR"
  git clean -fdq
}

# ---------- helpers ----------

# Run release.sh from inside the clone with the bats stub in front of PATH.
# Wrapping it in a function (instead of inlining `PATH=... run "$SCRIPT" ...`)
# keeps the call sites readable and makes it obvious every test goes through
# the same shim.
_run_release() {
  PATH="$BATS_STUB_DIR:$PATH" run "$CLONE_DIR/scripts/release.sh" "$@"
}

# Pick a target version > whatever .claude-plugin/plugin.json currently has.
# Keeps the test resilient to future version bumps on main.
_target_version() {
  local current
  current="$(grep -E '"version":[[:space:]]*"[^"]*"' "$CLONE_DIR/.claude-plugin/plugin.json" \
    | sed -E 's/.*"version":[[:space:]]*"([^"]*)".*/\1/')"
  # Bump the major component so the comparison always passes.
  local major
  major="${current%%.*}"
  echo "$((major + 100)).0.0"
}

# ---------- tests ----------

@test "real-repo: clean clone passes the dirty-tree check (dry-run)" {
  local v
  v="$(_target_version)"
  _run_release "$v" --dry-run --no-edit
  # Dry-run on a clean tree should reach the "Dry-run complete" line. If it
  # exits non-zero here it means the preconditions check is regressing for a
  # reason unrelated to dirtiness (bats failure, missing tag, etc.) — which
  # we still want to fail loudly on, since this is a smoke test.
  if [ "$status" -ne 0 ]; then
    echo "release.sh failed on a clean clone — output below"
    echo "$output"
    return 1
  fi
  echo "$output" | grep -qi "dry-run complete\|dry"
  echo "$output" | grep -qi "$v"
}

@test "real-repo: untracked file outside .gitignore triggers dirty-tree refusal" {
  # This is the canonical "v0.7.0 incident" reproduction: any file the user
  # forgot to commit (or that some side process dropped on the tree) must
  # block the release before it touches plugin.json or runs bats.
  echo "leftover from a prior run" > "$CLONE_DIR/untracked-release-blocker.txt"
  _run_release "$(_target_version)" --dry-run --no-edit
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "working tree is not clean"
  echo "$output" | grep -q "untracked-release-blocker.txt"
}

@test "real-repo: untracked .claude/ file is ignored by dirty-tree check (v0.7.0 fix regression guard)" {
  # The v0.7.0 incident was caused by an untracked .claude/ directory at repo
  # root. Commit 79728f5 ("chore: ignore root .claude/ directory entirely")
  # added `/.claude/` to .gitignore so Claude Code state files never trip
  # the release script again. This test pins that fix: if anyone removes the
  # rule, an untracked .claude/ file will come back into git status output
  # and this test will fail.
  mkdir -p "$CLONE_DIR/.claude"
  echo "{}" > "$CLONE_DIR/.claude/settings.local.json"
  echo "session state" > "$CLONE_DIR/.claude/something-untracked"

  _run_release "$(_target_version)" --dry-run --no-edit
  if [ "$status" -ne 0 ]; then
    echo "release.sh failed despite .claude/ being gitignored — output below"
    echo "$output"
    return 1
  fi
  echo "$output" | grep -qi "dry-run complete\|dry"
}

@test "real-repo: untracked .vscode/ file is ignored by dirty-tree check" {
  # Same regression-guard logic as the .claude/ case: .vscode/ is in
  # .gitignore (see `.vscode/` rule), so an IDE-state file should never
  # flip the dirty-tree check. If someone scopes the rule down (e.g. only
  # `.vscode/launch.json`) this test will fail and surface the regression.
  mkdir -p "$CLONE_DIR/.vscode"
  cat > "$CLONE_DIR/.vscode/settings.json" <<'JSON'
{ "editor.tabSize": 2 }
JSON

  _run_release "$(_target_version)" --dry-run --no-edit
  if [ "$status" -ne 0 ]; then
    echo "release.sh failed despite .vscode/ being gitignored — output below"
    echo "$output"
    return 1
  fi
  echo "$output" | grep -qi "dry-run complete\|dry"
}
