#!/usr/bin/env bats
#
# Quarantine: clearing Gatekeeper's flag from the apps Self Service handed
# out, and repairing the `hs` link a translocated Hammerspoon left behind.
#
# Nothing here touches this Mac. `sudo`, `xattr`, `pgrep`, `ps`, `osascript`
# and `open` are stubs, Applications is a temporary folder, and the apps table
# is replaced so the assertions run on data the test owns. Which apps carry
# the flag is a file the xattr stub consults, which carry Gatekeeper's
# provenance mark is another; whether Hammerspoon runs, and from where, is a
# third. A bundle from the portal belongs to root, which the test plays by
# taking the write bit away. The sudo log doubles as the count of password
# prompts: a settled Mac must leave it empty.

FAKE_APPS='{"apps":[
  {"kind":"cask","name":"hammerspoon","app":"Hammerspoon.app","group":"core"},
  {"kind":"cask","name":"karabiner-elements","app":"Karabiner-Elements.app","group":"core"},
  {"kind":"cask","name":"ngrok","app":"","group":"core"},
  {"kind":"cask","name":"signal","app":"Signal.app","group":"personal"}
]}'

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$DOTFILES_STATE" "$DOTFILES_APPLICATIONS" "$HOME/.local/bin"

  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_55-quarantine.sh.tmpl"
  FLAGGED="$BATS_TEST_TMPDIR/flagged"        # one app bundle name per line
  PROVENANCE="$BATS_TEST_TMPDIR/provenance"  # same, for com.apple.provenance
  RUNNING="$BATS_TEST_TMPDIR/hammerspoon-path" # exists while Hammerspoon runs
  LOG="$BATS_TEST_TMPDIR/commands.log"
  HS_LINK="$HOME/.local/bin/hs"
  TRANSLOCATED="/private/var/folders/xx/T/AppTranslocation/0000-1111/d/Hammerspoon.app"
  : >"$FLAGGED" "$PROVENANCE"
  stub_commands
}

teardown() {
  chmod -R u+w "$DOTFILES_APPLICATIONS" 2>/dev/null || true
}

stub_commands() {
  # xattr -p <attr> <path> answers from the list that attribute keeps;
  # -dr com.apple.quarantine <path> removes the app from the flagged list.
  stub xattr "$LOG" <<EOF
case "\$1 \$2" in
"-p com.apple.quarantine") grep -qxF "\${3##*/}" "$FLAGGED"; exit \$? ;;
"-p com.apple.provenance") grep -qxF "\${3##*/}" "$PROVENANCE"; exit \$? ;;
"-dr com.apple.quarantine") grep -vxF "\${3##*/}" "$FLAGGED" >"$FLAGGED.new" || true; mv "$FLAGGED.new" "$FLAGGED" ;;
*) exit 99 ;;
esac
EOF
  # sudo runs its argument list, which lands in the xattr stub above.
  stub sudo "$LOG" <<'EOF'
exec "$@"
EOF
  stub pgrep "$LOG" <<EOF
[ -f "$RUNNING" ] || exit 1
echo 4242
EOF
  stub ps "$LOG" <<EOF
cat "$RUNNING"
EOF
  # quit is what makes pgrep stop finding it.
  stub osascript "$LOG" <<EOF
rm -f "$RUNNING"
EOF
  stub open "$LOG" </dev/null
}

# quarantine <managed> <personal>  -> runs the rendered script
quarantine() {
  chezmoi_config "${1:-true}" "${2:-false}" false
  local script="$BATS_TEST_TMPDIR/quarantine.sh"
  render --file "$SCRIPT" --override-data "$FAKE_APPS" >"$script"
  run sh "$script"
}

installed() {
  mkdir -p "$DOTFILES_APPLICATIONS/$1/Contents/MacOS"
}

# from_portal "Hammerspoon.app" -> the bundle belongs to root, as the test
# can show it: not writable by the user
from_portal() {
  installed "$1"
  chmod a-w "$DOTFILES_APPLICATIONS/$1"
}

flagged() {
  printf '%s\n' "$1" >>"$FLAGGED"
}

