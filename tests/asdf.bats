#!/usr/bin/env bats
#
# asdf: the pinned versions file, the asdfrc, and the script that adds the
# plugins and installs the pins.
#
# Nothing here installs a plugin or a runtime: `asdf` is a stub whose whole
# world is a temporary directory, and HOME is a temporary directory too.

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_ASDF="$BATS_TEST_TMPDIR/bin/asdf"

  # The stub reads this itself, so the heredoc below needs no escaping.
  export ASDF_STUB_DATA="$BATS_TEST_TMPDIR/asdf-data"
  mkdir -p "$ASDF_STUB_DATA"
  ASDF_STUB_LOG="$BATS_TEST_TMPDIR/asdf.log"

  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_40-asdf.sh.tmpl"
  TOOL_VERSIONS="$REPO_ROOT/dot_tool-versions"
  ASDFRC="$REPO_ROOT/dot_asdfrc"
}

# stub_asdf -> an asdf that logs its arguments and keeps its plugins and
# installs as directories, so the script's own checks see the state it made.
stub_asdf() {
  stub asdf "$ASDF_STUB_LOG" <<'EOF'
case "$1" in
plugin)
  case "$2" in
  list) ls -1 "$ASDF_STUB_DATA/plugins" 2>/dev/null ;;
  add)
    [ -z "${ASDF_STUB_FAIL_ADD:-}" ] || { echo "stub: plugin add failed" >&2; exit 1; }
    mkdir -p "$ASDF_STUB_DATA/plugins/$3"
    ;;
  esac
  ;;
list) ls -1 "$ASDF_STUB_DATA/installs/$2" 2>/dev/null | sed 's/^/  /' ;;
install)
  [ -z "${ASDF_STUB_FAIL_INSTALL:-}" ] || { echo "stub: install failed" >&2; exit 1; }
  [ -d "$ASDF_STUB_DATA/plugins/$2" ] || { echo "stub: plugin $2 not added" >&2; exit 1; }
  mkdir -p "$ASDF_STUB_DATA/installs/$2/$3"
  ;;
reshim) ;;
*)
  echo "stub: unexpected subcommand $1" >&2
  exit 2
  ;;
esac
EOF
}

# pin <plugin> <version>...  -> the home copy of ~/.tool-versions
pin() {
  : >"$HOME/.tool-versions"
  while [ "$#" -gt 1 ]; do
    printf '%s %s\n' "$1" "$2" >>"$HOME/.tool-versions"
    shift 2
  done
}

# apply_tool_versions -> the repo's pins, as chezmoi would write them
apply_tool_versions() {
  cp "$TOOL_VERSIONS" "$HOME/.tool-versions"
}

# asdf_script -> runs the rendered script
asdf_script() {
  chezmoi_config false false false
  local script="$BATS_TEST_TMPDIR/asdf.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

# logged <asdf arguments>  -> did the stub record exactly that call?
logged() {
  grep -qxF "asdf $1" "$ASDF_STUB_LOG"
}

refute_logged() {
  ! grep -qxF "asdf $1" "$ASDF_STUB_LOG"
}

# logged_pins -> every plugin in the repo's versions file was added and its
# version installed; the file is the source, so a changed pin changes nothing
# here.
logged_pins() {
  while read -r plugin version; do
    logged "plugin add $plugin"
    logged "install $plugin $version"
  done <"$TOOL_VERSIONS"
}

# --- the pinned versions ---------------------------------------------------

@test "every pin is a plugin and a single explicit version" {
  [ -s "$TOOL_VERSIONS" ]
  while read -r plugin version extra; do
    [ -n "$plugin" ]
    [ -z "$extra" ]
    # No "latest", no ranges: a pin the script can check for.
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  done <"$TOOL_VERSIONS"
}

@test "the asdfrc turns on legacy version files" {
  run cat "$ASDFRC"
  [ "$output" = 'legacy_version_file = yes' ]
}

@test "chezmoi writes both files into the home directory" {
  chezmoi_config false false false
  local dest="$BATS_TEST_TMPDIR/dest"
  mkdir -p "$dest"
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$dest" managed
  [ "$status" -eq 0 ]
  [[ "$output" == *'.tool-versions'* ]]
  [[ "$output" == *'.asdfrc'* ]]
}

@test "neither file is a template, so chezmoi re-add works on them" {
  [ ! -e "$TOOL_VERSIONS.tmpl" ]
  [ ! -e "$ASDFRC.tmpl" ]
}

# --- a fresh machine -------------------------------------------------------

@test "a fresh machine adds both plugins and installs the pinned versions" {
  stub_asdf
  apply_tool_versions
  asdf_script
  [ "$status" -eq 0 ]
  logged_pins
  logged 'reshim'
  [ -f "$DOTFILES_STATE/asdf.hash" ]
}

@test "the versions come from the file, not from the script" {
  stub_asdf
  pin ruby 3.4.1
  asdf_script
  [ "$status" -eq 0 ]
  logged 'plugin add ruby'
  logged 'install ruby 3.4.1'
  ! grep -q '^asdf install nodejs' "$ASDF_STUB_LOG"
}

@test "an already added plugin is not added again" {
  stub_asdf
  mkdir -p "$ASDF_STUB_DATA/plugins/nodejs"
  pin nodejs 24.15.0
  asdf_script
  [ "$status" -eq 0 ]
  refute_logged 'plugin add nodejs'
  logged 'install nodejs 24.15.0'
}

@test "an already installed version is not installed again" {
  stub_asdf
  mkdir -p "$ASDF_STUB_DATA/plugins/python" "$ASDF_STUB_DATA/installs/python/3.12.13"
  pin python 3.12.13
  asdf_script
  [ "$status" -eq 0 ]
  refute_logged 'install python 3.12.13'
  logged 'reshim'
}

# --- re-running ------------------------------------------------------------

@test "a second run installs nothing and says so" {
  stub_asdf
  apply_tool_versions
  asdf_script
  [ "$status" -eq 0 ]
  local changes
  changes="$(grep -cE '^asdf (plugin add|install|reshim)' "$ASDF_STUB_LOG")"

  asdf_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'the pinned versions are installed'* ]]
  # Only the read-only checks ran: nothing was added, installed or reshimmed.
  [ "$(grep -cE '^asdf (plugin add|install|reshim)' "$ASDF_STUB_LOG")" -eq "$changes" ]
}

