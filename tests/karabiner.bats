#!/usr/bin/env bats
#
# Karabiner: the karabiner.ts project kept in the repo, and the script that
# builds it into Karabiner's config file.
#
# Nothing here runs node: `npm` is a stub whose whole world is a temporary
# directory, HOME is a temporary directory, and the source directory the script
# builds from is a copy of the repo's project, so a test can change the rules
# file without touching the repo. The real build is exercised by hand on a Mac
# that has Karabiner; the acceptance criterion for that is in the issue.

setup() {
  load helpers
  # Least of all may a test write into the real ~/.config/karabiner.
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$DOTFILES_APPLICATIONS"

  export DOTFILES_NPM="$BATS_TEST_TMPDIR/bin/npm"
  # The stub reads this itself, so the heredoc below needs no escaping.
  export NPM_STUB_LOG="$BATS_TEST_TMPDIR/npm.log"

  PROJECT="$REPO_ROOT/.karabiner"
  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_50-karabiner.sh.tmpl"
  CONFIG="$HOME/.config/karabiner/karabiner.json"
}

# --- the project in the repo -----------------------------------------------

# project_files -> everything in the project except the installed dependencies
project_files() {
  ls -1A "$PROJECT" | grep -v '^node_modules$'
}

# dev_deps <file> -> "name@range" for the first devDependencies block, which in
# the lockfile is the root package's
dev_deps() {
  awk '/"devDependencies"/ { f = 1; next }
       f && /^[[:space:]]*\}/ { exit }
       f { gsub(/[",]/, ""); sub(/:$/, "", $1); print $1 "@" $2 }' "$1"
}

@test "the project holds the rules file, the package files and nothing else" {
  run project_files
  [ "$output" = '.gitignore
package-lock.json
package.json
src
tsconfig.json' ]
  run ls -1A "$PROJECT/src"
  [ "$output" = 'index.ts' ]
}

@test "the starter README did not come along" {
  [ ! -e "$PROJECT/README.md" ]
}

@test "karabiner.ts is pinned and nothing tracks a moving version" {
  run grep -F '"karabiner.ts": "^1.38.0"' "$PROJECT/package.json"
  [ "$status" -eq 0 ]
  # "latest" and "*" would make npm ci reproducible only by accident.
  run grep -E '"(latest|\*)"' "$PROJECT/package.json"
  [ "$status" -ne 0 ]
}

@test "every dependency is a pinned range" {
  while read -r dep; do
    [[ "${dep#*@}" =~ ^\^?[0-9]+\.[0-9]+\.[0-9]+$ ]]
  done <<<"$(dev_deps "$PROJECT/package.json")"
}

@test "the lockfile is committed and resolves karabiner.ts to the pinned major" {
  [ -f "$PROJECT/package-lock.json" ]
  run grep -A1 -F '"node_modules/karabiner.ts"' "$PROJECT/package-lock.json"
  [[ "$output" =~ \"version\":\ \"1\.38\.[0-9]+\" ]]
  # Lockfile v3 is what `npm ci` needs to install without touching the network
  # for metadata.
  run grep -F '"lockfileVersion": 3' "$PROJECT/package-lock.json"
  [ "$status" -eq 0 ]
}

@test "the lockfile agrees with the package file, so npm ci does not refuse" {
  run diff <(dev_deps "$PROJECT/package.json") <(dev_deps "$PROJECT/package-lock.json")
  [ "$status" -eq 0 ]
}

@test "the scripts are build, dev and update" {
  run grep -F '"build": "tsx src/index.ts"' "$PROJECT/package.json"
  [ "$status" -eq 0 ]
  run grep -F '"dev": "tsx watch src/index.ts"' "$PROJECT/package.json"
  [ "$status" -eq 0 ]
  run grep -F '"update": "npm update karabiner.ts"' "$PROJECT/package.json"
  [ "$status" -eq 0 ]
}

@test "the dependencies are kept out of the repo" {
  run grep -Fx 'node_modules/' "$PROJECT/.gitignore"
  [ "$status" -eq 0 ]
}

@test "the rules target the profile Karabiner creates on first launch" {
  run grep -F "writeToProfile('Default profile'" "$PROJECT/src/index.ts"
  [ "$status" -eq 0 ]
}

@test "the generated config is nowhere in the repo" {
  run bash -c "find '$REPO_ROOT' -name .git -prune -o -name node_modules -prune -o \
    -name 'karabiner.json' -print"
  [ "$output" = '' ]
}

@test "chezmoi ignores the project without needing a rule for it" {
  chezmoi_config false false false
  local dest="$BATS_TEST_TMPDIR/dest"
  mkdir -p "$dest"
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" --destination "$dest" managed
  [ "$status" -eq 0 ]
  while read -r line; do
    [ "${line#.karabiner}" = "$line" ]
  done <<<"$output"
  # Dot-prefixed source entries are ignored by chezmoi already, so the ignore
  # file carries no rule for the project (the comment there mentions it).
  run bash -c "grep -v '^#' '$REPO_ROOT/.chezmoiignore' | grep -F '.karabiner'"
  [ "$status" -ne 0 ]
}

# --- the script ------------------------------------------------------------

# stub_npm -> an npm that logs its working directory and arguments (its own
# log line, because the directory is what the tests assert); the build writes
# the config file the way karabiner.ts does, in place.
stub_npm() {
  stub npm <<'EOF'
echo "$PWD $*" >>"$NPM_STUB_LOG"
case "$1" in
ci)
  [ -z "${NPM_STUB_FAIL_CI:-}" ] || { echo "stub: npm ci failed" >&2; exit 1; }
  mkdir -p node_modules
  ;;
run)
  [ -z "${NPM_STUB_FAIL_BUILD:-}" ] || { echo "stub: the build failed" >&2; exit 1; }
  [ -d node_modules ] || { echo "stub: dependencies are not installed" >&2; exit 1; }
  printf 'built from %s\n' "$PWD" >"$HOME/.config/karabiner/karabiner.json"
  ;;
*)
  echo "stub: unexpected subcommand $1" >&2
  exit 2
  ;;
esac
EOF
}

# karabiner_installed -> the app bundle the script gates on
karabiner_installed() {
  mkdir -p "$DOTFILES_APPLICATIONS/Karabiner-Elements.app"
}

# karabiner_launched -> the config file Karabiner writes on first launch
karabiner_launched() {
  mkdir -p "$(dirname "$CONFIG")"
  printf '{ "profiles": [] }\n' >"$CONFIG"
}

# source_copy -> a throwaway chezmoi source directory holding a copy of the
# project, so a test can change the rules file without touching the repo
source_copy() {
  SOURCE_DIR="$BATS_TEST_TMPDIR/source"
  mkdir -p "$SOURCE_DIR/.karabiner/src"
  cp -R "$REPO_ROOT/.chezmoitemplates" "$SOURCE_DIR/"
  cp "$PROJECT/src/index.ts" "$SOURCE_DIR/.karabiner/src/"
  cp "$PROJECT/package.json" "$PROJECT/package-lock.json" \
    "$PROJECT/tsconfig.json" "$SOURCE_DIR/.karabiner/"
}

# karabiner_script -> renders the script against the copied source and runs it
karabiner_script() {
  [ -n "${SOURCE_DIR:-}" ] || source_copy
  chezmoi_config false false false "$SOURCE_DIR"
  local script="$BATS_TEST_TMPDIR/karabiner.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

built_times() {
  grep -c ' run build$' "$NPM_STUB_LOG" 2>/dev/null || true
}

# --- a machine that has Karabiner ------------------------------------------

@test "the first apply installs the dependencies and builds the rules" {
  stub_npm
  karabiner_installed
  karabiner_launched
  karabiner_script
  [ "$status" -eq 0 ]
  # Both commands run in the project directory, not in the home directory.
  [ "$(cat "$NPM_STUB_LOG")" = "$SOURCE_DIR/.karabiner ci
$SOURCE_DIR/.karabiner run build" ]
  [ "$(cat "$CONFIG")" = "built from $SOURCE_DIR/.karabiner" ]
  [ -f "$DOTFILES_STATE/karabiner.hash" ]
}

@test "an unchanged source builds nothing and says nothing" {
  stub_npm
  karabiner_installed
  karabiner_launched
  karabiner_script
  [ "$status" -eq 0 ]

  karabiner_script
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  [ "$(built_times)" -eq 1 ]
}

@test "a changed rules file rebuilds" {
  stub_npm
  karabiner_installed
  karabiner_launched
  karabiner_script
  [ "$status" -eq 0 ]

  echo "// a new rule" >>"$SOURCE_DIR/.karabiner/src/index.ts"
  karabiner_script
  [ "$status" -eq 0 ]
  [ "$(built_times)" -eq 2 ]
}

@test "a changed lockfile rebuilds" {
  stub_npm
  karabiner_installed
  karabiner_launched
  karabiner_script
  [ "$status" -eq 0 ]

  # What `npm run update` leaves behind: a new resolved version.
  sed -i.bak 's/1\.38\.0/1.39.0/' "$SOURCE_DIR/.karabiner/package-lock.json"
  rm -f "$SOURCE_DIR/.karabiner/package-lock.json.bak"
  karabiner_script
  [ "$status" -eq 0 ]
  [ "$(built_times)" -eq 2 ]
}

# --- a machine that does not, or not yet -----------------------------------

@test "without Karabiner the script skips and records nothing" {
  stub_npm
  karabiner_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'not installed'* ]]
  [ ! -f "$NPM_STUB_LOG" ]
  [ ! -f "$DOTFILES_STATE/karabiner.hash" ]
}

@test "with Karabiner never launched the script says how to fix it and waits" {
  stub_npm
  karabiner_installed
  karabiner_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'never been launched'* ]]
  [ ! -f "$NPM_STUB_LOG" ]
  [ ! -f "$DOTFILES_STATE/karabiner.hash" ]
}

