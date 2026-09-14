#!/usr/bin/env bats
#
# The macOS defaults script: which keys it writes, in which order, and how it
# behaves when the machine already has a value.
#
# Nothing here touches the machine running the tests. `defaults`, `killall`,
# `osascript`, `hidutil`, `pmset` and `sudo` are stubs on PATH that log their
# arguments and change nothing, activateSettings is pointed at a stub through
# its seam, and HOME and the XDG variables are temporary directories. The two
# real tools are `plutil`, which reads a fixture the test writes, and the
# system python, which edits the exported hotkey plist exactly as it does on a
# real apply.
#
# The script is a pure writer, so one run tells everything about what it
# writes: setup_file applies it once and the value tests read that run's log
# through `applied`. Only a test that changes the machine first (the wallpaper
# store, pmset's report, the live pointer speed, a missing python) applies
# again, through `apply`.

# machine
#
# The Mac a run sees, under $BATS_TEST_TMPDIR: an isolated home, its own state
# directory, and the log and plists the stubs read and write. The stubs take
# those paths from the environment at run time, so the ones setup_file writes
# serve every run: a freshly written stub costs about 150 ms of macOS's
# first-execution check, and seven per test was most of this file's time.
machine() {
  isolate_home
  export DOTFILES_STATE="$TMP/state"
  export DEFAULTS_LOG="$TMP/commands.log"
  export DEFAULTS_EXPORTED="$TMP/exported.plist"
  export DEFAULTS_IMPORTED="$TMP/imported.plist"
  LOG="$DEFAULTS_LOG"
  IMPORTED="$DEFAULTS_IMPORTED"
  hotkeys_domain >"$DEFAULTS_EXPORTED"

  # What `pmset -g custom` reports. This machine needs all four values
  # changed; the tests that care about the comparison override it.
  export PMSET_STATE="Battery Power:
 displaysleep         5
 sleep                1
 lessbright           1
AC Power:
 displaysleep         5
 sleep                1"
}

setup_file() {
  load helpers
  machine

  # The log is named as a variable, unexpanded, so each stub opens whichever
  # log the run's environment names. Stubs without a body take /dev/null so
  # they never read a stdin bats inherited. What `defaults export` hands out
  # and where `defaults import` lands are the same kind of seam, so the hotkey
  # round-trip can be inspected.
  stub defaults '$DEFAULTS_LOG' <<'EOF'
case "$1" in
export) cat "$DEFAULTS_EXPORTED" ;;
import) cat >"$DEFAULTS_IMPORTED" ;;
esac
EOF
  stub killall '$DEFAULTS_LOG' </dev/null
  stub sudo '$DEFAULTS_LOG' </dev/null
  stub activateSettings '$DEFAULTS_LOG' </dev/null
  stub osascript '$DEFAULTS_LOG' <<'EOF'
[ -z "${OSASCRIPT_FAILS:-}" ] || exit 1
EOF
  stub hidutil '$DEFAULTS_LOG' <<'EOF'
[ -z "${POINTER_LIVE-unset}" ] || echo "${POINTER_LIVE:-45056}"
EOF
  stub pmset '$DEFAULTS_LOG' <<'EOF'
[ "$1" != -g ] || printf '%s\n' "$PMSET_STATE"
EOF
  export DOTFILES_ACTIVATE_SETTINGS="$STUB_BIN/activateSettings"

  export SCRIPT="$BATS_FILE_TMPDIR/defaults.sh"
  render --file "$REPO_ROOT/.chezmoiscripts/run_onchange_after_60-defaults.sh.tmpl" >"$SCRIPT"

  # The one apply the read-only tests look at.
  run sh "$SCRIPT"
  export APPLIED_STATUS="$status"
  export APPLIED_OUTPUT="$output"
  export APPLIED_HOME="$HOME"
  export APPLIED_STATE="$DOTFILES_STATE"
  export APPLIED_LOG="$LOG"
  export APPLIED_IMPORTED="$IMPORTED"
}

setup() {
  load helpers
  machine
}