@test "a changed pin installs the new version and reshims" {
  stub_asdf
  pin nodejs 24.15.0
  asdf_script
  pin nodejs 24.15.1
  asdf_script
  [ "$status" -eq 0 ]
  logged 'install nodejs 24.15.1'
  [ "$(grep -c '^asdf reshim$' "$ASDF_STUB_LOG")" -eq 2 ]
}

@test "a version that disappeared is reinstalled even though the file is unchanged" {
  stub_asdf
  pin nodejs 24.15.0
  asdf_script
  rm -rf "$ASDF_STUB_DATA/installs/nodejs"
  asdf_script
  [ "$status" -eq 0 ]
  [ "$(grep -c '^asdf install nodejs 24.15.0$' "$ASDF_STUB_LOG")" -eq 2 ]
}

# --- what it must never do -------------------------------------------------

@test "the script only ever reads, adds, installs and reshims" {
  stub_asdf
  apply_tool_versions
  asdf_script
  [ "$status" -eq 0 ]
  # `asdf set` would write ~/.tool-versions, which chezmoi manages: the home
  # copy would then drift from the repo on the next apply.
  while read -r _ subcommand _; do
    case "$subcommand" in
    plugin | list | install | reshim) ;;
    *) return 1 ;;
    esac
  done <"$ASDF_STUB_LOG"
}

@test "the home copy of the versions file is left untouched" {
  stub_asdf
  apply_tool_versions
  asdf_script
  [ "$status" -eq 0 ]
  run diff "$TOOL_VERSIONS" "$HOME/.tool-versions"
  [ "$status" -eq 0 ]
}

# --- when things are missing or broken -------------------------------------

@test "without asdf the script does nothing and the apply continues" {
  export DOTFILES_ASDF="$BATS_TEST_TMPDIR/bin/absent-asdf"
  apply_tool_versions
  asdf_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'not installed'* ]]
  [ ! -f "$DOTFILES_STATE/asdf.hash" ]
}

@test "without a versions file the script does nothing" {
  stub_asdf
  asdf_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'nothing to pin'* ]]
  [ ! -f "$ASDF_STUB_LOG" ]
  [ ! -f "$DOTFILES_STATE/asdf.hash" ]
}

@test "a failing install does not abort the apply and is retried next time" {
  stub_asdf
  export ASDF_STUB_FAIL_INSTALL=1
  apply_tool_versions
  asdf_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'something did not install. The next `chezmoi apply` installs the pinned versions.'* ]]
  [ ! -f "$DOTFILES_STATE/asdf.hash" ]

  unset ASDF_STUB_FAIL_INSTALL
  asdf_script
  [ "$status" -eq 0 ]
  logged_pins
  [ -f "$DOTFILES_STATE/asdf.hash" ]
}

@test "a failing plugin add does not abort the apply" {
  stub_asdf
  export ASDF_STUB_FAIL_ADD=1
  apply_tool_versions
  asdf_script
  [ "$status" -eq 0 ]
  [ ! -f "$DOTFILES_STATE/asdf.hash" ]
}

# --- the shell init the shell issue owns -----------------------------------

# shell_files -> the managed fish and zsh startup files
shell_files() {
  find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o \
    -path "$REPO_ROOT/docs" -prune -o \
    -path "$REPO_ROOT/tests" -prune -o \
    -type f \( -name 'config.fish' -o -name '*zprofile*' \) -print
}

@test "no managed file sources the retired git-clone asdf" {
  run bash -c "grep -rIl -e 'asdf\.fish' -e 'asdf\.sh' '$REPO_ROOT' \
    --exclude-dir=.git --exclude-dir=docs --exclude-dir=tests || true"
  [ "$output" = '' ]
}

@test "the shell init puts the asdf shims on the path" {
  local files
  files="$(shell_files)"
  # A renamed startup file must fail here, not pass by finding nothing.
  [ -n "$files" ]
  while read -r file; do
    grep -q '\.asdf/shims' "$file"
  done <<<"$files"
}
