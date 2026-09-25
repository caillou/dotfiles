#!/usr/bin/env bats
#
# The shared script preamble (.chezmoitemplates/facts.sh), rendered the way a
# script inlines it, then exercised through its interface: every predicate and
# every marker helper, both outcomes each.

setup() {
  load helpers
  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$DOTFILES_APPLICATIONS"
}

@test "the preamble creates the state directory" {
  facts="$(render_facts)"
  [ ! -d "$DOTFILES_STATE" ]
  facts_probe "$facts" 'true'
  [ "$status" -eq 0 ]
  [ -d "$DOTFILES_STATE" ]
}

@test "is_managed is true on a managed machine" {
  facts="$(render_facts true)"
  facts_probe "$facts" 'if is_managed; then echo yes; else echo no; fi'
  [ "$output" = yes ]
}

@test "is_managed is false on an unmanaged machine" {
  facts="$(render_facts false)"
  facts_probe "$facts" 'if is_managed; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "app_present finds an installed app" {
  facts="$(render_facts)"
  mkdir -p "$DOTFILES_APPLICATIONS/Visual Studio Code.app"
  facts_probe "$facts" 'if app_present "Visual Studio Code.app"; then echo yes; else echo no; fi'
  [ "$output" = yes ]
}

@test "app_present does not find a missing app" {
  facts="$(render_facts)"
  facts_probe "$facts" 'if app_present "Visual Studio Code.app"; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "has_command finds a command on PATH" {
  facts="$(render_facts)"
  stub dotfiles-fake
  facts_probe "$facts" 'if has_command dotfiles-fake; then echo yes; else echo no; fi'
  [ "$output" = yes ]
}

@test "has_command does not find a missing command" {
  facts="$(render_facts)"
  facts_probe "$facts" 'if has_command dotfiles-absent; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "default_is is true when the key already has the value" {
  facts="$(render_facts)"
  stub defaults <<'EOF'
[ "$1" = read ] && [ "$2" = com.apple.dock ] && [ "$3" = tilesize ] || exit 1
echo 16
EOF
  facts_probe "$facts" 'if default_is com.apple.dock tilesize 16; then echo yes; else echo no; fi'
  [ "$output" = yes ]
}

@test "default_is is false when the key has another value" {
  facts="$(render_facts)"
  stub defaults <<'EOF'
echo 48
EOF
  facts_probe "$facts" 'if default_is com.apple.dock tilesize 16; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "default_is is false when the key is unset" {
  facts="$(render_facts)"
  stub defaults <<'EOF'
echo "does not exist" >&2
exit 1
EOF
  facts_probe "$facts" 'if default_is com.apple.dock tilesize 16; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "marked is true after mark" {
  facts="$(render_facts)"
  facts_probe "$facts" 'mark ssh-key-generated; if marked ssh-key-generated; then echo yes; else echo no; fi'
  [ "$output" = yes ]
  [ -f "$DOTFILES_STATE/ssh-key-generated" ]
}

@test "marked is false without mark" {
  facts="$(render_facts)"
  facts_probe "$facts" 'if marked ssh-key-generated; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "mark stores a value that marker_value reads back" {
  facts="$(render_facts)"
  facts_probe "$facts" 'mark packages-status 1; marker_value packages-status'
  [ "$output" = 1 ]
}

@test "marker_value is empty for a marker that does not exist" {
  facts="$(render_facts)"
  facts_probe "$facts" 'printf "[%s]" "$(marker_value packages-status)"'
  [ "$output" = "[]" ]
}

@test "hash_unchanged is true for the stored hash" {
  facts="$(render_facts)"
  facts_probe "$facts" 'store_hash packages abc123; if hash_unchanged packages abc123; then echo yes; else echo no; fi'
  [ "$output" = yes ]
}

@test "hash_unchanged is false for a different hash" {
  facts="$(render_facts)"
  facts_probe "$facts" 'store_hash packages abc123; if hash_unchanged packages def456; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "hash_unchanged is false when no hash was ever stored" {
  facts="$(render_facts)"
  facts_probe "$facts" 'if hash_unchanged packages abc123; then echo yes; else echo no; fi'
  [ "$output" = no ]
}

@test "file_hash is the sha256 of the files' contents, concatenated" {
  facts="$(render_facts)"
  printf 'a' >"$BATS_TEST_TMPDIR/a"
  printf 'b' >"$BATS_TEST_TMPDIR/b"
  facts_probe "$facts" "file_hash '$BATS_TEST_TMPDIR/a' '$BATS_TEST_TMPDIR/b'"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'ab' | shasum -a 256 | cut -d ' ' -f 1)" ]
}

@test "file_hash fails when a file is missing instead of hashing the rest" {
  facts="$(render_facts)"
  printf 'a' >"$BATS_TEST_TMPDIR/a"
  facts_probe "$facts" "file_hash '$BATS_TEST_TMPDIR/a' '$BATS_TEST_TMPDIR/missing'"
  [ "$status" -ne 0 ]
  [[ "$output" == *'missing does not exist'* ]]
}

@test "the preamble puts the asdf shims on PATH when they exist" {
  facts="$(render_facts)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.asdf/shims"
  facts_probe "$facts" 'case ":$PATH:" in *":$HOME/.asdf/shims:"*) echo yes ;; *) echo no ;; esac'
  [ "$output" = yes ]
}

@test "the preamble leaves PATH alone when the asdf shims are absent" {
  facts="$(render_facts)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  facts_probe "$facts" 'case ":$PATH:" in *":$HOME/.asdf/shims:"*) echo yes ;; *) echo no ;; esac'
  [ "$output" = no ]
}
