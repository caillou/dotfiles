# Shared bats helpers.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Git's own environment, dropped.
#
# A commit exports GIT_DIR, GIT_INDEX_FILE and friends into every hook, and
# they outrank any path an argument names: under `lefthook run pre-commit`,
# `git init "$BATS_TEST_TMPDIR/repo"` re-initialises the *real* repository
# instead, and with no work tree in sight it marks that repository bare. Every
# later `git -C "$fixture" ...` then reads the real checkout too, which is why
# `remote add origin` answered "remote origin already exists".
#
# Sourced from each file's setup(), so this runs before every test: a test
# talks to the repository it just created, never to the one it runs inside.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX \
  GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

# chezmoi_config <managed> <personal> <embedded> [source directory]
#
# Writes a throwaway chezmoi config carrying the machine facts, so templates
# can be rendered for any machine without touching the real config. The
# source directory defaults to the repo; a test that copies part of the repo
# somewhere it can modify names that copy, and `render` follows it.
chezmoi_config() {
  CHEZMOI_CONFIG="${BATS_TEST_TMPDIR:-$BATS_FILE_TMPDIR}/chezmoi.toml"
  CHEZMOI_SOURCE="${4:-$REPO_ROOT}"
  cat >"$CHEZMOI_CONFIG" <<EOF
sourceDir = "$CHEZMOI_SOURCE"

[data]
managed = ${1:-false}
personal = ${2:-false}
embedded = ${3:-false}
EOF
  export CHEZMOI_CONFIG CHEZMOI_SOURCE
}

# render <template>...  -> the rendered text on stdout
render() {
  [ -n "${CHEZMOI_CONFIG:-}" ] || chezmoi_config false false false
  chezmoi --config "$CHEZMOI_CONFIG" --source "$CHEZMOI_SOURCE" execute-template "$@"
}

# render_facts [managed] -> path of the rendered facts preamble
render_facts() {
  chezmoi_config "${1:-false}"
  local facts="${BATS_TEST_TMPDIR:-$BATS_FILE_TMPDIR}/facts.sh"
  render '{{ template "facts.sh" . }}' >"$facts"
  printf '%s' "$facts"
}

# facts_probe <facts-file> <shell code> -> runs the code with the preamble loaded
facts_probe() {
  local facts="$1" code="$2" probe="${BATS_TEST_TMPDIR:-$BATS_FILE_TMPDIR}/probe.sh"
  {
    printf '#!/bin/sh\n'
    printf '. "%s"\n' "$facts"
    printf '%s\n' "$code"
  } >"$probe"
  run sh "$probe"
}

# Every helper works from the test's temporary directory, or from the file's
# when called from setup_file, where bats leaves BATS_TEST_TMPDIR unset.

# isolate_home
#
# HOME and every XDG variable into the test's temporary directory, so nothing
# a test runs can read or write the real home directory. XDG_CONFIG_HOME is
# set on this Mac and wins over HOME, which is why HOME alone is not enough.
# The physical path, because git resolves a repository's path before it
# matches an includeIf and /var is a symlink to /private/var on macOS.
isolate_home() {
  TMP="$(cd "${BATS_TEST_TMPDIR:-$BATS_FILE_TMPDIR}" && pwd -P)"
  export HOME="$TMP/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$HOME"
}

# stub <name> [log] [exit] [<<'EOF' body EOF]
#
# A fake command in $BATS_TEST_TMPDIR/bin, which goes to the front of PATH the
# first time. The stub appends "<name> <arguments>" to <log> when a log is
# given, runs the body when one is given as a heredoc (a pipe would run the
# function in a subshell and lose the PATH change), and exits <exit>, 0 by
# default. A body that exits itself wins over <exit>. STUB_BIN names the
# directory for the seams (DOTFILES_<TOOL>) that need a path rather than a
# name on PATH. The helper cannot tell a heredoc from a pipe bats itself was
# started with, so a stub without a body passes </dev/null when the suite may
# run under `something | bats`.
stub() {
  local name="$1" log="${2:-}" code="${3:-0}"
  STUB_BIN="${BATS_TEST_TMPDIR:-$BATS_FILE_TMPDIR}/bin"
  mkdir -p "$STUB_BIN"
  {
    printf '#!/bin/sh\n'
    if [ -n "$log" ]; then
      printf 'printf '"'"'%%s\\n'"'"' "%s $*" >>"%s"\n' "$name" "$log"
    fi
    if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then
      cat
    fi
    printf 'exit %s\n' "$code"
  } >"$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
  case ":$PATH:" in
  *":$STUB_BIN:"*) ;;
  *) export PATH="$STUB_BIN:$PATH" ;;
  esac
}
