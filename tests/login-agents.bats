#!/usr/bin/env bats
#
# Login agents: the launch agents that start Homerow and Maccy, written by
# chezmoi and loaded by run_after_56-login-agents.
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

  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_56-login-agents.sh.tmpl"
  SOURCE_AGENTS="$REPO_ROOT/private_Library/LaunchAgents"
  AGENTS="$HOME/Library/LaunchAgents"
  HOMEROW="$AGENTS/ch.caillou.homerow.plist"
  MACCY="$AGENTS/ch.caillou.maccy.plist"
  LOADED="$BATS_TEST_TMPDIR/loaded"   # one loaded label per line
  BROKEN="$BATS_TEST_TMPDIR/broken"   # exists while bootstrap fails
  LOG="$BATS_TEST_TMPDIR/commands.log"
  : >"$LOADED"

  stub launchctl "$LOG" <<EOF
case "\$1" in
print) grep -qxF "\${2##*/}" "$LOADED"; exit \$? ;;
bootstrap) [ -e "$BROKEN" ] && exit 5; label="\${3##*/}"; echo "\${label%.plist}" >>"$LOADED" ;;
bootout) grep -vxF "\${2##*/}" "$LOADED" >"$LOADED.new" || true; mv "$LOADED.new" "$LOADED" ;;
*) exit 99 ;;
esac
EOF
  export DOTFILES_LAUNCHCTL="$STUB_BIN/launchctl"
}

agents() {
  local script="$BATS_TEST_TMPDIR/login-agents.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

# installed Homerow|Maccy -> the bundle, plus the agent file an apply writes
installed() {
  local label
  label="ch.caillou.$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  mkdir -p "$DOTFILES_APPLICATIONS/$1.app/Contents/MacOS"
  cp "$SOURCE_AGENTS/$label.plist" "$AGENTS/$label.plist"
}

apply_library() {
  chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$HOME" \
    apply --exclude scripts "$HOME/Library"
}

says() { [[ "$output" == *"$1"* ]]; }
ran() { grep -qF "$1" "$LOG"; }

# --- the agent files ---------------------------------------------------------

# agent_is <plist> <label> <app> -> the file is a valid agent that opens <app>
agent_is() {
  run plutil -lint "$1"
  [ "$status" -eq 0 ]
  run plutil -extract Label raw "$1"
  [ "$output" = "$2" ]
  run plutil -extract RunAtLoad raw "$1"
  [ "$output" = "true" ]
  run plutil -extract ProgramArguments json -o - "$1"
  [ "$output" = "[\"\\/usr\\/bin\\/open\",\"-g\",\"-a\",\"$3\"]" ]
}

@test "an apply writes both agents into LaunchAgents when Maccy is there, valid plists" {
  mkdir -p "$DOTFILES_APPLICATIONS/Maccy.app"
  run apply_library
  [ "$status" -eq 0 ]
  agent_is "$HOMEROW" ch.caillou.homerow Homerow
  agent_is "$MACCY" ch.caillou.maccy Maccy
}

@test "without Maccy an apply writes Homerow's agent only" {
  run apply_library
  [ "$status" -eq 0 ]
  agent_is "$HOMEROW" ch.caillou.homerow Homerow
  [ ! -e "$MACCY" ]
}

@test "the agent files are not templates, so chezmoi re-add works on them" {
  for plist in "$SOURCE_AGENTS"/*; do
    [[ "$plist" != *.tmpl ]]
    run grep -c '{{' "$plist"
    [ "$output" = 0 ]
  done
}

# --- loading them --------------------------------------------------------------

@test "without either app nothing is run and nothing is said" {
  cp "$SOURCE_AGENTS"/*.plist "$AGENTS/"
  agents
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$LOG" ]
}

@test "the first apply loads Homerow's agent, which launches Homerow" {
  installed Homerow
  agents
  [ "$status" -eq 0 ]
  ran "launchctl bootstrap gui/501 $HOMEROW"
  ! ran "launchctl bootout"
  ! ran "ch.caillou.maccy"
  grep -qxF ch.caillou.homerow "$LOADED"
  says 'Homerow launched'
  says 'Accessibility'
  ! says 'maccy'
  [ -f "$DOTFILES_STATE/homerow-agent.hash" ]
}

@test "the first apply with Maccy loads its agent too, without Homerow's hint" {
  installed Maccy
  agents
  [ "$status" -eq 0 ]
  ran "launchctl bootstrap gui/501 $MACCY"
  ! ran "ch.caillou.homerow"
  grep -qxF ch.caillou.maccy "$LOADED"
  [ "$output" = 'maccy: login agent loaded and Maccy launched' ]
  [ -f "$DOTFILES_STATE/maccy-agent.hash" ]
}

@test "with both apps both agents are loaded" {
  installed Homerow
  installed Maccy
  agents
  [ "$status" -eq 0 ]
  ran "launchctl bootstrap gui/501 $HOMEROW"
  ran "launchctl bootstrap gui/501 $MACCY"
  says 'Homerow launched'
  says 'Maccy launched'
}

@test "loaded agents with unchanged files are left alone, quietly" {
  installed Homerow
  installed Maccy
  agents
  : >"$LOG"
  agents
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! ran "launchctl bootstrap"
  ! ran "launchctl bootout"
}

@test "Homerow's hash from before the script covered Maccy still counts" {
  installed Homerow
  echo ch.caillou.homerow >"$LOADED"
  shasum -a 256 "$HOMEROW" | cut -d ' ' -f 1 >"$DOTFILES_STATE/homerow-agent.hash"
  agents
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! ran "launchctl bootstrap"
}

@test "an edited agent file is unloaded and loaded again, the other one is not" {
  installed Homerow
  installed Maccy
  agents
  : >"$LOG"
  sed -i '' 's/<string>-g<\/string>/<string>-g<\/string><string>-j<\/string>/' "$MACCY"
  agents
  [ "$status" -eq 0 ]
  ran "launchctl bootout gui/501/ch.caillou.maccy"
  ran "launchctl bootstrap gui/501 $MACCY"
  ! ran "ch.caillou.homerow"
  [ "$output" = 'maccy: login agent loaded and Maccy launched' ]
}

@test "a bootstrap that fails is reported, does not fail the apply, and is retried" {
  installed Homerow
  installed Maccy
  : >"$BROKEN"
  agents
  [ "$status" -eq 0 ]
  says 'homerow: could not load the login agent'
  says "launchctl bootstrap gui/501 $HOMEROW"
  says 'maccy: could not load the login agent'
  says "launchctl bootstrap gui/501 $MACCY"
  [ ! -f "$DOTFILES_STATE/homerow-agent.hash" ]
  [ ! -f "$DOTFILES_STATE/maccy-agent.hash" ]

  rm "$BROKEN"
  : >"$LOG"
  agents
  ran "launchctl bootstrap gui/501 $HOMEROW"
  ran "launchctl bootstrap gui/501 $MACCY"
  says 'Homerow launched'
  says 'Maccy launched'
}

@test "a missing agent file is reported and the apply continues" {
  mkdir -p "$DOTFILES_APPLICATIONS/Homerow.app/Contents/MacOS"
  installed Maccy
  agents
  [ "$status" -eq 0 ]
  says "homerow: $HOMEROW is missing"
  ! ran "ch.caillou.homerow"
  ran "launchctl bootstrap gui/501 $MACCY"
}