# hotkeys_domain -> what `defaults export com.apple.symbolichotkeys` hands out:
# a domain with one hotkey already in it, so the edit has something to keep.
hotkeys_domain() {
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AppleSymbolicHotKeys</key>
  <dict>
    <key>32</key>
    <dict>
      <key>enabled</key><true/>
    </dict>
  </dict>
</dict>
</plist>
EOF
}

# applied -> the run setup_file did, as apply leaves one: status, output, and
# the log and imported plist the assertions read
applied() {
  status="$APPLIED_STATUS"
  output="$APPLIED_OUTPUT"
  LOG="$APPLIED_LOG"
  IMPORTED="$APPLIED_IMPORTED"
}

# apply -> runs the rendered script on this test's machine
apply() {
  run sh "$SCRIPT"
}

logged() {
  grep -qxF "$1" "$LOG"
}

# writes_all <<EOF ... EOF  -> fails naming the first expected line missing
writes_all() {
  local line
  while read -r line; do
    [ -n "$line" ] || continue
    if ! logged "$line"; then
      echo "not written: $line" >&3
      return 1
    fi
  done
}

# at <file> <fixed string> -> the line number of the first match
at() {
  grep -n -m 1 -F -- "$2" "$1" | cut -d : -f 1
}

# --- the order the script does things in -----------------------------------

@test "the script quits System Settings, writes, activates, then restarts" {
  quit="$(at "$SCRIPT" 'tell application "System Settings" to quit')"
  first_write="$(grep -n -m 1 '^defaults write ' "$SCRIPT" | cut -d : -f 1)"
  last_write="$(grep -n '^defaults ' "$SCRIPT" | tail -n 1 | cut -d : -f 1)"
  activate="$(at "$SCRIPT" '"$ACTIVATE_SETTINGS" -u')"
  restart="$(at "$SCRIPT" 'killall Finder Dock SystemUIServer')"

  [ "$quit" -lt "$first_write" ]
  [ "$last_write" -lt "$activate" ]
  [ "$activate" -lt "$restart" ]
}

@test "the same order holds when it runs" {
  applied
  [ "$status" -eq 0 ]
  quit="$(at "$LOG" 'osascript -e tell application "System Settings" to quit')"
  first_write="$(grep -n -m 1 '^defaults write ' "$LOG" | cut -d : -f 1)"
  last_write="$(grep -n '^defaults ' "$LOG" | tail -n 1 | cut -d : -f 1)"
  activate="$(at "$LOG" 'activateSettings -u')"
  restart="$(at "$LOG" 'killall Finder Dock SystemUIServer')"

  [ "$quit" = 1 ]
  [ "$quit" -lt "$first_write" ]
  [ "$last_write" -lt "$activate" ]
  [ "$activate" -lt "$restart" ]
}

@test "it is a pure writer: no hash, no state of its own, always exits 0" {
  applied
  [ "$status" -eq 0 ]
  [ ! -f "$APPLIED_STATE/defaults.hash" ]
}

@test "running it twice does exactly the same thing" {
  # The same home as the first run, so the paths in the log agree.
  export HOME="$APPLIED_HOME"
  apply
  [ "$status" -eq 0 ]
  diff "$APPLIED_LOG" "$LOG"
}

# --- the values ------------------------------------------------------------

@test "keyboard and text substitution" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write NSGlobalDomain com.apple.keyboard.fnState -bool true
defaults write com.apple.HIToolbox AppleFnUsageType -int 0
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
EOF
}

@test "scrolling" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false
EOF
}

