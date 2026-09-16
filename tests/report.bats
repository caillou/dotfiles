#!/usr/bin/env bats
#
# Manual-steps report: which items the checklist carries for a given machine.
#
# Nothing here touches this Mac. Applications and the state directory are
# temporary directories the tests fill in themselves, `brew` is a stub, and
# HOME and every XDG variable point into the test's own tree, so the report
# cannot read a real marker or a real app.

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  export DOTFILES_BREW="$BATS_TEST_TMPDIR/bin/brew"
  mkdir -p "$DOTFILES_STATE" "$DOTFILES_APPLICATIONS"

  REPORT="$REPO_ROOT/.chezmoiscripts/run_after_90-report.sh.tmpl"
}

# report <managed> <personal> <embedded>  -> runs the rendered script
report() {
  chezmoi_config "${1:-false}" "${2:-false}" "${3:-false}"
  local script="$BATS_TEST_TMPDIR/report.sh"
  render --file "$REPORT" >"$script"
  run sh "$script"
}

# render_apps <managed> <personal> <apps json>  -> the script text, fake table
#
# The app table is replaced so the row-to-line mapping is asserted on data the
# test owns rather than on whatever the real table happens to hold today.
render_apps() {
  chezmoi_config "$1" "$2" false
  render --file "$REPORT" --override-data "$3"
}

# report_apps <managed> <personal>  -> runs the script rendered on FAKE_APPS
report_apps() {
  local script="$BATS_TEST_TMPDIR/report.sh"
  render_apps "$1" "$2" "$FAKE_APPS" >"$script"
  run sh "$script"
}

# installed <app bundle>
installed() {
  mkdir -p "$DOTFILES_APPLICATIONS/$1"
}

# stub_brew_check <exit code>  -> a brew whose `bundle check` names three entries
#
# The stream layout is the contract under test. Real `brew bundle check`
# (Homebrew 6.0.22) writes its entire failure report -- headline, every `→`
# line, footer -- to stderr and leaves stdout empty, and unrelated warnings
# share that stream, so the stub does the same. A report that read stdout, or
# that threw stderr away, would pass against a friendlier stub and then print
# nothing at all on a real Mac.
stub_brew_check() {
  stub brew "$BATS_TEST_TMPDIR/brew.log" "${1:-1}" <<'EOF'
{
  echo "Warning: unrelated noise brew puts on stderr"
  echo "brew bundle can't satisfy your Brewfile's dependencies."
  echo "→ Cask docker-desktop needs to be installed or updated."
  echo "→ App Store app Keynote needs to be installed or updated."
  echo "→ Tap homebrew/cask-versions needs to be tapped."
  echo "Satisfy missing dependencies with brew bundle install."
} >&2
EOF
  : >"$DOTFILES_STATE/Brewfile"
}

says() {
  [[ "$output" == *"$1"* ]]
}

refute_says() {
  [[ "$output" != *"$1"* ]]
}

# --- rendering, on a table the test owns -----------------------------------

FAKE_APPS='{"apps":[
  {"kind":"cask","name":"fake-cask","app":"Fake Cask.app","group":"core"},
  {"kind":"mas","name":"12345","app":"Fake Store App.app","group":"core"},
  {"kind":"cask","name":"no-bundle","app":"","group":"core"},
  {"kind":"cask","name":"fake-personal","app":"Fake Personal.app","group":"personal"}
]}'

@test "a managed machine checks one app per table row, casks and App Store alike" {
  run render_apps true false "$FAKE_APPS"
  [ "$status" -eq 0 ]
  says 'want_app "Fake Cask.app" "Fake Cask"'
  says 'want_app "Fake Store App.app" "Fake Store App"'
}

@test "a row that installs no bundle is not checked for one" {
  run render_apps true false "$FAKE_APPS"
  refute_says 'no-bundle'
  refute_says 'want_app ""'
}

@test "rows outside the enabled groups are not in the list" {
  run render_apps true false "$FAKE_APPS"
  refute_says 'Fake Personal'
  run render_apps true true "$FAKE_APPS"
  says 'want_app "Fake Personal.app" "Fake Personal"'
}

@test "the Self Service list is rendered only for a managed machine" {
  run render_apps true false "$FAKE_APPS"
  says 'Self Service Portal'
  run render_apps false false "$FAKE_APPS"
  refute_says 'Self Service Portal'
  refute_says 'want_app'
}

