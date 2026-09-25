# Shared script preamble: environment plus pure predicates and marker helpers.
#
# Every `after` script inlines this file with a chezmoi template include right
# after its shebang. Scripts are separate `sh` processes, so nothing set here
# survives into the next script; inlining is the only mechanism.
#
# The Homebrew installer script does NOT include this file: chezmoi keys
# run-once scripts by rendered content, so editing this file would re-run it.
#
# Every external tool a script runs goes through a variable named after it:
# TOOL="${DOTFILES_TOOL:-<real path or name>}". The `brew shellenv` below puts
# /opt/homebrew/bin ahead of anything a test prepends to PATH, so a stub there
# would never win; the variable is the seam a test points at its stub. The
# tools more than one script runs are defined here, the rest in the script
# that runs them.

# Every script inlines the whole preamble and uses the part it needs, so the
# unused helpers are not a smell.
# shellcheck disable=SC2329
set -eu

# Scripts run in a plain `sh` without any of the user's shell config.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
if [ -d "$HOME/.asdf/shims" ]; then
  PATH="$HOME/.asdf/shims:$PATH"
  export PATH
fi

# Where markers and hashes live. Overridable so tests can point it at a
# temporary directory.
STATE="${DOTFILES_STATE:-$HOME/.local/state/dotfiles}"
mkdir -p "$STATE"

# Where app bundles live. Overridable for the same reason.
APPLICATIONS="${DOTFILES_APPLICATIONS:-/Applications}"

# The generated Brewfile stays at a stable path: it is exactly what `brew
# bundle` ran with, so `brew bundle cleanup --file "$BREWFILE"` is a meaningful
# drift check afterwards. Edit .chezmoitemplates/Brewfile, never this copy.
# shellcheck disable=SC2034
BREWFILE="$STATE/Brewfile"

# The shared tool seams, see the header. Not every script uses every one.
# shellcheck disable=SC2034
BREW="${DOTFILES_BREW:-brew}"
# shellcheck disable=SC2034
FISH="${DOTFILES_FISH:-${HOMEBREW_PREFIX:-/opt/homebrew}/bin/fish}"

# Is this machine managed by an employer? Answered once at `chezmoi init`
# (detected from `profiles status -type enrollment`) and editable in chezmoi's
# config afterwards, so no script ever re-detects it.
MANAGED={{ if .managed }}1{{ else }}0{{ end }}

is_managed() {
  [ "$MANAGED" = 1 ]
}

# app_present "Visual Studio Code.app"
app_present() {
  [ -d "$APPLICATIONS/$1" ]
}

# has_command brew
has_command() {
  command -v "$1" >/dev/null 2>&1
}

# default_is com.apple.dock tilesize 16
default_is() {
  [ "$(defaults read "$1" "$2" 2>/dev/null)" = "$3" ]
}

# mark ssh-key-generated [value]
mark() {
  if [ "$#" -gt 1 ]; then
    printf '%s\n' "$2" >"$STATE/$1"
  else
    : >"$STATE/$1"
  fi
}

# marked ssh-key-generated
marked() {
  [ -f "$STATE/$1" ]
}

# marker_value packages-status  -> the stored value, empty when unmarked
marker_value() {
  if [ -f "$STATE/$1" ]; then
    head -n 1 "$STATE/$1"
  fi
}

# hash_unchanged packages <hash>
hash_unchanged() {
  [ -f "$STATE/$1.hash" ] && [ "$(cat "$STATE/$1.hash")" = "$2" ]
}

# store_hash packages <hash>
store_hash() {
  printf '%s\n' "$2" >"$STATE/$1.hash"
}

# file_hash <path>...  -> the sha256 of the files' contents, concatenated
#
# A missing file is a failure, not a shorter input: `cat` alone would hash the
# files that are there, and the hash would look valid.
file_hash() {
  for file in "$@"; do
    if [ ! -f "$file" ]; then
      echo "file_hash: $file does not exist" >&2
      return 1
    fi
  done
  cat "$@" | shasum -a 256 | cut -d ' ' -f 1
}
