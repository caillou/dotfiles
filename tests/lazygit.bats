#!/usr/bin/env bats
#
# lazygit's config: the one setting it carries, and that lazygit's own state
# and cache files next to it stay out of chezmoi's hands.

setup() {
  load helpers
  isolate_home
}

# apply -> writes every managed file into the isolated home directory
apply() {
  chezmoi_config false false false
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" \
    --destination "$HOME" apply --exclude scripts
  [ "$status" -eq 0 ]
}

@test "the config is written with the VS Code edit preset" {
  apply
  [ -f "$HOME/.config/lazygit/config.yml" ]
  run grep -q "editPreset: 'vscode'" "$HOME/.config/lazygit/config.yml"
  [ "$status" -eq 0 ]
}

@test "chezmoi manages the config but never the state or the PR cache" {
  chezmoi_config false false false
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" \
    --destination "$HOME" managed
  [ "$status" -eq 0 ]
  [[ "$output" == *".config/lazygit/config.yml"* ]]
  [[ "$output" != *"lazygit/state.yml"* ]]
  [[ "$output" != *"github_pull_requests.json"* ]]
}

@test "lazygit reads the managed config and leaves it untouched" {
  command -v lazygit >/dev/null 2>&1 || skip 'lazygit is not installed'
  apply
  cp "$HOME/.config/lazygit/config.yml" "$BATS_TEST_TMPDIR/config-as-applied.yml"

  # `--print-config-dir` is a local read that loads the config and exits;
  # a load that rewrote the file would stop every later apply at an
  # overwrite prompt.
  run lazygit --print-config-dir
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/lazygit" ]
  run cmp "$BATS_TEST_TMPDIR/config-as-applied.yml" "$HOME/.config/lazygit/config.yml"
  [ "$status" -eq 0 ]
}