@test "the package-failure branch is rendered only for an unmanaged machine" {
  # `marker_value packages-status` is named in the shared preamble's comments
  # too, so the branch is recognised by the line only it carries.
  run render_apps false false "$FAKE_APPS"
  says 'brew bundle exited'
  run render_apps true false "$FAKE_APPS"
  refute_says 'brew bundle exited'
}

# --- the apps to request ---------------------------------------------------

@test "a managed machine is told to request the apps that are not installed" {
  installed 'Fake Cask.app'
  report_apps true false
  [ "$status" -eq 0 ]
  says 'Self Service Portal'
  says '- Fake Store App'
  refute_says '- Fake Cask'
}

@test "the list is what Applications holds now, not what it held last time" {
  report_apps true false
  says '- Fake Cask'
  installed 'Fake Cask.app'
  report_apps true false
  refute_says '- Fake Cask'
}

@test "the list follows the enabled groups" {
  report_apps true false
  refute_says '- Fake Personal'
  report_apps true true
  says '- Fake Personal'
}

@test "a managed machine with every app installed is not sent to the portal" {
  chezmoi_config true false false
  while read -r app; do
    installed "$app"
  done <<<"$(render '{{ range .apps }}{{ if ne .app "" }}{{ .app }}
{{ end }}{{ end }}')"
  report true
  [ "$status" -eq 0 ]
  refute_says 'Self Service Portal'
}

@test "an unmanaged machine is never sent to the portal" {
  report false
  [ "$status" -eq 0 ]
  refute_says 'Self Service Portal'
}

# --- Privacy & Security, and Karabiner's first launch ----------------------

@test "approvals are listed only for the apps that are installed" {
  report false
  refute_says 'Approve Karabiner-Elements'
  refute_says 'Approve Hammerspoon'

  installed 'Karabiner-Elements.app'
  report false
  says 'Approve Karabiner-Elements'
  says 'Input Monitoring'
  says 'Accessibility'
  says 'Login Items & Extensions'
  refute_says 'Approve Hammerspoon'

  installed 'Hammerspoon.app'
  report false
  says 'Approve Hammerspoon'
}

@test "an installed Karabiner that has never run is asked to be launched once" {
  installed 'Karabiner-Elements.app'
  report false
  says 'Launch Karabiner-Elements once'

  mkdir -p "$XDG_CONFIG_HOME/karabiner"
  echo '{}' >"$XDG_CONFIG_HOME/karabiner/karabiner.json"
  report false
  refute_says 'Launch Karabiner-Elements once'
}

@test "Karabiner's first launch is not mentioned when Karabiner is absent" {
  report false
  refute_says 'Launch Karabiner-Elements once'
}

# --- the settings a marker decides -----------------------------------------

@test "dictation always needs a human, so it is always listed" {
  report false
  says 'dictation'
  says 'en_US, fr_CH and de_CH'
}

@test "pointer speed is listed until the script that writes it marks success" {
  report false
  says 'tracking speed'
  : >"$DOTFILES_STATE/pointer-speed-applied"
  report false
  refute_says 'tracking speed'
}

@test "auto-brightness is listed until the display script marks success" {
  report false
  says 'Automatically adjust brightness'
  : >"$DOTFILES_STATE/auto-brightness-applied"
  report false
  refute_says 'Automatically adjust brightness'
}

# --- the ssh key for Azure DevOps ------------------------------------------

@test "no key was generated on this machine, so Azure DevOps is not mentioned" {
  report false
  refute_says 'Azure DevOps'
}

@test "a generated key is printed for the paste, with the way to stop asking" {
  echo 'ssh-rsa AAAATESTKEYAAAA nobody@example' >"$HOME/id_rsa.pub"
  printf '%s\n' "$HOME/id_rsa.pub" >"$DOTFILES_STATE/ssh-key-generated"
  report false
  [ "$status" -eq 0 ]
  says 'Azure DevOps'
  says 'ssh-rsa AAAATESTKEYAAAA nobody@example'
  says "rm $DOTFILES_STATE/ssh-key-generated"
}

@test "a key file that is gone says so instead of printing nothing" {
  printf '%s\n' "$HOME/.ssh/id_rsa.pub" >"$DOTFILES_STATE/ssh-key-generated"
  report false
  [ "$status" -eq 0 ]
  says 'Azure DevOps'
  says 'Key file missing'
}