approved() {
  printf '%s\n' "$1" >>"$PROVENANCE"
}

# hammerspoon_runs_from <path of the running binary's bundle>
hammerspoon_runs_from() {
  printf '%s/Contents/MacOS/Hammerspoon\n' "$1" >"$RUNNING"
}

says() {
  [[ "$output" == *"$1"* ]]
}

refute_says() {
  [[ "$output" != *"$1"* ]]
}

logged() {
  [ -f "$LOG" ] && grep -qF -- "$1" "$LOG"
}

refute_logged() {
  [ ! -f "$LOG" ] || ! grep -qF -- "$1" "$LOG"
}

# --- the flag ---------------------------------------------------------------

@test "a flagged app from the portal has its flag cleared through sudo" {
  from_portal 'Karabiner-Elements.app'
  flagged 'Karabiner-Elements.app'
  quarantine true
  [ "$status" -eq 0 ]
  says "clearing Gatekeeper's flag on Karabiner-Elements.app (sudo password needed)"
  logged "sudo xattr -dr com.apple.quarantine $DOTFILES_APPLICATIONS/Karabiner-Elements.app"
  [ ! -s "$FLAGGED" ]
}

@test "a flagged app the user owns is cleared without sudo" {
  installed 'Karabiner-Elements.app'
  flagged 'Karabiner-Elements.app'
  quarantine true
  [ "$status" -eq 0 ]
  says "clearing Gatekeeper's flag on Karabiner-Elements.app"
  refute_says 'sudo'
  refute_logged 'sudo'
  logged "xattr -dr com.apple.quarantine $DOTFILES_APPLICATIONS/Karabiner-Elements.app"
  [ ! -s "$FLAGGED" ]
}

@test "an app Gatekeeper has approved keeps its flag and costs nothing" {
  from_portal 'Karabiner-Elements.app'
  flagged 'Karabiner-Elements.app'
  approved 'Karabiner-Elements.app'
  quarantine true
  [ "$status" -eq 0 ]
  refute_logged 'sudo'
  refute_logged 'xattr -dr'
  refute_says 'clearing'
  [ -z "$output" ]
}

@test "an app without the flag costs no sudo" {
  installed 'Karabiner-Elements.app'
  quarantine true
  [ "$status" -eq 0 ]
  refute_logged 'sudo'
  refute_says 'clearing'
}

@test "a flagged app that is not installed is left to the next apply" {
  flagged 'Karabiner-Elements.app'
  quarantine true
  [ "$status" -eq 0 ]
  refute_logged 'sudo'
}

@test "only the enabled groups are looked at" {
  installed 'Signal.app'
  flagged 'Signal.app'
  quarantine true false
  refute_logged 'Signal.app'
  quarantine true true
  logged "xattr -dr com.apple.quarantine $DOTFILES_APPLICATIONS/Signal.app"
}

@test "a row that installs no bundle is never looked at" {
  run render --file "$SCRIPT" --override-data "$FAKE_APPS"
  refute_says 'ngrok'
  refute_says 'app_present ""'
}

@test "an unmanaged Mac leaves Gatekeeper's flags alone" {
  installed 'Hammerspoon.app'
  flagged 'Hammerspoon.app'
  hammerspoon_runs_from "$TRANSLOCATED"
  quarantine false
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
  [ -z "$output" ]
}

@test "a sudo that fails says so and exits zero" {
  from_portal 'Karabiner-Elements.app'
  flagged 'Karabiner-Elements.app'
  stub sudo "$LOG" 1 </dev/null
  quarantine true
  [ "$status" -eq 0 ]
  says 'could not clear the flag on Karabiner-Elements.app'
  says 'chezmoi apply'
}

# --- Hammerspoon and its hs link -------------------------------------------

