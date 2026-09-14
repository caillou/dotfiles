#!/usr/bin/env bats
#
# Homebrew installer and packages: what the Brewfile says for a given machine,
# which casks and App Store apps the script appends to it, and how it records
# the outcome of `brew bundle`.
#
# Nothing here installs anything: `brew` is a stub, and the Applications folder
# and the Caskroom are temporary directories the tests fill in themselves.

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  export DOTFILES_CASKROOM="$BATS_TEST_TMPDIR/Caskroom"
  export DOTFILES_BREW="$BATS_TEST_TMPDIR/bin/brew"
  mkdir -p "$DOTFILES_APPLICATIONS" "$DOTFILES_CASKROOM"

  BREWLOG="$BATS_TEST_TMPDIR/brew.log"
  BREWFILE="$DOTFILES_STATE/Brewfile"
  PACKAGES="$REPO_ROOT/.chezmoiscripts/run_after_10-packages.sh.tmpl"
  HOMEBREW="$REPO_ROOT/.chezmoiscripts/run_once_before_00-homebrew.sh.tmpl"
}

# stub_brew [exit code] -> a brew that logs its arguments and installs nothing
stub_brew() {
  stub brew "$BREWLOG" "${1:-0}"
}

# packages <managed> <personal> <embedded>  -> runs the rendered script
packages() {
  chezmoi_config "${1:-false}" "${2:-false}" "${3:-false}"
  local script="$BATS_TEST_TMPDIR/packages.sh"
  render --file "$PACKAGES" >"$script"
  run sh "$script"
}

# installed <app bundle> [cask]  -> an app in Applications, optionally Homebrew's
installed() {
  mkdir -p "$DOTFILES_APPLICATIONS/$1"
  [ "$#" -lt 2 ] || mkdir -p "$DOTFILES_CASKROOM/$2"
}

brewfile_has() {
  grep -qxF "$1" "$BREWFILE"
}

refute_brewfile_has() {
  ! grep -qxF "$1" "$BREWFILE"
}

# --- the Brewfile template -------------------------------------------------

@test "every machine gets the core formulae, the taps and the fonts" {
  stub_brew
  for managed in true false; do
    packages "$managed"
    [ "$status" -eq 0 ]
    brewfile_has 'tap "jesseduffield/lazygit"'
    brewfile_has 'brew "chezmoi"'
    brewfile_has 'brew "fish"'
    brewfile_has 'brew "mas"'
    brewfile_has 'brew "jesseduffield/lazygit/lazygit"'
    brewfile_has 'brew "mactop"'
    brewfile_has 'cask "font-ibm-plex-mono"'
    brewfile_has 'cask "font-ibm-plex-sans"'
    brewfile_has 'cask "font-anonymice-nerd-font"'
  done
}

