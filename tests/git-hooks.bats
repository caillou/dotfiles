#!/usr/bin/env bats
#
# Git hooks: the script that installs lefthook's pre-commit hook into the
# checkout. lefthook is a stub that writes the hook file the way the real one
# does, and the source directory is a throwaway repository, so no test goes
# near the repo's own .git.

setup() {
  load helpers
  isolate_home
  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_LEFTHOOK="$BATS_TEST_TMPDIR/bin/lefthook"
  export LEFTHOOK_STUB_LOG="$BATS_TEST_TMPDIR/lefthook.log"
  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_11-git-hooks.sh.tmpl"
}

# stub_lefthook -> a lefthook that logs its working directory and writes the
# hook file where the real one does
stub_lefthook() {
  stub lefthook <<'EOF'
echo "$PWD $*" >>"$LEFTHOOK_STUB_LOG"
[ -z "${LEFTHOOK_STUB_FAIL:-}" ] || { echo "stub: install failed" >&2; exit 1; }
mkdir -p .git/hooks
printf '#!/bin/sh\n# lefthook\n' >.git/hooks/pre-commit
EOF
}

# source_repo -> a throwaway source directory that is a git repository, with
# the templates the script inlines
source_repo() {
  SOURCE_DIR="$BATS_TEST_TMPDIR/source"
  mkdir -p "$SOURCE_DIR"
  cp -R "$REPO_ROOT/.chezmoitemplates" "$SOURCE_DIR/"
  git -C "$SOURCE_DIR" init -q
  # git init leaves a hooks folder of samples; the built-in git the bootstrap
  # uses leaves none, and the script must cope with both.
  rm -rf "$SOURCE_DIR/.git/hooks"
}

# hooks_script -> renders the script against the source directory and runs it
hooks_script() {
  chezmoi_config false false false "$SOURCE_DIR"
  local script="$BATS_TEST_TMPDIR/git-hooks.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

# installs -> how many times the stub was asked to install, 0 when never
installs() {
  [ -f "$LEFTHOOK_STUB_LOG" ] || { echo 0; return; }
  grep -c ' install$' "$LEFTHOOK_STUB_LOG" || true
}

@test "a checkout without the hook gets it, installed from the source directory" {
  stub_lefthook
  source_repo
  hooks_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'installing lefthook'* ]]
  [ "$(cat "$LEFTHOOK_STUB_LOG")" = "$SOURCE_DIR install" ]
  [ -f "$SOURCE_DIR/.git/hooks/pre-commit" ]
}

@test "a checkout that has the hook is left alone, quietly" {
  stub_lefthook
  source_repo
  hooks_script
  hooks_script
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(installs)" = 1 ]
}

@test "a hook someone else wrote is replaced, since lefthook is what commits need" {
  stub_lefthook
  source_repo
  mkdir -p "$SOURCE_DIR/.git/hooks"
  printf '#!/bin/sh\nexit 0\n' >"$SOURCE_DIR/.git/hooks/pre-commit"
  hooks_script
  [ "$status" -eq 0 ]
  [ "$(installs)" = 1 ]
}

@test "a source directory that is not a repository is skipped" {
  stub_lefthook
  SOURCE_DIR="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$SOURCE_DIR"
  cp -R "$REPO_ROOT/.chezmoitemplates" "$SOURCE_DIR/"
  hooks_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'not a git checkout'* ]]
  [ "$(installs)" = 0 ]
}

@test "a missing lefthook is a skip, not a failure" {
  source_repo
  hooks_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'lefthook is not installed'* ]]
}

@test "a failed install says so and does not fail the apply" {
  stub_lefthook
  export LEFTHOOK_STUB_FAIL=1
  source_repo
  hooks_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'lefthook install failed'* ]]
}

@test "lefthook is a core package, so the hook is installed on every Mac" {
  run grep -Fx 'brew "lefthook"' "$REPO_ROOT/.chezmoitemplates/Brewfile"
  [ "$status" -eq 0 ]
}