@test "every trackpad key lands in both trackpad domains" {
  applied
  [ "$status" -eq 0 ]
  for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    writes_all <<EOF
defaults write $domain Clicking -bool true
defaults write $domain DragLock -int 0
defaults write $domain Dragging -int 0
defaults write $domain TrackpadThreeFingerDrag -bool false
defaults write $domain TrackpadRightClick -bool true
defaults write $domain TrackpadCornerSecondaryClick -int 0
defaults write $domain TrackpadThreeFingerTapGesture -int 0
defaults write $domain TrackpadTwoFingerDoubleTapGesture -int 1
defaults write $domain TrackpadPinch -int 1
defaults write $domain TrackpadRotate -int 1
defaults write $domain TrackpadScroll -bool true
defaults write $domain TrackpadHorizScroll -int 1
defaults write $domain TrackpadMomentumScroll -bool true
defaults write $domain TrackpadHandResting -bool true
defaults write $domain TrackpadThreeFingerHorizSwipeGesture -int 2
defaults write $domain TrackpadThreeFingerVertSwipeGesture -int 2
defaults write $domain TrackpadFourFingerHorizSwipeGesture -int 2
defaults write $domain TrackpadFourFingerVertSwipeGesture -int 2
defaults write $domain TrackpadFourFingerPinchGesture -int 2
defaults write $domain TrackpadFiveFingerPinchGesture -int 2
defaults write $domain TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3
defaults write $domain USBMouseStopsTrackpad -int 0
EOF
  done
}

@test "force click and click firmness go to the built-in trackpad only" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true
defaults write com.apple.AppleMultitouchTrackpad ActuateDetents -int 0
defaults write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 1
defaults write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 1
defaults write NSGlobalDomain com.apple.trackpad.forceClick -bool false
EOF
  run grep -c 'AppleBluetoothMultitouch.trackpad ForceSuppressed' "$LOG"
  [ "$output" = 0 ]
}

@test "tap to click and secondary click also get their global and per-host copies" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true
defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true
EOF
}

@test "pointer speed is written for the trackpad and the mouse" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 0.6875
defaults write NSGlobalDomain com.apple.mouse.scaling -float 0.6875
EOF
}

@test "screenshots" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<EOF
defaults write com.apple.screencapture location -string $APPLIED_HOME/Downloads
defaults write com.apple.screencapture type -string png
defaults write com.apple.screencapture show-thumbnail -bool false
EOF
}

@test "finder" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<EOF
defaults write com.apple.finder NewWindowTarget -string PfLo
defaults write com.apple.finder NewWindowTargetPath -string file://$APPLIED_HOME/Downloads/
defaults write com.apple.finder FXPreferredViewStyle -string clmv
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
EOF
}

@test "the Desktop icon view dictionary has the types Finder stores" {
  applied
  [ "$status" -eq 0 ]

  local prefix='defaults write com.apple.finder DesktopViewSettings -dict-add IconViewSettings '
  local fragment="$BATS_TEST_TMPDIR/iconview.plist"
  grep -F "$prefix" "$LOG" | sed "s|^$prefix||" >"$fragment"
  [ -s "$fragment" ]

  # A plist fragment, so plutil parses it. Old-style `{ key = value; }` syntax
  # would parse too, but every scalar in it would come out a string.
  run plutil -convert xml1 -o - "$fragment"
  [ "$status" -eq 0 ]

  # Keys sorted by plutil and whitespace dropped: the sizes are reals, the
  # label position a boolean, and only the arrangement is a string, which is
  # how Finder stores them. No sixth key sneaks in.
  local body
  body="$(printf '%s\n' "$output" | sed -n '/<dict>/,/<\/dict>/p' | tr -d ' \t\n')"
  [ "$body" = '<dict><key>arrangeBy</key><string>kind</string><key>gridSpacing</key><real>100</real><key>iconSize</key><real>16</real><key>labelOnBottom</key><false/><key>textSize</key><real>14</real></dict>' ]
}

@test "window manager" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
defaults write com.apple.WindowManager StandardHideDesktopIcons -bool true
defaults write com.apple.WindowManager HideDesktop -bool true
defaults write com.apple.WindowManager StandardHideWidgets -bool true
defaults write com.apple.WindowManager StageManagerHideWidgets -bool false
defaults write com.apple.WindowManager AutoHide -bool false
defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false
defaults write com.apple.WindowManager EnableTilingOptionAccelerator -bool false
defaults write com.apple.WindowManager AppWindowGroupingBehavior -int 1
EOF
}

