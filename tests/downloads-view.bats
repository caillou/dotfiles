#!/usr/bin/env bats
#
# The Downloads view script: what it runs, in which order, and what it does
# when uv is missing.
#
# Nothing here restarts Finder or writes a .DS_Store: `uv` and `killall` are
# stubs that only log their arguments, and HOME is a temporary directory. The
# module they stand in for has its own tests in tests/test_downloads_view.py.

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_UV="$BATS_TEST_TMPDIR/bin/uv"
  export DOTFILES_KILLALL="$BATS_TEST_TMPDIR/bin/killall"

  UVLOG="$BATS_TEST_TMPDIR/uv.log"
  KILLALLLOG="$BATS_TEST_TMPDIR/killall.log"
  MODULE="$REPO_ROOT/.downloads-view/ensure_downloads_view.py"
  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_62-downloads-view.sh.tmpl"
}

# stub_killall [exit code]
stub_killall() {
  stub killall "$KILLALLLOG" "${1:-0}"
}

# stub_uv [exit code]
stub_uv() {
  stub uv "$UVLOG" "${1:-0}"
}

rendered_script() {
  local script="$BATS_TEST_TMPDIR/downloads-view.sh"
  render --file "$SCRIPT" >"$script"
  printf '%s' "$script"
}

downloads_view() {
  run sh "$(rendered_script)"
}

@test "the script is change-triggered on the module" {
  run grep -c "$(shasum -a 256 "$MODULE" | cut -d ' ' -f 1)" "$(rendered_script)"
  [ "$output" = 1 ]
}

@test "the script runs the module out of the source directory" {
  stub_killall
  stub_uv
  downloads_view
  [ "$status" -eq 0 ]
  [ "$(cat "$UVLOG")" = "uv run --with ds_store python3 $MODULE $HOME/.DS_Store" ]
  [ -f "$MODULE" ]
}

@test "the script restarts Finder before and after the module runs" {
  stub_killall
  stub_uv
  downloads_view
  [ "$status" -eq 0 ]
  [ "$(cat "$KILLALLLOG")" = 'killall Finder
killall Finder' ]
}

@test "a Finder that is not running does not stop the script" {
  stub_killall 1
  stub_uv
  downloads_view
  [ "$status" -eq 0 ]
}

@test "a failing module run aborts the apply, so chezmoi retries it" {
  # chezmoi only records a change-triggered script's hash when it exits 0.
  # Failing here is what makes the next apply write the record again.
  stub_killall
  stub_uv 3
  downloads_view
  [ "$status" -ne 0 ]
}

@test "the script skips with a hint when uv is not installed yet" {
  stub_killall
  export DOTFILES_UV="$BATS_TEST_TMPDIR/bin/absent-uv"
  downloads_view
  [ "$status" -eq 0 ]
  [[ "$output" == *'uv is not installed yet'* ]]
  [[ "$output" == *'chezmoi state delete-bucket --bucket=entryState'* ]]
  [ ! -f "$KILLALLLOG" ]
}

@test "chezmoi never writes the module into the home directory" {
  # The module is repo-only content: dot-prefixed, so chezmoi ignores it.
  chezmoi_config false false false
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$HOME" managed
  [ "$status" -eq 0 ]
  [[ "$output" != *'.downloads-view'* ]]
}

@test "the script writes nothing into the home directory itself" {
  stub_killall
  stub_uv
  downloads_view
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.DS_Store" ]
}
