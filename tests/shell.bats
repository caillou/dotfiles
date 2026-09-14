#!/usr/bin/env bats
#
# The shell: what the managed fish, zsh and bash files say, what a real shell
# makes of them on a clean home, and what the two shell scripts do to a
# machine.
#
# Nothing here touches the real home directory, the real /etc/shells or the
# real login record: HOME and every XDG_*_HOME point into the test's temporary
# directory, and fish, dscl, chsh and sudo are stubs.

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_FISH="$BATS_TEST_TMPDIR/bin/fish"
  export DOTFILES_SHELLS="$BATS_TEST_TMPDIR/shells"

  FISH_SOURCE="$REPO_ROOT/dot_config/private_fish"
  PLUGINS_SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_20-fish-plugins.sh.tmpl"
  LOGIN_SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_21-login-shell.sh.tmpl"
  LOG="$BATS_TEST_TMPDIR/calls.log"
  SHELL_RECORD="$BATS_TEST_TMPDIR/login-record"
  DEST="$BATS_TEST_TMPDIR/dest"
}

# The files this issue manages, as source paths.
managed_shell_files() {
  cat <<EOF
$FISH_SOURCE/config.fish
$FISH_SOURCE/conf.d/00-settings.fish
$FISH_SOURCE/conf.d/fish_frozen_theme.fish
$FISH_SOURCE/functions/amph.fish
$FISH_SOURCE/functions/karabinerRestart.fish
$FISH_SOURCE/fish_plugins
$REPO_ROOT/dot_zprofile
$REPO_ROOT/dot_zshrc
$REPO_ROOT/dot_bash_profile
$REPO_ROOT/dot_bashrc
$REPO_ROOT/dot_inputrc
EOF
}

# The same files as home-relative targets.
managed_shell_targets() {
  cat <<'EOF'
.config/fish/config.fish
.config/fish/conf.d/00-settings.fish
.config/fish/conf.d/fish_frozen_theme.fish
.config/fish/functions/amph.fish
.config/fish/functions/karabinerRestart.fish
.config/fish/fish_plugins
.zprofile
.zshrc
.bash_profile
.bashrc
.inputrc
EOF
}

# apply_shell_files -> the managed files written into a throwaway destination
apply_shell_files() {
  chezmoi_config false false false
  mkdir -p "$DEST"
  # Scripts are excluded on purpose: this checks the file targets, and the
  # scripts have their own tests below that never run the real commands.
  chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$DEST" \
    apply --exclude=scripts
}

# --- the managed files -----------------------------------------------------

@test "chezmoi writes every shell file to its home-relative target" {
  chezmoi_config false false false
  mkdir -p "$DEST"
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$DEST" managed
  [ "$status" -eq 0 ]
  while read -r target; do
    grep -qxF "$target" <<<"$output"
  done <<<"$(managed_shell_targets)"
}

@test "machine state fish owns is never managed" {
  chezmoi_config false false false
  mkdir -p "$DEST"
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$DEST" managed
  [ "$status" -eq 0 ]
  # Universal variables, the key-bindings file fish 4.3 froze and everything
  # the plugins own are rewritten by fish or by fisher, not by us.
  for target in .config/fish/fish_variables .config/fish/fishfile \
    .config/fish/conf.d/fish_frozen_key_bindings.fish \
    .config/fish/conf.d/pure.fish .config/fish/conf.d/z.fish \
    .config/fish/conf.d/fzf.fish .config/fish/completions; do
    ! grep -qxF "$target" <<<"$output"
  done
}

@test "no managed shell file contains an absolute home path" {
  while read -r file; do
    run grep -n '/Users/' "$file"
    [ "$status" -ne 0 ]
  done <<<"$(managed_shell_files)"
}

@test "a clean home gets the fish files, with fish's own directory private" {
  apply_shell_files
  while read -r target; do
    [ -f "$DEST/$target" ]
  done <<<"$(managed_shell_targets)"
  # ~/.config/fish is 0700 on this Mac; chezmoi would otherwise relax it.
  [ "$(stat -f %Lp "$DEST/.config/fish")" = 700 ]
}