@test "dock appearance and the four hot corners" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0.5
defaults write com.apple.dock tilesize -int 16
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock largesize -int 128
defaults write com.apple.dock orientation -string bottom
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock launchanim -bool false
defaults write com.apple.dock wvous-tl-corner -int 0
defaults write com.apple.dock wvous-tl-modifier -int 0
defaults write com.apple.dock wvous-tr-corner -int 0
defaults write com.apple.dock wvous-tr-modifier -int 0
defaults write com.apple.dock wvous-bl-corner -int 0
defaults write com.apple.dock wvous-bl-modifier -int 0
defaults write com.apple.dock wvous-br-corner -int 0
defaults write com.apple.dock wvous-br-modifier -int 0
EOF
}

@test "what is in the Dock is left to the Dock script" {
  applied
  run grep -E 'persistent-apps|persistent-others' "$LOG"
  [ "$status" -ne 0 ]
}

@test "dictation is enabled with its three languages" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
defaults write com.apple.HIToolbox AppleDictationAutoEnable -int 1
defaults write com.apple.assistant.support Dictation Enabled -bool true
defaults write com.apple.speech.recognition.AppleSpeechRecognition.prefs DictationIMPreferredLanguageIdentifiers -array en_US fr_CH de_CH
EOF
}

@test "what the notes mark informational or dropped is never written" {
  applied
  run grep -E 'AppleBluetoothMultitouch.mouse|doubleClickThreshold|LSQuarantine|com.apple.Safari|universalaccess|messageshelper|AppleInterfaceStyle|AppleShowScrollBars|AppleLocale' "$LOG"
  [ "$status" -ne 0 ]
}

# --- the dictation shortcut ------------------------------------------------

# hotkey <entry> -> the imported entry as python prints it
hotkey() {
  /usr/bin/python3 -c '
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    print(plistlib.loads(f.read())["AppleSymbolicHotKeys"][sys.argv[2]])
' "$IMPORTED" "$1"
}

@test "the shortcut goes through the domain, never through the plist file" {
  applied
  [ "$status" -eq 0 ]
  logged 'defaults export com.apple.symbolichotkeys -'
  logged 'defaults import com.apple.symbolichotkeys -'
  run grep -E 'PlistBuddy|Preferences/com.apple.symbolichotkeys.plist' "$LOG"
  [ "$status" -ne 0 ]
}

@test "entry 164 carries the captured parameters, including the one over int64" {
  applied
  run hotkey 164
  [ "$status" -eq 0 ]
  [ "$output" = "{'enabled': True, 'value': {'parameters': [262144, 18446744073709289471], 'type': 'modifier'}}" ]
}

@test "the other hotkeys of the domain survive the edit" {
  applied
  [ "$status" -eq 0 ]
  run hotkey 32
  [ "$output" = "{'enabled': True}" ]
  run hotkey 164
  [[ "$output" == *'18446744073709289471'* ]]
}

@test "without a system python the shortcut is skipped and the apply continues" {
  export DOTFILES_PYTHON="$BATS_TEST_TMPDIR/no-python3"
  apply
  [ "$status" -eq 0 ]
  [[ "$output" == *'skipping the dictation shortcut'* ]]
  [ ! -f "$IMPORTED" ]
  logged 'killall Finder Dock SystemUIServer'
}

# --- the wallpaper ---------------------------------------------------------

# wallpaper_store <provider> -> an Index.plist naming that provider
wallpaper_store() {
  local store="$HOME/Library/Application Support/com.apple.wallpaper/Store"
  mkdir -p "$store"
  cat >"$store/Index.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AllSpacesAndDisplays</key>
  <dict>
    <key>Desktop</key>
    <dict>
      <key>Content</key>
      <dict>
        <key>Choices</key>
        <array>
          <dict>
            <key>Provider</key><string>$1</string>
          </dict>
        </array>
      </dict>
    </dict>
  </dict>
</dict>
</plist>
EOF
}

@test "a fresh Mac with no wallpaper store gets the solid black picture" {
  applied
  [ "$status" -eq 0 ]
  [[ "$output" == *'wallpaper set to solid black'* ]]
  logged 'osascript -e tell application "System Events" to set picture of every desktop to "/System/Library/Desktop Pictures/Solid Colors/Black.png"'
}