@test "a Karabiner installed and launched later gets its rules on the next sync" {
  stub_npm
  karabiner_script
  [ "$status" -eq 0 ]

  karabiner_installed
  karabiner_script
  [ "$status" -eq 0 ]

  karabiner_launched
  karabiner_script
  [ "$status" -eq 0 ]
  [ "$(built_times)" -eq 1 ]
  [ -f "$DOTFILES_STATE/karabiner.hash" ]
}

@test "the script never creates Karabiner's config file itself" {
  stub_npm
  karabiner_installed
  karabiner_script
  [ "$status" -eq 0 ]
  # Karabiner owns that file: writing a stub of it would hide the fact that
  # Karabiner was never launched, and the build would have nothing to merge
  # its rules into.
  [ ! -e "$CONFIG" ]
}

# --- when the build goes wrong ---------------------------------------------

@test "without npm the script waits for the asdf node instead of failing" {
  export DOTFILES_NPM="$BATS_TEST_TMPDIR/bin/absent-npm"
  karabiner_installed
  karabiner_launched
  karabiner_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'npm is not available'* ]]
  [ ! -f "$DOTFILES_STATE/karabiner.hash" ]
}

@test "a failing npm ci does not abort the apply and is retried next time" {
  stub_npm
  karabiner_installed
  karabiner_launched
  export NPM_STUB_FAIL_CI=1
  karabiner_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'npm ci failed. The next `chezmoi apply` builds the rules.'* ]]
  [ ! -f "$DOTFILES_STATE/karabiner.hash" ]

  unset NPM_STUB_FAIL_CI
  karabiner_script
  [ "$status" -eq 0 ]
  [ "$(built_times)" -eq 1 ]
  [ -f "$DOTFILES_STATE/karabiner.hash" ]
}

@test "a failing build does not abort the apply and is retried next time" {
  stub_npm
  karabiner_installed
  karabiner_launched
  export NPM_STUB_FAIL_BUILD=1
  karabiner_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'the build failed. The next `chezmoi apply` builds the rules.'* ]]
  [ ! -f "$DOTFILES_STATE/karabiner.hash" ]

  unset NPM_STUB_FAIL_BUILD
  karabiner_script
  [ "$status" -eq 0 ]
  [ -f "$DOTFILES_STATE/karabiner.hash" ]
}
