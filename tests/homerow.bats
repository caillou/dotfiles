#!/usr/bin/env bats
#
# Homerow: the login agent that starts it, written by chezmoi and loaded by
# run_after_56-homerow.
#
# Nothing here touches this Mac. HOME is temporary, Applications is a folder
# the test fills in, and `launchctl` is a stub that keeps the loaded labels in
# a file: `print` answers from it, `bootstrap` adds to it, `bootout` removes
# from it. A file next to it makes `bootstrap` fail.

setup() {
  load helpers
  isolate_home
  chezmoi_config false false false

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  export DOTFILES_UID=501
  mkdir -p "$DOTFILES_STATE" "$DOTFILES_APPLICATIONS" "$HOME/Library/LaunchAgents"

  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_56-homerow.sh.tmpl"
  SOURCE_PLIST="$REPO_ROOT/private_Library/LaunchAgents/ch.caillou.homerow.plist"
  PLIST="$HOME/Library/LaunchAgents/ch.caillou.homerow.plist"
  LOADED="$BATS_TEST_TMPDIR/loaded"   # one loaded label per line
  BROKEN="$BATS_TEST_TMPDIR/broken"   # exists while bootstrap fails
  LOG="$BATS_TEST_TMPDIR/commands.log"
  : >"$LOADED"

  stub launchctl "$LOG" <<EOF
case "\$1" in
print) grep -qxF "\${2##*/}" "$LOADED"; exit \$? ;;
bootstrap) [ -e "$BROKEN" ] && exit 5; echo ch.caillou.homerow >>"$LOADED" ;;
bootout) grep -vxF "\${2##*/}" "$LOADED" >"$LOADED.new" || true; mv "$LOADED.new" "$LOADED" ;;
*) exit 99 ;;
esac
EOF
  export DOTFILES_LAUNCHCTL="$STUB_BIN/launchctl"
}

homerow() {
  local script="$BATS_TEST_TMPDIR/homerow.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

installed() {
  mkdir -p "$DOTFILES_APPLICATIONS/Homerow.app/Contents/MacOS"
  cp "$SOURCE_PLIST" "$PLIST"
}

apply_library() {
  chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$HOME" \
    apply --exclude scripts "$HOME/Library"
}

says() { [[ "$output" == *"$1"* ]]; }
ran() { grep -qF "$1" "$LOG"; }

# --- the agent file ----------------------------------------------------------

@test "an apply writes the agent into LaunchAgents, and it is a valid plist" {
  run apply_library
  [ "$status" -eq 0 ]
  [ -f "$PLIST" ]
  run plutil -lint "$PLIST"
  [ "$status" -eq 0 ]
  run plutil -extract Label raw "$PLIST"
  [ "$output" = "ch.caillou.homerow" ]
  run plutil -extract RunAtLoad raw "$PLIST"
  [ "$output" = "true" ]
  run plutil -extract ProgramArguments json -o - "$PLIST"
  [ "$output" = '["\/usr\/bin\/open","-g","-a","Homerow"]' ]
}

@test "the agent file is not a template, so chezmoi re-add works on it" {
  [[ "$SOURCE_PLIST" != *.tmpl ]]
  run grep -c '{{' "$SOURCE_PLIST"
  [ "$output" = 0 ]
}

# --- loading it ----------------------------------------------------------------

@test "without Homerow nothing is run and nothing is said" {
  cp "$SOURCE_PLIST" "$PLIST"
  homerow
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$LOG" ]
}

@test "the first apply loads the agent, which launches Homerow" {
  installed
  homerow
  [ "$status" -eq 0 ]
  ran "launchctl bootstrap gui/501 $PLIST"
  ! ran "launchctl bootout"
  grep -qxF ch.caillou.homerow "$LOADED"
  says 'Homerow launched'
  says 'Accessibility'
  [ -f "$DOTFILES_STATE/homerow-agent.hash" ]
}

@test "a loaded agent with an unchanged file is left alone, quietly" {
  installed
  homerow
  : >"$LOG"
  homerow
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! ran "launchctl bootstrap"
  ! ran "launchctl bootout"
}

@test "an edited agent file is unloaded and loaded again" {
  installed
  homerow
  : >"$LOG"
  sed -i '' 's/<string>-g<\/string>/<string>-g<\/string><string>-j<\/string>/' "$PLIST"
  homerow
  [ "$status" -eq 0 ]
  ran "launchctl bootout gui/501/ch.caillou.homerow"
  ran "launchctl bootstrap gui/501 $PLIST"
  says 'Homerow launched'
}

@test "a bootstrap that fails is reported, does not fail the apply, and is retried" {
  installed
  : >"$BROKEN"
  homerow
  [ "$status" -eq 0 ]
  says 'could not load the login agent'
  says "launchctl bootstrap gui/501 $PLIST"
  [ ! -f "$DOTFILES_STATE/homerow-agent.hash" ]

  rm "$BROKEN"
  : >"$LOG"
  homerow
  ran "launchctl bootstrap gui/501 $PLIST"
  says 'Homerow launched'
}

@test "a missing agent file is reported and the apply continues" {
  mkdir -p "$DOTFILES_APPLICATIONS/Homerow.app/Contents/MacOS"
  homerow
  [ "$status" -eq 0 ]
  says 'is missing'
  [ ! -f "$LOG" ]
}
