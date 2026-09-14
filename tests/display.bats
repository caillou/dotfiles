#!/usr/bin/env bats
#
# Display settings: turning auto-brightness off in root's CoreBrightness
# preferences.
#
# Nothing here touches this Mac. `sudo`, `killall` and `defaults` are stubs on
# PATH, and root's domain is a plist file in a temporary directory that the
# stubbed `defaults export` reads and the stubbed `defaults import` writes, so
# the round trip is exercised for real while the machine is left alone. The
# sudo log doubles as the count of password prompts: a settled Mac, one whose
# marker records an earlier success, must leave it empty.

DOMAIN=com.apple.CoreBrightness
BUILTIN=37D8832A-2D66-02CA-B9F7-8F30A301B230
SECOND=610E5031-9C1E-4B6B-9E25-4F9F0BC8B7A2
EXTERNAL=4D9F0C61-8B3C-4D0B-9F3F-70A0D2B1C6A1

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  MARKER="$DOTFILES_STATE/auto-brightness-applied"
  DISPLAY_SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_64-display.sh.tmpl"

  ROOT_PLIST="$BATS_TEST_TMPDIR/root-CoreBrightness.plist"
  LOG="$BATS_TEST_TMPDIR/sudo.log"
  stub_commands
}

# Stubs stand in for every command that could change this Mac. They are written
# in setup, before any test body, so a bug in the script cannot reach the real
# sudo even in a test that never mentions it.
stub_commands() {
  stub sudo "$LOG" <<EOF
case "\$*" in
"-H defaults export $DOMAIN -")
  [ -f "$ROOT_PLIST" ] || exit 1
  cat "$ROOT_PLIST"
  ;;
"-H defaults import $DOMAIN -")
  [ -f "$BATS_TEST_TMPDIR/import-fails" ] && exit 1
  if [ -f "$BATS_TEST_TMPDIR/import-ignored" ]; then
    cat >/dev/null
  else
    cat >"$ROOT_PLIST"
  fi
  ;;
"killall corebrightnessd") ;;
*)
  printf 'unexpected sudo: %s\n' "\$*" >&2
  exit 99
  ;;
esac
EOF
  # Called without sudo these would be a bug, so they log under their own bare
  # name and report failure rather than quietly standing in for the real thing.
  for command in killall defaults; do
    stub "$command" "$LOG" 1 </dev/null
  done
}

# display_entry <uuid> <true|false|missing> -> one display dict
display_entry() {
  printf '\t\t<key>%s</key>\n\t\t<dict>\n' "$1"
  case "$2" in
  true | false) printf '\t\t\t<key>AutoBrightnessEnable</key>\n\t\t\t<%s/>\n' "$2" ;;
  esac
  printf '\t\t\t<key>BrightnessLevelNits</key>\n\t\t\t<real>317.5</real>\n\t\t</dict>\n'
}

# root_domain <display entries> -> the plist root's domain holds
root_domain() {
  cat >"$ROOT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CBUser-9F2A</key>
	<dict>
		<key>BlueReductionEnabled</key>
		<false/>
	</dict>
	<key>DisplayPreferences</key>
	<dict>
$1	</dict>
	<key>KeyboardBacklightABEnabled</key>
	<true/>
</dict>
</plist>
EOF
}

# display -> runs the rendered script with everything stubbed
display() {
  chezmoi_config false false false
  local script="$BATS_TEST_TMPDIR/display.sh"
  render --file "$DISPLAY_SCRIPT" >"$script"
  run sh "$script"
}

# settled -> the marker an earlier apply left behind
settled() {
  mkdir -p "$DOTFILES_STATE"
  : >"$MARKER"
}

# value_at <key path> -> the value in root's domain, fails when absent
value_at() {
  plutil -extract "$1" raw -o - "$ROOT_PLIST"
}

# flag_of <uuid> -> that display's auto-brightness flag, fails when absent
flag_of() {
  value_at "DisplayPreferences.$1.AutoBrightnessEnable"
}

logged() {
  grep -qxF -e "$1" "$LOG"
}

refute_logged() {
  ! grep -qxF -e "$1" "$LOG"
}

# no_sudo -> nothing was logged, so no password could have been asked for
no_sudo() {
  [ ! -s "$LOG" ]
}

manual_instruction() {
  [[ "$output" == *'System Settings > Displays'* ]]
}

# --- turning it off --------------------------------------------------------

@test "a display with auto-brightness on is turned off" {
  root_domain "$(display_entry "$BUILTIN" true)$(display_entry "$SECOND" false)"
  display
  [ "$status" -eq 0 ]
  [ "$(flag_of "$BUILTIN")" = false ]
  [ "$(flag_of "$SECOND")" = false ]
  logged "sudo -H defaults import $DOMAIN -"
  [ -f "$MARKER" ]
}

@test "the flag is set on every display entry, identifiers being per machine" {
  root_domain "$(display_entry "$EXTERNAL" missing)"
  display
  [ "$status" -eq 0 ]
  [ "$(flag_of "$EXTERNAL")" = false ]
}