@test "fish_plugins lists the three plugins, and fisher, which reconciles it" {
  # fisher rewrites this file from its own universal variable after every
  # install or update, appending itself when it is missing. Leaving it out
  # would make `fisher update` uninstall fisher on the next plugin change.
  run cat "$FISH_SOURCE/fish_plugins"
  [ "$output" = 'jethrokuan/z
pure-fish/pure
jethrokuan/fzf
jorgebucaran/fisher' ]
}

@test "config.fish sets up Homebrew, the locale, the pager and the asdf shims" {
  run cat "$FISH_SOURCE/config.fish"
  [[ "$output" == *'eval $(/opt/homebrew/bin/brew shellenv)'* ]]
  [[ "$output" == *'set -x LANG en_US.UTF-8'* ]]
  [[ "$output" == *'set -x LESS -R'* ]]
  [[ "$output" == *'set -x MORE -R'* ]]
  [[ "$output" == *'share/fish/vendor_completions.d'* ]]
  [[ "$output" == *'set -gx --prepend PATH ~/.asdf/shims'* ]]
  [[ "$output" == *'set PATH $PATH ~/.local/bin'* ]]
}

@test "config.fish drops the paths and the asdf install that no longer exist" {
  run grep -c -e '~/\.bin' -e 'asdf\.fish' "$FISH_SOURCE/config.fish"
  [ "$output" = 0 ]
}

@test "config.fish only sources Docker's helper when Docker wrote one" {
  run grep -A1 'test -f ~/.docker/init-fish.sh' "$FISH_SOURCE/config.fish"
  [[ "$output" == *'source ~/.docker/init-fish.sh'* ]]
}

@test "config.fish carries every abbreviation" {
  run grep -c '^abbr -a -- ' "$FISH_SOURCE/config.fish"
  [ "$output" = 21 ]
  for name in a ag c d e g gb gc gd ggl ggp glog gr gs j more t unifi w wr watt; do
    grep -q "^abbr -a -- $name " "$FISH_SOURCE/config.fish"
  done
}

@test "the conf.d settings file keeps only what the universal variables kept" {
  run cat "$FISH_SOURCE/conf.d/00-settings.fish"
  [[ "$output" == *'set -gx XDG_CONFIG_HOME $HOME/.config'* ]]
  [[ "$output" == *'set -g fish_emoji_width 2'* ]]
  # Every pure_* universal variable on this Mac holds Pure's own default, so
  # the set that differs is empty. A Pure option appearing here later has to
  # be a deliberate edit with the diff to back it up.
  run grep -c '^set .*pure_' "$FISH_SOURCE/conf.d/00-settings.fish"
  [ "$output" = 0 ]
}

@test "the frozen theme file keeps the Ayu Dark colours" {
  run cat "$FISH_SOURCE/conf.d/fish_frozen_theme.fish"
  [[ "$output" == *'set --global fish_color_command 39BAE6'* ]]
  [[ "$output" == *'set --global fish_color_normal B3B1AD'* ]]
  [[ "$output" == *'set --global fish_color_cwd 59C2FF'* ]]
}

@test "every managed fish file is valid fish" {
  command -v fish >/dev/null || skip "fish is not installed"
  for file in "$FISH_SOURCE/config.fish" "$FISH_SOURCE/conf.d/00-settings.fish" \
    "$FISH_SOURCE/conf.d/fish_frozen_theme.fish" \
    "$FISH_SOURCE/functions/amph.fish" \
    "$FISH_SOURCE/functions/karabinerRestart.fish"; do
    run fish --no-execute "$file"
    [ "$status" -eq 0 ]
  done
}

@test "a fresh fish on a clean home has the abbreviations and the settings" {
  local fish
  fish="$(command -v fish)" || skip "fish is not installed"
  apply_shell_files
  run env -i HOME="$DEST" PATH=/usr/bin:/bin TERM=dumb \
    XDG_CONFIG_HOME="$DEST/.config" XDG_DATA_HOME="$DEST/.local/share" \
    XDG_CACHE_HOME="$DEST/.cache" XDG_STATE_HOME="$DEST/.local/state" \
    "$fish" --command 'abbr --query gs; and echo abbreviations
echo $fish_emoji_width
echo $XDG_CONFIG_HOME
echo $LANG
string join \n $PATH'
  [ "$status" -eq 0 ]
  [[ "$output" == *'abbreviations'* ]]
  [[ "$output" == *'2'* ]]
  [[ "$output" == *"$DEST/.config"* ]]
  [[ "$output" == *'en_US.UTF-8'* ]]
  [[ "$output" == *"$DEST/.asdf/shims"* ]]
  [[ "$output" == *"$DEST/.local/bin"* ]]
  [[ "$output" == *'./node_modules/.bin'* ]]
}

@test "Claude Code's zsh tool shell finds Homebrew, the asdf shims and the locale" {
  apply_shell_files
  run env -i HOME="$DEST" ZDOTDIR="$DEST" PATH=/usr/bin:/bin TERM=dumb \
    /bin/zsh -l -c 'echo "$LANG"; echo "$XDG_CONFIG_HOME"; echo "$PATH"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'en_US.UTF-8'* ]]
  [[ "$output" == *"$DEST/.config"* ]]
  [[ "$output" == *"$DEST/.asdf/shims"* ]]
  [[ "$output" == *"$DEST/.local/bin"* ]]
  [[ "$output" == *'./node_modules/.bin'* ]]
  if [ -x /opt/homebrew/bin/brew ]; then
    [[ "$output" == *'/opt/homebrew/bin'* ]]
  fi
}

@test "the bash files keep the shims and lose the stray echo" {
  run cat "$REPO_ROOT/dot_bashrc"
  [[ "$output" == *'export PATH="$HOME/.asdf/shims:$PATH"'* ]]
  [[ "$output" != *'HAHAHAHAHA'* ]]
  run cat "$REPO_ROOT/dot_bash_profile"
  [[ "$output" == *'[ -f "$HOME/.docker/init-bash.sh" ] && source "$HOME/.docker/init-bash.sh"'* ]]
}

@test "the readline config keeps option-arrow word movement" {
  run cat "$REPO_ROOT/dot_inputrc"
  [[ "$output" == *'"\e\e[C": forward-word'* ]]
  [[ "$output" == *'"\e\e[D": backward-word'* ]]
}

# --- the fish-plugins script -----------------------------------------------

# stub_fish [fisher update exit code] -> a fish that installs nothing
#
# It models fisher's lifecycle: the bootstrap command makes `functions --query
# fisher` start succeeding, so a test can tell an install from an update.
stub_fish() {
  stub fish "$LOG" <<EOF
case "\$2" in
'functions --query fisher') [ -f "$BATS_TEST_TMPDIR/fisher-installed" ] || exit 1 ;;
'fisher update') exit ${1:-0} ;;
*)
  [ -z "\${STUB_BOOTSTRAP_FAILS:-}" ] || exit 1
  : >"$BATS_TEST_TMPDIR/fisher-installed"
  ;;
