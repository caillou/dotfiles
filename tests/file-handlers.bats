#!/usr/bin/env bats
#
# File handlers: the script that makes VS Code the app for the code-related
# file types, through duti.
#
# Nothing here touches this Mac's LaunchServices database: `duti` is a stub
# whose handler table is a file in the test's directory, `mdls` is a stub
# that calls an extension dynamic when a second file lists it, Applications
# is a temporary folder, and the handlers data is replaced so the assertions
# run on a short list the test owns. The duti log doubles as the count of
# writes, and of dialogs macOS would have shown: a settled Mac must leave it
# without a single `-s`.

FAKE_HANDLERS='{"handlers":[
  {"bundle":"com.microsoft.VSCode","app":"Visual Studio Code.app","extensions":["md","xml","csv"]}
]}'

setup() {
  load helpers
  isolate_home

  export DOTFILES_STATE="$BATS_TEST_TMPDIR/state"
  export DOTFILES_APPLICATIONS="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$DOTFILES_STATE" "$DOTFILES_APPLICATIONS"

  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_65-file-handlers.sh.tmpl"
  TABLE="$BATS_TEST_TMPDIR/handlers" # one "extension bundle-id" per line
  DYNAMIC="$BATS_TEST_TMPDIR/dynamic" # extensions no app declares, one per line
  LOG="$BATS_TEST_TMPDIR/duti.log"
  HASH="$DOTFILES_STATE/handlers.hash"
  : >"$TABLE" "$DYNAMIC"
  stub_duti
  stub_mdls
}

# mdls -name kMDItemContentType -raw <probe> answers a made-up dyn. type for
# an extension in the dynamic list, a declared one for the rest.
stub_mdls() {
  stub mdls <<EOF
ext="\${4##*.}"
if grep -qxF "\$ext" "$DYNAMIC"; then
  printf 'dyn.ah62d4rv4ge80q4pxra'
else
  printf 'public.plain-text'
fi
EOF
  export DOTFILES_MDLS="$STUB_BIN/mdls"
}

# stub_duti [exit code of -s]
#
# -x <ext> answers from the table the way duti does, three lines, or fails
# like duti on an extension without a handler; -s <bundle> <ext> <role>
# rewrites the table.
stub_duti() {
  stub duti "$LOG" <<EOF
case "\$1" in
-x)
  bundle="\$(awk -v ext="\$2" '\$1 == ext { print \$2 }' "$TABLE")"
  if [ -z "\$bundle" ]; then
    echo "Failed to get default application for extension '\$2'" >&2
    exit 2
  fi
  printf '%s\n' "Some.app" "/Applications/Some.app" "\$bundle"
  ;;
-s)
  [ "${1:-0}" -eq 0 ] || exit "${1:-0}"
  awk -v ext="\$3" '\$1 != ext' "$TABLE" >"$TABLE.new"
  printf '%s %s\n' "\$3" "\$2" >>"$TABLE.new"
  mv "$TABLE.new" "$TABLE"
  ;;
*) exit 99 ;;
esac
EOF
  export DOTFILES_DUTI="$STUB_BIN/duti"
}

# handlers [data] -> runs the rendered script, on the fake table by default
handlers() {
  chezmoi_config false false false
  local script="$BATS_TEST_TMPDIR/handlers.sh"
  render --file "$SCRIPT" --override-data "${1:-$FAKE_HANDLERS}" >"$script"
  run sh "$script"
}

# settled -> the table with every fake extension already on VS Code
settled() {
  printf 'md com.microsoft.VSCode\nxml com.microsoft.VSCode\ncsv com.microsoft.VSCode\n' >"$TABLE"
}

# handler_of md -> the bundle id in the table
handler_of() {
  awk -v ext="$1" '$1 == ext { print $2 }' "$TABLE"
}

# writes -> the -s lines the stub logged, 0 when duti was never called
writes() {
  [ -f "$LOG" ] || { echo 0; return; }
  grep -c '^duti -s ' "$LOG" || true
}

install_vscode() {
  mkdir -p "$DOTFILES_APPLICATIONS/Visual Studio Code.app"
}

@test "without duti the script skips and says the next apply sets the handlers" {
  install_vscode
  export DOTFILES_DUTI="$BATS_TEST_TMPDIR/nowhere/duti"
  handlers
  [ "$status" -eq 0 ]
  [[ "$output" == *"duti is not available yet"* ]]
  [[ "$output" == *"next \`chezmoi apply\`"* ]]
  [ ! -f "$HASH" ]
}