@test "the daemon is restarted only after a write" {
  root_domain "$(display_entry "$BUILTIN" true)"
  display
  [ "$status" -eq 0 ]
  # The import comes before the restart, and the restart before the read-back.
  [ "$(tail -3 "$LOG")" = "sudo -H defaults import $DOMAIN -
sudo killall corebrightnessd
sudo -H defaults export $DOMAIN -" ]
}

@test "the rest of the domain survives the round trip" {
  root_domain "$(display_entry "$BUILTIN" true)"
  display
  [ "$status" -eq 0 ]
  [ "$(value_at 'CBUser-9F2A.BlueReductionEnabled')" = false ]
  [ "$(value_at KeyboardBacklightABEnabled)" = true ]
  # plutil prints reals with six decimals, hence the spelling.
  [ "$(value_at "DisplayPreferences.$BUILTIN.BrightnessLevelNits")" = 317.500000 ]
}

# --- the no-op -------------------------------------------------------------

@test "a machine that is already off is a no-op: no import, no restart" {
  root_domain "$(display_entry "$BUILTIN" false)$(display_entry "$SECOND" false)"
  display
  [ "$status" -eq 0 ]
  [[ "$output" == *'already off'* ]]
  refute_logged "sudo -H defaults import $DOMAIN -"
  refute_logged 'sudo killall corebrightnessd'
  [ -f "$MARKER" ]
}

@test "without the marker the domain is read through sudo, once, even when nothing changes" {
  root_domain "$(display_entry "$BUILTIN" false)"
  display
  [ "$status" -eq 0 ]
  logged "sudo -H defaults export $DOMAIN -"
  [ "$(wc -l <"$LOG")" -eq 1 ]
  [ -f "$MARKER" ]
}

@test "a settled Mac asks for no admin password at all" {
  settled
  root_domain "$(display_entry "$BUILTIN" false)"
  display
  [ "$status" -eq 0 ]
  [[ "$output" == *'already off'* ]]
  no_sudo
  [ -f "$MARKER" ]
}

@test "a second apply after a write is a no-op without sudo" {
  root_domain "$(display_entry "$BUILTIN" true)$(display_entry "$EXTERNAL" missing)"
  display
  : >"$LOG"
  display
  [ "$status" -eq 0 ]
  [[ "$output" == *'already off'* ]]
  no_sudo
}

# --- dead ends never fail the apply ----------------------------------------

@test "a domain that cannot be read leaves the apply alone" {
  rm -f "$ROOT_PLIST"
  display
  [ "$status" -eq 0 ]
  manual_instruction
  refute_logged "sudo -H defaults import $DOMAIN -"
  [ ! -f "$MARKER" ]
}

@test "a domain without display entries leaves the apply alone" {
  root_domain ''
  display
  [ "$status" -eq 0 ]
  manual_instruction
  refute_logged "sudo -H defaults import $DOMAIN -"
  [ ! -f "$MARKER" ]
}

@test "a failed import leaves the apply alone and restarts nothing" {
  root_domain "$(display_entry "$BUILTIN" true)"
  : >"$BATS_TEST_TMPDIR/import-fails"
  display
  [ "$status" -eq 0 ]
  manual_instruction
  refute_logged 'sudo killall corebrightnessd'
  [ ! -f "$MARKER" ]
}

@test "a flag that does not stay off asks for the manual step" {
  root_domain "$(display_entry "$BUILTIN" true)"
  : >"$BATS_TEST_TMPDIR/import-ignored"
  display
  [ "$status" -eq 0 ]
  manual_instruction
  logged 'sudo killall corebrightnessd'
  [ "$(flag_of "$BUILTIN")" = true ]
  [ ! -f "$MARKER" ]
}

@test "a marker cleared after an earlier success brings the read back" {
  root_domain "$(display_entry "$BUILTIN" true)"
  display
  [ -f "$MARKER" ]
  # Cleared by hand: the next apply reads root's domain again instead of
  # trusting the earlier success, and a run that then cannot finish leaves
  # no marker behind.
  rm "$MARKER"
  rm -f "$ROOT_PLIST"
  : >"$LOG"
  display
  [ "$status" -eq 0 ]
  logged "sudo -H defaults export $DOMAIN -"
  manual_instruction
  [ ! -f "$MARKER" ]
}

# --- the route into the domain ---------------------------------------------

@test "the script edits root's domain, never the preferences file" {
  run render --file "$DISPLAY_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$DOMAIN"* ]]
  [[ "$output" != *'/var/root/Library/Preferences'* ]]
  [[ "$output" != *'PlistBuddy'* ]]
}

@test "auto-brightness is the only key touched, so True Tone stays default" {
  root_domain "$(display_entry "$BUILTIN" true)"
  display
  [ "$status" -eq 0 ]
  run bash -c "plutil -extract 'DisplayPreferences.$BUILTIN' xml1 -o - '$ROOT_PLIST' | grep -c '<key>'"
  [ "$output" = 2 ]
}