# --- packages that did not install -----------------------------------------

@test "a clean package run is not on the checklist" {
  stub_brew_check 1
  report false
  refute_says 'brew bundle exited'

  echo 0 >"$DOTFILES_STATE/packages-status"
  report false
  refute_says 'brew bundle exited'
  [ ! -f "$BATS_TEST_TMPDIR/brew.log" ]
}

@test "a failed package run names the entries and the usual cause" {
  stub_brew_check 1
  echo 1 >"$DOTFILES_STATE/packages-status"
  report false
  [ "$status" -eq 0 ]
  says 'brew bundle exited 1'
  says '- Cask docker-desktop'
  says '- App Store app Keynote'
  # A tap is a realistic miss -- the Brewfile carries `tap` lines -- and it is
  # the shape that proves the suffix is not pinned to "installed or updated".
  says '- Tap homebrew/cask-versions'
  says 'signed-out App Store'
  run cat "$BATS_TEST_TMPDIR/brew.log"
  says "brew bundle check --file $DOTFILES_STATE/Brewfile --verbose"
}

@test "brew's headline, footer and stray warnings are not read as entries" {
  stub_brew_check 1
  echo 1 >"$DOTFILES_STATE/packages-status"
  report false
  refute_says 'unrelated noise'
  refute_says "can't satisfy"
  refute_says 'Satisfy missing dependencies'
}

@test "the entries are worked out now, so a since-fixed entry is not repeated" {
  stub_brew_check 1
  echo 2 >"$DOTFILES_STATE/packages-status"
  report false
  says '- Cask docker-desktop'

  stub brew
  report false
  says 'brew bundle exited 2'
  refute_says '- Cask docker-desktop'
}

@test "a machine without Homebrew still gets the advice, without the entries" {
  echo 1 >"$DOTFILES_STATE/packages-status"
  export DOTFILES_BREW="$BATS_TEST_TMPDIR/bin/no-such-brew"
  report false
  [ "$status" -eq 0 ]
  says 'brew bundle exited 1'
  says 'signed-out App Store'
}

# --- the upgrade the apply never runs --------------------------------------

@test "a machine with Homebrew is told how to upgrade its packages" {
  stub brew
  report false
  [ "$status" -eq 0 ]
  says 'Upgrade the Homebrew packages'
  says 'brew update && brew upgrade'
}

@test "a machine without Homebrew has nothing to upgrade" {
  export DOTFILES_BREW="$BATS_TEST_TMPDIR/bin/no-such-brew"
  report false
  refute_says 'brew update && brew upgrade'
}

# --- the README says the same ----------------------------------------------

@test "the README's manual checklist covers everything the report can print" {
  local checklist item
  checklist="$(sed -n '/^## Manual checklist$/,/^## /p' "$REPO_ROOT/README.md")"
  [ -n "$checklist" ]
  for item in \
    'Karabiner-Elements' 'Hammerspoon' 'Input Monitoring' 'Accessibility' \
    'Login Items & Extensions' 'karabiner/karabiner.json' 'dictation' \
    'tracking speed' 'Automatically adjust brightness' 'Azure DevOps' \
    'Self Service Portal' 'brew bundle' 'brew update && brew upgrade' \
    'App Store' 'admin password' \
    'ssh-key-generated' 'pointer-speed-applied' 'auto-brightness-applied' \
    'packages-status'; do
    if [[ "$checklist" != *"$item"* ]]; then
      echo "the README checklist never mentions: $item" >&2
      return 1
    fi
  done
}

# --- the report may never fail the apply -----------------------------------

@test "a settled machine still gets a checklist and a zero exit" {
  report false
  [ "$status" -eq 0 ]
  says 'What is left to do by hand'
  says 'admin password'
}

@test "everything going wrong at once still exits zero and prints the rest" {
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/no-such-Applications"
  printf '%s\n' "$BATS_TEST_TMPDIR/gone.pub" >"$DOTFILES_STATE/ssh-key-generated"
  echo 9 >"$DOTFILES_STATE/packages-status"
  stub brew '' 7 <<'EOF'
echo 'not a brew' >&2
EOF
  : >"$DOTFILES_STATE/Brewfile"

  for managed in true false; do
    report "$managed"
    [ "$status" -eq 0 ]
    # The footer is the last line of the script, so reaching it proves no step
    # swallowed the ones after it.
    says 'admin password'
  done
}