@test "a translocated Hammerspoon is unflagged, its dead link removed, and relaunched" {
  installed 'Hammerspoon.app'
  flagged 'Hammerspoon.app'
  hammerspoon_runs_from "$TRANSLOCATED"
  ln -s "$TRANSLOCATED/Contents/Frameworks/hs/hs" "$HS_LINK"
  quarantine true
  [ "$status" -eq 0 ]
  says "clearing Gatekeeper's flag on Hammerspoon.app"
  says "removing $HS_LINK"
  says 'relaunching Hammerspoon'
  [ ! -L "$HS_LINK" ]
  logged 'osascript -e tell application "Hammerspoon" to quit'
  logged "open $DOTFILES_APPLICATIONS/Hammerspoon.app"
}

@test "a link into a translocated copy is removed even while its target exists" {
  installed 'Hammerspoon.app'
  mkdir -p "$BATS_TEST_TMPDIR/AppTranslocation/abc/d/Hammerspoon.app/Contents/Frameworks/hs"
  : >"$BATS_TEST_TMPDIR/AppTranslocation/abc/d/Hammerspoon.app/Contents/Frameworks/hs/hs"
  ln -s "$BATS_TEST_TMPDIR/AppTranslocation/abc/d/Hammerspoon.app/Contents/Frameworks/hs/hs" "$HS_LINK"
  hammerspoon_runs_from "$DOTFILES_APPLICATIONS/Hammerspoon.app"
  quarantine true
  [ "$status" -eq 0 ]
  [ ! -L "$HS_LINK" ]
  says 'relaunching Hammerspoon'
}

@test "a dangling link is removed and Hammerspoon relaunched even when it runs from Applications" {
  installed 'Hammerspoon.app'
  ln -s "$BATS_TEST_TMPDIR/nowhere/hs" "$HS_LINK"
  hammerspoon_runs_from "$DOTFILES_APPLICATIONS/Hammerspoon.app"
  quarantine true
  [ ! -L "$HS_LINK" ]
  logged 'open'
}

@test "a Hammerspoon that is not running is not launched" {
  installed 'Hammerspoon.app'
  ln -s "$BATS_TEST_TMPDIR/nowhere/hs" "$HS_LINK"
  quarantine true
  [ "$status" -eq 0 ]
  [ ! -L "$HS_LINK" ]
  refute_logged 'osascript'
  refute_logged 'open'
}

@test "a Hammerspoon whose flag could not be cleared is not relaunched" {
  from_portal 'Hammerspoon.app'
  flagged 'Hammerspoon.app'
  hammerspoon_runs_from "$TRANSLOCATED"
  stub sudo "$LOG" 1 </dev/null
  quarantine true
  [ "$status" -eq 0 ]
  says 'still flagged'
  refute_logged 'osascript'
  refute_logged 'open'
}

@test "a Hammerspoon that will not quit is left alone with a note" {
  installed 'Hammerspoon.app'
  hammerspoon_runs_from "$TRANSLOCATED"
  stub osascript "$LOG" </dev/null
  quarantine true
  [ "$status" -eq 0 ]
  says 'did not quit'
  refute_logged 'open'
}

@test "a good link into Applications is kept" {
  installed 'Hammerspoon.app'
  mkdir -p "$DOTFILES_APPLICATIONS/Hammerspoon.app/Contents/Frameworks/hs"
  : >"$DOTFILES_APPLICATIONS/Hammerspoon.app/Contents/Frameworks/hs/hs"
  ln -s "$DOTFILES_APPLICATIONS/Hammerspoon.app/Contents/Frameworks/hs/hs" "$HS_LINK"
  hammerspoon_runs_from "$DOTFILES_APPLICATIONS/Hammerspoon.app"
  quarantine true
  [ -L "$HS_LINK" ]
  refute_logged 'open'
}

# --- a settled Mac ----------------------------------------------------------

@test "a settled managed Mac prompts for nothing and relaunches nothing" {
  installed 'Hammerspoon.app'
  installed 'Karabiner-Elements.app'
  hammerspoon_runs_from "$DOTFILES_APPLICATIONS/Hammerspoon.app"
  quarantine true
  [ "$status" -eq 0 ]
  refute_logged 'sudo'
  refute_logged 'osascript'
  refute_logged 'open'
  [ -z "$output" ]
}
