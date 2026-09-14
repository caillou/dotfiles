#!/usr/bin/env bats
#
# Hammerspoon: three plain Lua files under ~/.hammerspoon, no script, no
# symlink, and a Spoons folder chezmoi keeps its hands off.
#
# Nothing here launches or reloads Hammerspoon. The files are checked as files:
# what chezmoi manages, what an apply writes, and what an edit re-adds. HOME
# and the whole XDG set are temporary, and the round-trip runs against a copy
# of the source directory, so `chezmoi re-add` can never write into the repo.

setup() {
  load helpers
  isolate_home

  CONFIG_DIR="$REPO_ROOT/dot_hammerspoon"
  INIT="$CONFIG_DIR/init.lua"
  WINDOWS="$CONFIG_DIR/windows.lua"
  STATUS_MESSAGE="$CONFIG_DIR/status-message.lua"
}

# sandbox -> a copy of the Hammerspoon source, so re-add writes to the copy
sandbox() {
  SRC="$BATS_TEST_TMPDIR/source"
  mkdir -p "$SRC"
  cp -R "$CONFIG_DIR" "$SRC/dot_hammerspoon"
  cp "$REPO_ROOT/.chezmoiignore" "$SRC/.chezmoiignore"
  chezmoi_config false false false "$SRC"
}

# sandboxed <chezmoi arguments>...
sandboxed() {
  chezmoi --config "$CHEZMOI_CONFIG" --source "$CHEZMOI_SOURCE" --destination "$HOME" "$@"
}

# managed_targets [managed] [personal] [embedded]
managed_targets() {
  chezmoi_config "${1:-false}" "${2:-false}" "${3:-false}"
  chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$HOME" managed
}

# --- what is managed -------------------------------------------------------