@test "a managed machine gets formulae and fonts only" {
  stub_brew
  packages true true true
  [ "$status" -eq 0 ]
  run grep -c '^mas ' "$BREWFILE"
  [ "$output" = 0 ]
  run grep '^cask ' "$BREWFILE"
  [ "$output" = 'cask "font-ibm-plex-mono"
cask "font-ibm-plex-sans"
cask "font-anonymice-nerd-font"' ]
}

@test "the personal group appears only when its flag is set" {
  stub_brew
  packages false false false
  refute_brewfile_has 'tap "gbevin/tools"'
  refute_brewfile_has 'brew "gbevin/tools/sendmidi"'
  refute_brewfile_has 'brew "figlet"'
  refute_brewfile_has 'cask "spotify"'
  refute_brewfile_has 'mas "WhatsApp", id: 310633997'

  packages false true false
  brewfile_has 'tap "gbevin/tools"'
  brewfile_has 'brew "gbevin/tools/sendmidi"'
  brewfile_has 'brew "figlet"'
  brewfile_has 'cask "spotify"'
  brewfile_has 'mas "WhatsApp", id: 310633997'
}

@test "the embedded group appears only when its flag is set" {
  stub_brew
  packages false false false
  refute_brewfile_has 'brew "platformio"'
  refute_brewfile_has 'cask "gcc-arm-embedded"'

  packages false false true
  brewfile_has 'brew "platformio"'
  brewfile_has 'brew "open-ocd"'
  brewfile_has 'brew "dfu-util"'
  brewfile_has 'cask "gcc-arm-embedded"'
}

# --- the cask filter -------------------------------------------------------

@test "a cask whose app is missing is installed" {
  stub_brew
  packages false
  brewfile_has 'cask "google-chrome"'
}

@test "an app installed by hand is left alone" {
  stub_brew
  installed "Google Chrome.app"
  packages false
  [ "$status" -eq 0 ]
  refute_brewfile_has 'cask "google-chrome"'
  [[ "$output" == *"leaving Google Chrome.app alone"* ]]
}

@test "an app Homebrew installed stays in the Brewfile" {
  stub_brew
  installed "Google Chrome.app" google-chrome
  packages false
  brewfile_has 'cask "google-chrome"'
}

@test "a cask that installs no app bundle is always listed" {
  stub_brew
  packages false
  brewfile_has 'cask "ngrok"'
}

@test "the App Store rows are not filtered by presence" {
  stub_brew
  installed "Amphetamine.app"
  packages false
  brewfile_has 'mas "Amphetamine", id: 937984704'
}

# --- running brew bundle ---------------------------------------------------

@test "brew bundle runs against the generated Brewfile" {
  stub_brew
  packages false
  [ "$status" -eq 0 ]
  [ "$(cat "$BREWLOG")" = "brew bundle --file $BREWFILE" ]
}

@test "a failing brew bundle lands in the marker and the apply continues" {
  stub_brew 17
  packages false
  [ "$status" -eq 0 ]
  [ "$(cat "$DOTFILES_STATE/packages-status")" = 17 ]
  [ -f "$DOTFILES_STATE/packages.hash" ]
}

@test "an unchanged Brewfile after a successful run does not run brew bundle" {
  stub_brew
  packages false
  packages false
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BREWLOG")" -eq 1 ]
  [[ "$output" == *"nothing changed"* ]]
}

@test "an unchanged Brewfile after a failed run runs brew bundle again" {
  stub_brew 17
  packages false
  stub_brew
  packages false
  [ "$(wc -l <"$BREWLOG")" -eq 2 ]
  [ "$(cat "$DOTFILES_STATE/packages-status")" = 0 ]
}

@test "a changed Brewfile runs brew bundle again" {
  stub_brew
  packages false
  packages false true
  [ "$(wc -l <"$BREWLOG")" -eq 2 ]
}

@test "without Homebrew the script writes the Brewfile and stops" {
  export DOTFILES_BREW="$BATS_TEST_TMPDIR/bin/absent-brew"
  packages false
  [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew is not installed"* ]]
  [ -f "$BREWFILE" ]
  [ ! -f "$DOTFILES_STATE/packages.hash" ]
}

# --- the app table ---------------------------------------------------------

# rows <expression> -> one line per row of .chezmoidata/apps.yaml
rows() {
  chezmoi_config false true true
  render "{{ range .apps }}$1{{ \"\n\" }}{{ end }}"
}

@test "every row of the table is a cask or an App Store app in a known group" {
  run rows '{{ .kind }} {{ .group }}'
  [ "$status" -eq 0 ]
  while read -r kind group; do
    case "$kind" in cask | mas) ;; *) return 1 ;; esac
    case "$group" in core | personal | embedded) ;; *) return 1 ;; esac
  done <<<"$output"
}

@test "the table names every package once and every App Store id is numeric" {
  run rows '{{ .name }}'
  [ "$(sort <<<"$output" | uniq -d)" = '' ]

  run rows '{{ .kind }} {{ .name }}'
  while read -r kind name; do
    case "$kind" in
    mas) case "$name" in *[!0-9]* | '') return 1 ;; esac ;;
    esac
  done <<<"$output"
}

# --- the Homebrew installer ------------------------------------------------
#
# Nothing here can install Homebrew: curl, sudo, bash and brew are stubs in a
# directory that replaces PATH, and HOMEBREW_PREFIX points at an empty
# directory so the guard does not find the Homebrew of the machine running
# these tests.