@test "an app that is not installed is skipped, nothing is written, nothing is remembered" {
  handlers
  [ "$status" -eq 0 ]
  [[ "$output" == *"Visual Studio Code.app is not installed"* ]]
  [ "$(writes)" = 0 ]
  [ ! -f "$HASH" ]
}

@test "every extension without a handler, or with another app, goes to the app" {
  install_vscode
  printf 'md com.coteditor.CotEditor\ncsv com.apple.Numbers\n' >"$TABLE"
  handlers
  [ "$status" -eq 0 ]
  [ "$(handler_of md)" = com.microsoft.VSCode ]
  [ "$(handler_of xml)" = com.microsoft.VSCode ]
  [ "$(handler_of csv)" = com.microsoft.VSCode ]
  [ "$(writes)" = 3 ]
  [[ "$output" == *"making Visual Studio Code.app the app for md xml csv"* ]]
}

@test "the role is all, which is what Change All in the Finder sets" {
  install_vscode
  handlers
  run grep -c '^duti -s com.microsoft.VSCode [a-z]* all$' "$LOG"
  [ "$output" = 3 ]
}

@test "a change warns that macOS confirms each type with a dialog" {
  install_vscode
  handlers
  [[ "$output" == *"macOS confirms each file type with a dialog"* ]]
}

@test "a settled Mac is not written to, prints nothing and remembers the table" {
  install_vscode
  settled
  handlers
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  [ "$(writes)" = 0 ]
  [ -f "$HASH" ]
}

@test "a table that was asked once is not asked again, whatever the answers were" {
  install_vscode
  settled
  handlers
  [ -f "$HASH" ]
  # The user answered "Keep" for xml, or changed it by hand: their call.
  printf 'md com.microsoft.VSCode\nxml com.apple.TextEdit\ncsv com.microsoft.VSCode\n' >"$TABLE"
  rm -f "$LOG"
  handlers
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  [ "$(handler_of xml)" = com.apple.TextEdit ]
  # duti was not even asked.
  [ ! -f "$LOG" ]
}

@test "a changed table asks again, for the types that differ only" {
  install_vscode
  settled
  handlers
  handlers '{"handlers":[{"bundle":"com.microsoft.VSCode","app":"Visual Studio Code.app","extensions":["md","xml","csv","diff"]}]}'
  [ "$(handler_of diff)" = com.microsoft.VSCode ]
  [ "$(writes)" = 1 ]
}

@test "removing the hash asks again" {
  install_vscode
  settled
  handlers
  rm "$HASH"
  printf 'md com.microsoft.VSCode\nxml com.apple.TextEdit\ncsv com.microsoft.VSCode\n' >"$TABLE"
  handlers
  [ "$(handler_of xml)" = com.microsoft.VSCode ]
  [ "$(writes)" = 1 ]
}

@test "an extension no app declares is skipped with a note and does not block the rest" {
  install_vscode
  printf 'md com.microsoft.VSCode\ncsv com.microsoft.VSCode\n' >"$TABLE"
  echo xml >"$DYNAMIC"
  handlers
  [ "$status" -eq 0 ]
  [[ "$output" == *"no installed app declares .xml"* ]]
  [ "$(writes)" = 0 ]
  [ -f "$HASH" ]
}

@test "a refused extension is reported, does not fail the apply, and is retried next time" {
  install_vscode
  stub_duti 1
  handlers
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not make Visual Studio Code.app the handler for .md"* ]]
  [[ "$output" == *"could not make Visual Studio Code.app the handler for .csv"* ]]
  [ "$(writes)" = 3 ]
  [ ! -f "$HASH" ]
}

# --- the data ----------------------------------------------------------------

@test "the real table names VS Code by its bundle id and its app bundle" {
  run render '{{ range .handlers }}{{ .bundle }} {{ .app }}{{ end }}'
  [ "$output" = 'com.microsoft.VSCode Visual Studio Code.app' ]
}

@test "every extension is lowercase, without a dot, and listed once" {
  run render '{{ range .handlers }}{{ range .extensions }}{{ . }}{{ "\n" }}{{ end }}{{ end }}'
  while read -r ext; do
    [[ "$ext" =~ ^[a-z0-9]+$ ]]
  done <<<"$output"
  run bash -c "printf '%s\n' '$output' | sort | uniq -d"
  [ -z "$output" ]
}

@test "the types the request named are in the list" {
  run render '{{ range .handlers }}{{ .extensions | join " " }}{{ end }}'
  for ext in xml md csv js ts jsx diff; do
    [[ " $output " == *" $ext "* ]]
  done
}

@test "duti is a core formula, so a managed Mac gets it too" {
  run grep -Fx 'brew "duti"' "$REPO_ROOT/.chezmoitemplates/Brewfile"
  [ "$status" -eq 0 ]
}