@test "a desktop already on a solid colour is left alone" {
  wallpaper_store com.apple.wallpaper.choice.color
  apply
  [ "$status" -eq 0 ]
  [[ "$output" == *'already a solid colour'* ]]
  run grep -c 'set picture of every desktop' "$LOG"
  [ "$output" = 0 ]
}

@test "a desktop on a picture is switched to the solid colour" {
  wallpaper_store com.apple.wallpaper.choice.sonoma
  apply
  [ "$status" -eq 0 ]
  run grep -c 'set picture of every desktop' "$LOG"
  [ "$output" = 1 ]
}

@test "a refused Automation prompt prints the manual step and does not fail" {
  export OSASCRIPT_FAILS=1
  apply
  [ "$status" -eq 0 ]
  [[ "$output" == *'could not set the wallpaper'* ]]
  logged 'killall Finder Dock SystemUIServer'
}

# --- power -----------------------------------------------------------------

@test "pmset writes every value that differs, with sudo" {
  applied
  [ "$status" -eq 0 ]
  writes_all <<'EOF'
sudo pmset -c sleep 0
sudo pmset -c displaysleep 10
sudo pmset -b displaysleep 15
sudo pmset -b lessbright 0
EOF
}

@test "pmset writes nothing when the machine already has those values" {
  export PMSET_STATE="Battery Power:
 displaysleep         15
 sleep                1
 lessbright           0
AC Power:
 displaysleep         10
 sleep                0"
  apply
  [ "$status" -eq 0 ]
  run grep -c '^sudo ' "$LOG"
  [ "$output" = 0 ]
}

@test "only the value that differs is written" {
  export PMSET_STATE="Battery Power:
 displaysleep         15
 lessbright           0
AC Power:
 displaysleep         3
 sleep                0"
  apply
  [ "$status" -eq 0 ]
  run grep '^sudo ' "$LOG"
  [ "$output" = 'sudo pmset -c displaysleep 10' ]
}

@test "a failing pmset prints the manual step and does not fail the apply" {
  stub sudo "$LOG" 1 </dev/null
  apply
  [ "$status" -eq 0 ]
  [[ "$output" == *'System Settings > Battery'* ]]
  logged 'killall Finder Dock SystemUIServer'
}

# --- pointer speed read-back -----------------------------------------------

@test "the live pointer speed is read before the writes and after activation" {
  applied
  [ "$status" -eq 0 ]
  run grep -c 'hidutil property --get HIDPointerAcceleration' "$LOG"
  [ "$output" = 2 ]
  read_back="$(grep -n 'hidutil' "$LOG" | tail -n 1 | cut -d : -f 1)"
  activate="$(at "$LOG" 'activateSettings -u')"
  [ "$activate" -lt "$read_back" ]
}

@test "a live value at the target marks the step done" {
  export POINTER_LIVE=45056
  apply
  [ "$status" -eq 0 ]
  [ "$(cat "$DOTFILES_STATE/pointer-speed-applied")" = 0.6875 ]
}

@test "a live value that did not follow warns and leaves the marker absent" {
  export POINTER_LIVE=65536
  apply
  [ "$status" -eq 0 ]
  [ ! -f "$DOTFILES_STATE/pointer-speed-applied" ]
  [[ "$output" == *'pointer speed is 65536, wanted 45056'* ]]
  [[ "$output" == *'System Settings > Trackpad'* ]]
}

@test "a marker from an earlier run is dropped when the value drifts" {
  export POINTER_LIVE=45056
  apply
  [ -f "$DOTFILES_STATE/pointer-speed-applied" ]
  export POINTER_LIVE=131072
  apply
  [ "$status" -eq 0 ]
  [ ! -f "$DOTFILES_STATE/pointer-speed-applied" ]
}

@test "a machine where hidutil reports nothing does not fail the apply" {
  export POINTER_LIVE=
  apply
  [ "$status" -eq 0 ]
  [ ! -f "$DOTFILES_STATE/pointer-speed-applied" ]
  [[ "$output" == *'pointer speed is unknown'* ]]
}