@test "the three Lua files are the whole of the managed Hammerspoon config" {
  run managed_targets
  [ "$status" -eq 0 ]
  run grep '^\.hammerspoon' <<<"$output"
  [ "$output" = '.hammerspoon
.hammerspoon/init.lua
.hammerspoon/status-message.lua
.hammerspoon/windows.lua' ]
}

@test "the files are managed on every machine, Hammerspoon installed or not" {
  # No facts gate and no script: on a Mac without Hammerspoon the files are
  # still written, and they are inert until it is installed.
  run managed_targets true false false
  [[ "$output" == *'.hammerspoon/windows.lua'* ]]
  run managed_targets false true true
  [[ "$output" == *'.hammerspoon/windows.lua'* ]]
}

@test "chezmoi manages nothing under Spoons" {
  run managed_targets
  [ "$status" -eq 0 ]
  refute_line_matching '^\.hammerspoon/Spoons'
}

@test "the folder is not exact_, so Spoons and friends are left alone" {
  # `exact_hammerspoon` would make chezmoi delete every unmanaged entry in
  # ~/.hammerspoon on apply, Spoons included.
  [ -d "$REPO_ROOT/dot_hammerspoon" ]
  run find "$REPO_ROOT" -mindepth 1 -maxdepth 1 -name '*hammerspoon*'
  [ "$output" = "$REPO_ROOT/dot_hammerspoon" ]
}

@test "the ignore rule keeps a Spoon out of the source directory" {
  sandbox
  mkdir -p "$HOME/.hammerspoon/Spoons/EmmyLua.spoon"
  echo '-- generated at runtime' >"$HOME/.hammerspoon/Spoons/EmmyLua.spoon/init.lua"

  run sandboxed add "$HOME/.hammerspoon/Spoons/EmmyLua.spoon/init.lua"
  [ "$status" -eq 0 ]
  [ ! -e "$SRC/dot_hammerspoon/Spoons" ]
}

@test "an apply leaves a runtime-generated Spoon in place" {
  sandbox
  mkdir -p "$HOME/.hammerspoon/Spoons/EmmyLua.spoon"
  echo '-- generated at runtime' >"$HOME/.hammerspoon/Spoons/EmmyLua.spoon/init.lua"

  run sandboxed apply
  [ "$status" -eq 0 ]
  run cat "$HOME/.hammerspoon/Spoons/EmmyLua.spoon/init.lua"
  [ "$output" = '-- generated at runtime' ]
}

# --- plain, home-relative, re-addable --------------------------------------

@test "no file is a template, so chezmoi re-add works on them" {
  [ ! -e "$INIT.tmpl" ]
  [ ! -e "$WINDOWS.tmpl" ]
  [ ! -e "$STATUS_MESSAGE.tmpl" ]
  run find "$CONFIG_DIR" -name '*.tmpl'
  [ -z "$output" ]
}

@test "an apply writes the three files and settles" {
  sandbox
  run sandboxed apply
  [ "$status" -eq 0 ]
  diff "$INIT" "$HOME/.hammerspoon/init.lua"
  diff "$WINDOWS" "$HOME/.hammerspoon/windows.lua"
  diff "$STATUS_MESSAGE" "$HOME/.hammerspoon/status-message.lua"
  # Real files, not a symlink to the source directory.
  [ ! -L "$HOME/.hammerspoon" ]
  [ ! -L "$HOME/.hammerspoon/windows.lua" ]

  # A second apply has nothing left to do.
  run sandboxed apply --dry-run --verbose
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "editing windows.lua in place and re-adding round-trips" {
  sandbox
  run sandboxed apply
  [ "$status" -eq 0 ]

  printf '\n-- edited in ~/.hammerspoon, not in the repo\n' >>"$HOME/.hammerspoon/windows.lua"
  run sandboxed re-add
  [ "$status" -eq 0 ]
  diff "$SRC/dot_hammerspoon/windows.lua" "$HOME/.hammerspoon/windows.lua"

  # The edit is now the managed content, so the next apply is a no-op.
  run sandboxed apply --dry-run --verbose
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- what the config does --------------------------------------------------

@test "init.lua installs the hs command line, the reload hotkey and the alert" {
  grep -qF 'hs.ipc.cliInstall(os.getenv("HOME") .. "/.local")' "$INIT"
  grep -qF 'hs.hotkey.bind({ "shift", "ctrl" }, "`"' "$INIT"
  grep -qF 'hs.alert.show(' "$INIT"
}

@test "init.lua watches the config folder once and requires the windows module" {
  run grep -c 'hs\.pathwatcher\.new' "$INIT"
  [ "$output" = '1' ]
  grep -qF 'hs.pathwatcher.new(hs.configdir' "$INIT"
  grep -qxF 'require("windows")' "$INIT"
}

@test "the keyboard repo's tooling is gone" {
  # No symlink-following second watcher, no EmmyLua spoon, no space-fn.
  run grep -riE 'emmylua|space-fn|loadSpoon|pathToAbsolute' "$CONFIG_DIR"
  [ "$status" -ne 0 ]
}

@test "every module require resolves to a file in the folder" {
  # The module names lost their `keyboard.` prefix; a stale one would only
  # surface as a runtime error in the Hammerspoon console.
  local found=0
  while read -r module; do
    case "$module" in
    hs | hs.*) continue ;;
    esac
    found=$((found + 1))
    [ -f "$CONFIG_DIR/$module.lua" ]
  done < <(grep -rhoE 'require\("[^"]+"\)' "$CONFIG_DIR" | sed -E 's/require\("(.*)"\)/\1/')
  [ "$found" -gt 0 ]
}

@test "windows.lua keeps the Ctrl+s modal and its status message" {
  grep -qxF 'local trigger = "s"' "$WINDOWS"
  grep -qxF 'local modifiers = { "ctrl" }' "$WINDOWS"
  grep -qxF 'local message = require("status-message")' "$WINDOWS"
  # Every layout the modal binds is still reachable.
  for layout in centerWithFullHeight left40 right60 upLeft downRight nextScreen; do
    grep -qF "local function $layout(" "$WINDOWS"
  done
}

# refute_line_matching <extended regex>
refute_line_matching() {
  while read -r line; do
    if [[ "$line" =~ $1 ]]; then
      echo "unexpected managed target: $line" >&2
      return 1
    fi
  done <<<"$output"
}
