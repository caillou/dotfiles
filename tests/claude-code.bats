#!/usr/bin/env bats
#
# Claude Code: the guarded native installer.
#
# Nothing here can install the CLI or reach the network: curl and bash are
# stubs behind the script's seams and on PATH as well, the installer body is a
# file the test wrote itself, and HOME is a temporary directory, so the guard
# never sees the claude of the machine running these tests.

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"

  LOG="$BATS_TEST_TMPDIR/installer.log"
  RAN="$BATS_TEST_TMPDIR/ran-installer.sh"
  CLAUDE="$HOME/.local/bin/claude"
  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_45-claude-code.sh.tmpl"

  INSTALLER_BODY='#!/bin/bash
echo "would install Claude Code"
'
  stub_bash
  stub_curl 0 "$INSTALLER_BODY"
  export DOTFILES_CURL="$STUB_BIN/curl"
  export DOTFILES_BASH="$STUB_BIN/bash"
}

# stub_curl <exit code> [body]  -> a curl that writes body to its -o target
stub_curl() {
  local body="$BATS_TEST_TMPDIR/curl-body"
  printf '%s' "${2:-}" >"$body"
  stub curl "$LOG" "${1:-0}" <<EOF
target=
while [ "\$#" -gt 0 ]; do
  case "\$1" in
  -o) target="\$2" ;;
  esac
  shift
done
[ -z "\$target" ] || cat "$body" >"\$target"
EOF
}

# stub_bash [outcome]  -> a bash that logs the file it was handed and keeps a
# copy of it, so a test can prove the script ran what it downloaded. The
# default outcome creates the link the real installer creates; `nothing` exits
# zero having installed nothing, `fail` exits non-zero.
stub_bash() {
  stub bash "$LOG" <<EOF
cat "\$1" >"$RAN"
case "${1:-install}" in
install)
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\nexit 0\n' >"$CLAUDE"
  chmod +x "$CLAUDE"
  ;;
fail) exit 3 ;;
esac
EOF
}

# claude_code  -> runs the rendered script against the stubs
claude_code() {
  local script="$BATS_TEST_TMPDIR/claude-code.sh"
  render --file "$SCRIPT" >"$script"
  PATH="$STUB_BIN:/usr/bin:/bin" run sh "$script"
}

# logged curl  -> did a stub record a call?
logged() {
  [ -f "$LOG" ] && grep -q "^$1" "$LOG"
}

# retry_message  -> one line, named for the script, ending in the repo's
# retry sentence
retry_message() {
  [[ "$output" == claude-code:* ]] || return 1
  [[ "$output" == *'The next `chezmoi apply` downloads the installer again.'* ]]
}

# --- the rendered script ---------------------------------------------------

@test "the installer is downloaded to a file and checked before it is run" {
  run render --file "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'https://claude.ai/install.sh'* ]]
  # The download lands in a file, and bash is handed that file. Piping curl
  # into `bash -c` is the defect the Homebrew installer already carries a
  # guard against: it turns a captive portal into a silent success.
  [[ "$output" == *'-fsSL "$URL" -o "$installer"'* ]]
  [[ "$output" == *'"${DOTFILES_BASH:-/bin/bash}" "$installer"'* ]]
  [[ "$output" != *'bash -c'* ]]
  # Both halves of the guard: PATH, and the link the installer creates, which
  # the preamble does not put on PATH.
  [[ "$output" == *'has_command claude || [ -x "$CLAUDE" ]'* ]]
  [[ "$output" == *'CLAUDE="$HOME/.local/bin/claude"'* ]]
}

@test "the script is the same on a managed and on an unmanaged Mac" {
  # The CLI goes on both Macs, so nothing in the script may read a fact. The
  # preamble's MANAGED line is the only rendered difference allowed.
  chezmoi_config true false false
  render --file "$SCRIPT" | grep -v '^MANAGED=' >"$BATS_TEST_TMPDIR/managed.sh"
  chezmoi_config false true true
  render --file "$SCRIPT" | grep -v '^MANAGED=' >"$BATS_TEST_TMPDIR/personal.sh"
  run diff "$BATS_TEST_TMPDIR/managed.sh" "$BATS_TEST_TMPDIR/personal.sh"
  [ "$status" -eq 0 ]
  # The template itself names no fact either, in a branch or in a value. Only
  # the include does, and that is the preamble every script carries.
  run grep -c 'is_managed\|\.managed\|\.personal\|\.embedded' "$SCRIPT"
  [ "$output" = 0 ]
}

# --- the guard -------------------------------------------------------------

@test "an installed CLI is left alone" {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\nexit 0\n' >"$CLAUDE"
  chmod +x "$CLAUDE"

  claude_code
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  [ ! -f "$LOG" ]
}

@test "a claude on PATH is left alone even without the link" {
  stub claude

  claude_code
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  [ ! -f "$LOG" ]
  [ ! -e "$CLAUDE" ]
}

# --- installing ------------------------------------------------------------

@test "a missing CLI is installed from the downloaded file" {
  claude_code
  [ "$status" -eq 0 ]
  logged curl
  logged bash
  [[ "$output" == *'installing the CLI'* ]]
  # bash ran the downloaded file itself, and the copy is gone afterwards.
  [ "$(cat "$RAN")" = "$(printf '%s' "$INSTALLER_BODY")" ]
  local ran
  ran="$(sed -n 's/^bash //p' "$LOG")"
  [ -n "$ran" ]
  [ ! -e "$ran" ]
  [ -x "$CLAUDE" ]
}

@test "an empty download is reported and the apply continues" {
  stub_curl 0 ''
  claude_code
  [ "$status" -eq 0 ]
  [[ "$output" == *'empty'* ]]
  retry_message
  ! logged bash
  [ ! -e "$CLAUDE" ]
}

@test "a failed download is reported and the apply continues" {
  stub_curl 6 ''
  claude_code
  [ "$status" -eq 0 ]
  [[ "$output" == *'could not download the installer'* ]]
  retry_message
  ! logged bash
  [ ! -e "$CLAUDE" ]
}

@test "a download that is not a shell script is reported" {
  # What a captive portal hands back instead of the installer.
  stub_curl 0 '<html><body>Sign in to continue</body></html>
'
  claude_code
  [ "$status" -eq 0 ]
  [[ "$output" == *'not a shell script'* ]]
  retry_message
  ! logged bash
  [ ! -e "$CLAUDE" ]
}

@test "a failing installer is reported and the apply continues" {
  stub_bash fail
  claude_code
  [ "$status" -eq 0 ]
  [[ "$output" == *'the installer failed'* ]]
  retry_message
  [ ! -e "$CLAUDE" ]
}

@test "an installer that leaves no CLI behind is reported" {
  stub_bash nothing
  claude_code
  [ "$status" -eq 0 ]
  logged bash
  [[ "$output" == *"left no $CLAUDE"* ]]
  retry_message
  [ ! -e "$CLAUDE" ]
}
