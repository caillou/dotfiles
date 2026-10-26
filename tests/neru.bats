#!/usr/bin/env bats
#
# The Neru script: registers Neru's login service once, and leaves a Mac
# without Neru, or with the service already registered, alone. Neru itself
# comes from the Brewfile, which tests/packages.bats covers.
#
# `neru` is a stub that logs its arguments and the launchd folder sits under
# an isolated HOME, so nothing here touches this Mac's services.

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export LOG="$BATS_TEST_TMPDIR/neru.log"
  : >"$LOG"

  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_56-neru.sh.tmpl"
  CONFIG="$REPO_ROOT/dot_config/neru/config.toml"
  PLIST="$HOME/Library/LaunchAgents/com.y3owk1n.neru.plist"
}

# with_neru [exit] -> a neru on the seam that logs its arguments and exits <exit>
with_neru() {
  stub neru '$LOG' "${1:-0}" </dev/null
  export DOTFILES_NERU="$STUB_BIN/neru"
}

apply() {
  local script="$BATS_TEST_TMPDIR/neru.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

@test "without neru the script skips and says the next apply registers the service" {
  export DOTFILES_NERU="$BATS_TEST_TMPDIR/no-such-neru"
  apply
  [ "$status" -eq 0 ]
  [[ "$output" == *'not installed'* ]]
  [ ! -s "$LOG" ]
}

@test "a Mac with neru and no service registers it, once" {
  with_neru
  apply
  [ "$status" -eq 0 ]
  grep -qxF 'neru services install' "$LOG"
  [[ "$output" == *'Accessibility'* ]]
}

@test "a registered service is left alone, silently" {
  with_neru
  mkdir -p "$(dirname "$PLIST")"
  : >"$PLIST"
  apply
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$LOG" ]
}

@test "a failing install says so and does not fail the apply" {
  with_neru 1
  apply
  [ "$status" -eq 0 ]
  [[ "$output" == *'by hand'* ]]
}

@test "the config is a plain dotfile that only overrides defaults" {
  [ -f "$CONFIG" ]
  grep -q '^capture_scope = "screen"$' "$CONFIG"
  grep -q '^\[scroll.hotkeys\]$' "$CONFIG"
  # The hotkeys stay Neru's defaults, ⌘⇧Space for hints among them.
  ! grep -q '^\[hotkeys\]' "$CONFIG"
}