esac
EOF
}

fisher_is_installed() {
  : >"$BATS_TEST_TMPDIR/fisher-installed"
}

fish_plugins_script() {
  render --file "$PLUGINS_SCRIPT" >"$BATS_TEST_TMPDIR/fish-plugins.sh"
  run sh "$BATS_TEST_TMPDIR/fish-plugins.sh"
}

called() {
  grep -qF "$1" "$LOG"
}

refute_called() {
  ! grep -qF "$1" "$LOG"
}

@test "a machine without fisher gets it installed and the plugins reconciled" {
  stub_fish
  fish_plugins_script
  [ "$status" -eq 0 ]
  called 'fisher.fish | source && fisher install jorgebucaran/fisher'
  called 'fish --command fisher update'
  [ -f "$DOTFILES_STATE/fish-plugins.hash" ]
}

@test "a second apply with nothing changed leaves fisher alone" {
  stub_fish
  fish_plugins_script
  : >"$LOG"
  fish_plugins_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'nothing changed'* ]]
  refute_called 'fisher update'
}

@test "an edited fish_plugins reconciles again" {
  stub_fish
  fish_plugins_script
  printf 'not-the-hash\n' >"$DOTFILES_STATE/fish-plugins.hash"
  : >"$LOG"
  fish_plugins_script
  [ "$status" -eq 0 ]
  called 'fish --command fisher update'
  refute_called 'fisher install jorgebucaran/fisher'
}

@test "fisher removed by hand is reinstalled even when nothing changed" {
  stub_fish
  fish_plugins_script
  rm -f "$BATS_TEST_TMPDIR/fisher-installed"
  : >"$LOG"
  fish_plugins_script
  [ "$status" -eq 0 ]
  called 'fisher install jorgebucaran/fisher'
}

@test "a failed fisher update is retried on the next apply" {
  stub_fish 1
  fish_plugins_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'fisher update failed. The next `chezmoi apply` installs fisher and the plugins.'* ]]
  [ ! -f "$DOTFILES_STATE/fish-plugins.hash" ]

  stub_fish
  : >"$LOG"
  fish_plugins_script
  called 'fish --command fisher update'
  [ -f "$DOTFILES_STATE/fish-plugins.hash" ]
}

@test "a failed fisher bootstrap does not abort the apply" {
  stub_fish
  STUB_BOOTSTRAP_FAILS=1 fish_plugins_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'could not install fisher'* ]]
  [ ! -f "$DOTFILES_STATE/fish-plugins.hash" ]
}

@test "without fish the plugins script does nothing" {
  export DOTFILES_FISH="$BATS_TEST_TMPDIR/bin/absent-fish"
  fish_plugins_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'fish is not installed'* ]]
  [ ! -f "$DOTFILES_STATE/fish-plugins.hash" ]
}

