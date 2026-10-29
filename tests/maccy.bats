#!/usr/bin/env bats
#
# Maccy: the ⌃⌥V shortcut run_after_57-maccy writes, and the restart that
# makes a running Maccy pick it up.
#
# Nothing here touches this Mac. HOME is temporary, so Maccy's container is a
# folder the test creates; Applications is a folder the test fills in.
# `defaults` is a stub over a directory of key files that logs every write.
# Whether Maccy runs is a file: `pgrep` answers from it, `osascript`'s quit
# removes it unless the test makes Maccy refuse, and `open` creates it.

setup() {
  load helpers
  isolate_home
  chezmoi_config true false false

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  export DEFAULTS_STORE="$BATS_TEST_TMPDIR/defaults"
  export DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults.log"
  export RUNNING="$BATS_TEST_TMPDIR/maccy-running"  # exists while Maccy runs
  export STUBBORN="$BATS_TEST_TMPDIR/maccy-stubborn" # exists while quit fails
  export CONTAINER="$HOME/Library/Containers/org.p0deje.Maccy"
  mkdir -p "$DOTFILES_STATE" "$DOTFILES_APPLICATIONS" "$DEFAULTS_STORE"

  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_57-maccy.sh.tmpl"
  LOG="$BATS_TEST_TMPDIR/commands.log"
  : >"$LOG" "$DEFAULTS_LOG"

  stub defaults <<'EOF'
key="$DEFAULTS_STORE/$2.$3"
case "$1" in
read)
  [ -f "$key" ] || {
    echo "The domain/default pair of ($2, $3) does not exist" >&2
    exit 1
  }
  cat "$key"
  ;;
write)
  printf '%s %s %s %s\n' "$2" "$3" "$4" "$5" >>"$DEFAULTS_LOG"
  printf '%s\n' "$5" >"$key"
  ;;
*)
  echo "unexpected: defaults $*" >&2
  exit 64
  ;;
esac
EOF
  # A Maccy that runs has its container: the system creates it at launch.
  stub pgrep "$LOG" <<'EOF'
[ -e "$RUNNING" ] || exit 1
mkdir -p "$CONTAINER"
echo 4242
EOF
  stub osascript "$LOG" <<'EOF'
[ -e "$STUBBORN" ] || rm -f "$RUNNING"
EOF
  stub open "$LOG" <<'EOF'
: >"$RUNNING"
EOF
  export DOTFILES_PGREP="$STUB_BIN/pgrep"
  export DOTFILES_OSASCRIPT="$STUB_BIN/osascript"
  export DOTFILES_OPEN="$STUB_BIN/open"
}

# ⌃⌥V as Maccy's recorder stores it, read off the managed Mac.
SHORTCUT='{"carbonKeyCode":9,"carbonModifiers":6144}'

maccy() {
  local script="$BATS_TEST_TMPDIR/maccy.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

installed() {
  mkdir -p "$DOTFILES_APPLICATIONS/Maccy.app/Contents/MacOS"
}

has_run() {
  mkdir -p "$CONTAINER/Data/Library/Preferences"
}

running() {
  : >"$RUNNING"
}

# preset <value as `defaults read` prints it>
preset() {
  printf '%s\n' "$1" >"$DEFAULTS_STORE/org.p0deje.Maccy.KeyboardShortcuts_popup"
}

says() { [[ "$output" == *"$1"* ]]; }
ran() { grep -qF "$1" "$LOG"; }
wrote() { grep -qxF "org.p0deje.Maccy KeyboardShortcuts_popup -string $SHORTCUT" "$DEFAULTS_LOG"; }
wrote_nothing() { [ ! -s "$DEFAULTS_LOG" ]; }

@test "without Maccy nothing is run, written or said" {
  maccy
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  wrote_nothing
  [ ! -s "$LOG" ]
}

@test "a Maccy that has never run gets no write, and is told to run once" {
  installed
  maccy
  [ "$status" -eq 0 ]
  wrote_nothing
  says 'has not run yet'
  says 'chezmoi apply'
}

@test "a Maccy the agent just launched is waited for, then set and restarted" {
  installed
  running
  maccy
  [ "$status" -eq 0 ]
  wrote
  ran 'osascript -e tell application "Maccy" to quit'
  ran 'open -g -a Maccy'
  says 'Maccy restarted'
}

@test "a stopped Maccy gets the shortcut and stays stopped" {
  installed
  has_run
  maccy
  [ "$status" -eq 0 ]
  wrote
  ! ran 'osascript'
  ! ran 'open'
  says 'applies when Maccy starts'
}

@test "a running Maccy with another shortcut is set, quit, then opened again" {
  installed
  has_run
  running
  preset '{"carbonKeyCode":8,"carbonModifiers":768}'
  maccy
  [ "$status" -eq 0 ]
  wrote
  [ "$(grep -n 'osascript' "$LOG" | head -n 1 | cut -d : -f 1)" -lt "$(grep -n '^open ' "$LOG" | cut -d : -f 1)" ]
  [ -e "$RUNNING" ]
  says 'shortcut set to ⌃⌥V and Maccy restarted'
}

@test "a Maccy that already has ⌃⌥V is left alone, quietly" {
  installed
  has_run
  running
  preset "$SHORTCUT"
  maccy
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  wrote_nothing
  ! ran 'osascript'
  ! ran 'open'
}

@test "a Maccy that does not quit is reported and not opened twice" {
  installed
  has_run
  running
  : >"$STUBBORN"
  maccy
  [ "$status" -eq 0 ]
  wrote
  ! ran 'open'
  says 'did not quit'
}