# installer_stubs  -> sudo, bash and a curl that downloads a real installer;
# call stub_curl afterwards for the failure cases.
installer_stubs() {
  INSTALLER_LOG="$BATS_TEST_TMPDIR/installer.log"
  INSTALLER_RAN="$BATS_TEST_TMPDIR/ran-installer.sh"

  stub sudo "$INSTALLER_LOG"

  # The bash stub keeps a copy of what it was handed, so a test can prove the
  # script ran the file it downloaded rather than anything else.
  stub bash "$INSTALLER_LOG" <<EOF
echo "NONINTERACTIVE=\${NONINTERACTIVE:-unset}" >>"$INSTALLER_LOG"
cat "\$1" >"$INSTALLER_RAN"
EOF

  INSTALLER_BODY='#!/bin/bash
echo "would install Homebrew"
'
  stub_curl 0 "$INSTALLER_BODY"
}

# stub_curl <exit code> [body]  -> a curl that writes body to its -o target
stub_curl() {
  local body="$BATS_TEST_TMPDIR/curl-body"
  printf '%s' "${2:-}" >"$body"
  stub curl "$INSTALLER_LOG" "${1:-0}" <<EOF
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

# homebrew  -> runs the rendered installer script against the stubs
homebrew() {
  local script="$BATS_TEST_TMPDIR/homebrew.sh"
  render --file "$HOMEBREW" >"$script"
  PATH="$STUB_BIN:/usr/bin:/bin" \
    HOMEBREW_PREFIX="$BATS_TEST_TMPDIR/no-homebrew" \
    DOTFILES_BASH="$STUB_BIN/bash" \
    run sh "$script"
}

# logged sudo  -> did a stub record a call?
logged() {
  [ -f "$INSTALLER_LOG" ] && grep -q "^$1" "$INSTALLER_LOG"
}

@test "the installer downloads to a file and checks it before running it" {
  run render --file "$HOMEBREW"
  [ "$status" -eq 0 ]
  [[ "$output" == *'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'* ]]
  # The download lands in a file, and bash is handed that file. Piping curl
  # into `bash -c` is the defect this guard exists for: it turns a failed
  # download into a successful run-once that chezmoi never repeats.
  [[ "$output" == *'-o "$installer"'* ]]
  [[ "$output" == *'NONINTERACTIVE=1 "${DOTFILES_BASH:-/bin/bash}" "$installer"'* ]]
  [[ "$output" != *'bash -c'* ]]
  # And the password comes after the download, not before it.
  [[ "${output#*curl}" == *'sudo -v'* ]]
}

@test "the installer does nothing when Homebrew is already there" {
  installer_stubs
  # brew on PATH is the only difference from the tests below: a broken guard
  # would reach the stubbed curl and sudo, and the log would show it.
  stub brew "$INSTALLER_LOG"

  homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *'already installed'* ]]
  [ ! -f "$INSTALLER_LOG" ]
}

@test "a downloaded installer is run from the file, once the password is asked" {
  installer_stubs
  homebrew
  [ "$status" -eq 0 ]
  logged sudo
  logged bash
  grep -qxF 'NONINTERACTIVE=1' "$INSTALLER_LOG"
  # bash ran the downloaded file itself, and the copy is gone afterwards.
  [ "$(cat "$INSTALLER_RAN")" = "$(printf '%s' "$INSTALLER_BODY")" ]
  local ran
  ran="$(sed -n 's/^bash //p' "$INSTALLER_LOG")"
  [ -n "$ran" ]
  [ ! -e "$ran" ]
}

@test "an empty download aborts the apply and costs no password" {
  installer_stubs
  stub_curl 0 ''
  homebrew
  [ "$status" -ne 0 ]
  [[ "$output" == *'empty'* ]]
  ! logged bash
  ! logged sudo
}

@test "a failed download aborts the apply and costs no password" {
  installer_stubs
  stub_curl 6 ''
  homebrew
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not download the installer'* ]]
  ! logged bash
  ! logged sudo
}

@test "a download that is not a shell script aborts the apply" {
  installer_stubs
  # What a captive portal hands back instead of the installer.
  stub_curl 0 '<html><body>Sign in to continue</body></html>
'
  homebrew
  [ "$status" -ne 0 ]
  [[ "$output" == *'not a shell script'* ]]
  ! logged bash
  ! logged sudo
}