@test "the plugins script pins the hash of the managed fish_plugins" {
  run render --file "$PLUGINS_SCRIPT"
  [ "$status" -eq 0 ]
  local hash
  hash="$(shasum -a 256 "$FISH_SOURCE/fish_plugins" | cut -d ' ' -f 1)"
  [[ "$output" == *"$hash"* ]]
}

# --- the login-shell script ------------------------------------------------

# stub_login_tools [chsh exit code]
#
# dscl reads and writes a file standing in for the login record, chsh writes
# the same file when it succeeds, and sudo logs and runs its arguments, so a
# broken guard still cannot reach the real machine.
stub_login_tools() {
  stub fish

  stub dscl "$LOG" <<EOF
case "\$2" in
-read) [ ! -f "$SHELL_RECORD" ] || printf 'UserShell: %s\n' "\$(cat "$SHELL_RECORD")" ;;
-create)
  [ -z "\${STUB_DSCL_CREATE_FAILS:-}" ] || exit 1
  printf '%s\n' "\$5" >"$SHELL_RECORD"
  ;;
esac
EOF

  stub chsh "$LOG" "${1:-0}" <<EOF
[ ${1:-0} -ne 0 ] || printf '%s\n' "\$2" >"$SHELL_RECORD"
EOF

  stub sudo "$LOG" <<'EOF'
exec "$@"
EOF
}

# The stubs are found on PATH: dscl, chsh and sudo have no seam.
login_shell_script() {
  render --file "$LOGIN_SCRIPT" >"$BATS_TEST_TMPDIR/login-shell.sh"
  run sh "$BATS_TEST_TMPDIR/login-shell.sh"
}

@test "a fresh Mac gets fish into /etc/shells and into the login record" {
  stub_login_tools
  printf '/bin/zsh\n' >"$SHELL_RECORD"
  printf '/bin/sh\n/bin/zsh\n' >"$DOTFILES_SHELLS"
  login_shell_script
  [ "$status" -eq 0 ]
  called "sudo tee -a $DOTFILES_SHELLS"
  [ "$(grep -c -x -F "$DOTFILES_FISH" "$DOTFILES_SHELLS")" -eq 1 ]
  called "chsh -s $DOTFILES_FISH"
  [ "$(cat "$SHELL_RECORD")" = "$DOTFILES_FISH" ]
}

@test "the login shell script is a no-op once fish is the login shell" {
  stub_login_tools
  printf '%s\n' "$DOTFILES_FISH" >"$SHELL_RECORD"
  printf '/bin/zsh\n%s\n' "$DOTFILES_FISH" >"$DOTFILES_SHELLS"
  login_shell_script
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  refute_called chsh
  refute_called sudo
  [ "$(cat "$DOTFILES_SHELLS")" = "/bin/zsh
$DOTFILES_FISH" ]
}

@test "re-running the login shell script changes nothing" {
  stub_login_tools
  printf '/bin/zsh\n' >"$SHELL_RECORD"
  : >"$DOTFILES_SHELLS"
  login_shell_script
  : >"$LOG"
  login_shell_script
  [ "$status" -eq 0 ]
  refute_called chsh
  [ "$(grep -c -x -F "$DOTFILES_FISH" "$DOTFILES_SHELLS")" -eq 1 ]
}

@test "fish already in /etc/shells is not appended twice" {
  stub_login_tools
  printf '/bin/zsh\n' >"$SHELL_RECORD"
  printf '%s\n' "$DOTFILES_FISH" >"$DOTFILES_SHELLS"
  login_shell_script
  [ "$status" -eq 0 ]
  refute_called 'sudo tee'
  called "chsh -s $DOTFILES_FISH"
}

@test "a federated account falls back to the directory record" {
  stub_login_tools 1
  printf '/bin/zsh\n' >"$SHELL_RECORD"
  : >"$DOTFILES_SHELLS"
  login_shell_script
  [ "$status" -eq 0 ]
  called "chsh -s $DOTFILES_FISH"
  called "sudo dscl . -create /Users/$(id -un) UserShell $DOTFILES_FISH"
  [ "$(cat "$SHELL_RECORD")" = "$DOTFILES_FISH" ]
}

@test "a login shell that cannot be changed does not abort the apply" {
  stub_login_tools 1
  printf '/bin/zsh\n' >"$SHELL_RECORD"
  : >"$DOTFILES_SHELLS"
  STUB_DSCL_CREATE_FAILS=1 login_shell_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'by hand'* ]]
}

@test "without fish the login shell script does nothing" {
  stub_login_tools
  export DOTFILES_FISH="$BATS_TEST_TMPDIR/bin/absent-fish"
  login_shell_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'fish is not installed'* ]]
  refute_called chsh
}
