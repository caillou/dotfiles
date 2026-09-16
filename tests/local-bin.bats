#!/usr/bin/env bats
#
# ~/.local: the folders Hammerspoon's `hs` installer needs, and the `code`
# symlink that stands in for the Homebrew cask's on a managed Mac.
#
# HOME is temporary and the apply is scoped to ~/.local, so no script runs and
# nothing on this Mac is read: Applications is a folder the test fills in.

setup() {
  load helpers
  isolate_home
  chezmoi_config false false false
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$DOTFILES_APPLICATIONS"
}

apply_local() {
  chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$HOME" \
    apply --exclude scripts "$HOME/.local"
}

# install_vscode -> a bundle with the launcher where the real one keeps it
install_vscode() {
  LAUNCHER="$DOTFILES_APPLICATIONS/Visual Studio Code.app/Contents/Resources/app/bin/code"
  mkdir -p "$(dirname "$LAUNCHER")"
  : >"$LAUNCHER"
}

# --- the folders the hs installer needs ------------------------------------

@test "an apply creates the two folders the hs installer links into" {
  run apply_local
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/bin" ]
  [ -d "$HOME/.local/share/man/man1" ]
}

@test "the .keep files create their folders and are never written" {
  run apply_local
  [ ! -e "$HOME/.local/bin/.keep" ]
  [ ! -e "$HOME/.local/share/man/man1/.keep" ]
}

@test "the folders are not exact_, so what lands there by other means stays" {
  mkdir -p "$HOME/.local/bin"
  : >"$HOME/.local/bin/claude"
  run apply_local
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/claude" ]
}

# --- the code symlink --------------------------------------------------------

@test "without VS Code there is no code link, dangling or otherwise" {
  run apply_local
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/code" ]
  [ ! -L "$HOME/.local/bin/code" ]
}

@test "with VS Code installed, code links to the launcher inside the bundle" {
  install_vscode
  run apply_local
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/code" ]
  [ "$(readlink "$HOME/.local/bin/code")" = "$LAUNCHER" ]
}

@test "the link appears on the apply after the app arrives" {
  run apply_local
  [ ! -L "$HOME/.local/bin/code" ]
  install_vscode
  run apply_local
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/code" ]
}

@test "a settled ~/.local has nothing left to do" {
  install_vscode
  run apply_local
  # stderr carries chezmoi's config-template warning on a machine whose config
  # predates the template; only stdout says whether anything would change.
  run --separate-stderr chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" \
    --destination "$HOME" apply --exclude scripts --dry-run --verbose "$HOME/.local"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the README says the same ----------------------------------------------

@test "the README explains both the link and the .keep files" {
  run cat "$REPO_ROOT/README.md"
  [[ "$output" == *'symlink_code.tmpl'* ]]
  [[ "$output" == *'dot_local/bin/.keep'* ]]
  [[ "$output" == *'dot_local/share/man/man1/.keep'* ]]
}
