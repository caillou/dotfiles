#!/usr/bin/env bats
#
# Git identity, the gh alias, the ssh client config and the script that sets up
# GitHub and ssh on a fresh Mac.
#
# Nothing here talks to GitHub or makes a real key: gh, ssh-keygen and git are
# stubs, HOME and every XDG variable point at a temporary directory, and the
# only checkout the git stub agrees to touch is the throwaway repository each
# test creates.

setup() {
  load helpers
  # isolate_home sets TMP to the physical path of the test directory, which
  # git's includeIf needs; every path below is built on it.
  isolate_home

  export DOTFILES_STATE="$TMP/state"
  SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_30-github-and-ssh.sh.tmpl"

  LOG="$TMP/commands.log"
  CHECKOUT="$TMP/checkout"
  AUTHED="$TMP/gh-authenticated"
  # Resolved before any stub goes on PATH: the test's own git calls, and the
  # git the stub hands the checkout to, are the real one.
  REAL_GIT="$(command -v git)"
}

# --- the managed files -----------------------------------------------------

# apply -> writes every managed file into the isolated home directory
apply() {
  chezmoi_config false false false
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" \
    --destination "$HOME" apply --exclude scripts
  [ "$status" -eq 0 ]
}

# repo <path> -> an empty git repository at that path
repo() {
  "$REAL_GIT" init -q "$1"
  printf '%s' "$1"
}

@test "the identity, the global ignore, the gh alias and the ssh config are written" {
  apply
  [ -f "$HOME/.gitconfig" ]
  [ -f "$HOME/.config/git/icfm.gitconfig" ]
  [ -f "$HOME/.config/git/ignore" ]
  [ -f "$HOME/.config/gh/config.yml" ]
  [ -f "$HOME/.ssh/config" ]
}

@test "chezmoi manages the gh config but never the credentials file" {
  chezmoi_config false false false
  run chezmoi --config "$CHEZMOI_CONFIG" --source "$REPO_ROOT" \
    --destination "$HOME" managed
  [ "$status" -eq 0 ]
  [[ "$output" == *".config/gh/config.yml"* ]]
  [[ "$output" != *"hosts.yml"* ]]
  [[ "$output" != *"id_rsa"* ]]
}

@test "everything outside ~/repos/icfm commits with the personal address" {
  apply
  run git -C "$(repo "$HOME/repos/caillou/dotfiles")" config --get user.email
  [ "$output" = 'pierre.spring@caillou.ch' ]
}

@test "a repo cloned into ~/repos/icfm later commits with the ICFM address" {
  apply
  # The include names a folder that does not exist yet, and git is fine with
  # it: the first ICFM clone on a fresh Mac is already correct.
  [ ! -e "$HOME/repos" ]
  run git -C "$HOME" config --global --list --includes
  [ "$status" -eq 0 ]

  icfm="$(repo "$HOME/repos/icfm/some-project")"
  run git -C "$icfm" config --get user.email
  [ "$output" = 'pierre.spring@icfm.ch' ]
  run git -C "$icfm" config --get user.name
  [ "$output" = 'Pierre Spring' ]
}

@test "the git defaults are set and the dropped includes are gone" {
  apply
  run git -C "$HOME" config --global --get pull.ff
  [ "$output" = 'only' ]
  run git -C "$HOME" config --global --get init.defaultBranch
  [ "$output" = 'main' ]
  run git -C "$HOME" config --global --get core.commentChar
  [ "$output" = '|' ]

  run grep -c 'bkw\|apprentice' "$HOME/.gitconfig"
  [ "$output" = 0 ]
}

@test "the global ignore covers the local Claude settings" {
  apply
  checkout="$(repo "$HOME/repos/caillou/something")"
  mkdir -p "$checkout/.claude"
  : >"$checkout/.claude/settings.local.json"
  run git -C "$checkout" check-ignore .claude/settings.local.json
  [ "$status" -eq 0 ]
}

@test "gh reads the co alias out of the managed config and leaves it untouched" {
  apply
  run grep -q 'co: pr checkout' "$HOME/.config/gh/config.yml"
  [ "$status" -eq 0 ]

  command -v gh >/dev/null 2>&1 || skip 'gh is not installed'
  # No token anywhere near this: GH_CONFIG_DIR is the isolated home and
  # `gh alias list` is a local read.
  export GH_CONFIG_DIR="$HOME/.config/gh"
  cp "$HOME/.config/gh/config.yml" "$TMP/gh-config-as-applied.yml"

  run gh alias list
  [ "$status" -eq 0 ]
  [[ "$output" == *'pr checkout'* ]]

  # gh appends its `version: "1"` schema marker to any config it reads without
  # one, and that rewrite is what stops every later apply at an overwrite
  # prompt. The managed file already carries it, so gh writes nothing back.
  run cmp "$TMP/gh-config-as-applied.yml" "$HOME/.config/gh/config.yml"
  [ "$status" -eq 0 ]
  # Reading the config is never a reason to invent a credentials file.
  [ ! -e "$HOME/.config/gh/hosts.yml" ]
}

@test "the gh folder and its config keep gh's own private modes" {
  apply
  [ "$(stat -f '%Lp' "$HOME/.config/gh")" = 700 ]
  [ "$(stat -f '%Lp' "$HOME/.config/gh/config.yml")" = 600 ]
}

@test "ssh forwards the agent, keeps the connection alive and finds the key" {
  apply
  run ssh -F "$HOME/.ssh/config" -G github.com
  [ "$status" -eq 0 ]
  [[ "$output" == *'forwardagent yes'* ]]
  [[ "$output" == *'serveraliveinterval 60'* ]]
  # Home-relative, as written: ssh does not expand it either.
  [[ "$output" == *'identityfile ~/.ssh/id_rsa'* ]]
}

@test "the ssh folder and its config are private" {
  apply
  [ "$(stat -f '%Lp' "$HOME/.ssh")" = 700 ]
  [ "$(stat -f '%Lp' "$HOME/.ssh/config")" = 600 ]
}

# --- the GitHub and ssh script ---------------------------------------------

# stubs -> gh, ssh-keygen and git that touch nothing real
#
# `$TMP/offline` fails every gh call that needs the network, the way a settled
# Mac behaves with the wifi off; `auth token` keeps working, because it only
# reads the local gh config.
stubs() {
  stub gh "$LOG" <<EOF
case "\$1 \$2" in
"auth token")
  [ -f "$AUTHED" ] || exit 1
  echo "a-stub-token"
  ;;
"auth status")
  [ ! -f "$TMP/offline" ] || exit 1
  [ -f "$AUTHED" ] || exit 1
  ;;
"auth login")
  [ ! -f "$TMP/login-fails" ] || exit 1
  : >"$AUTHED"
  ;;
"api meta")
  # An HTTP error is not the same failure as an unreachable host: the real gh
  # copies the response body to stdout, prints its own message to stderr and
  # exits 1, so the caller sees a non-empty stdout that is not a key.
  if [ -f "$TMP/api-fails" ]; then
    echo '{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}'
    echo "gh: Bad credentials (HTTP 401)" >&2
    exit 1
  fi
  [ ! -f "$TMP/offline" ] || exit 1
  echo "ssh-ed25519 AAAAstubhostkey"
  ;;
"ssh-key add")
  if [ -f "$TMP/offline" ]; then
    echo "dial tcp: lookup api.github.com: no such host" >&2
    exit 1
  fi
  if [ -f "$TMP/upload-fails" ]; then
    echo "HTTP 404: missing the admin:public_key scope" >&2
    exit 1
  fi
  ;;
esac
EOF

  # -F <host> -f <file> answers from the known_hosts file, as the real one
  # does; anything else is a key generation and writes a fake pair.
  stub ssh-keygen "$LOG" <<EOF
if [ "\$1" = "-F" ]; then
  grep -q "\$2" "\$4" 2>/dev/null || exit 1
  exit 0
fi
out=""
prev=""
for arg in "\$@"; do
  [ "\$prev" != "-f" ] || out="\$arg"
  prev="\$arg"
done
[ -n "\$out" ] || exit 1
echo "not a key" >"\$out"
chmod 600 "\$out"
echo "ssh-rsa AAAAstub" >"\$out.pub"
EOF

  # Runs the real git, but only against the throwaway checkout: a bug in the
  # script or in this file can never reach a repository that matters.
  stub git "$LOG" <<EOF
for arg in "\$@"; do
  [ "\$arg" != "$CHECKOUT" ] || exec "$REAL_GIT" "\$@"
done
echo "the git stub refuses to run outside $CHECKOUT: \$*" >&2
exit 1
EOF

  export DOTFILES_GH="$STUB_BIN/gh"
  export DOTFILES_GIT="$STUB_BIN/git"
  export DOTFILES_SSH_KEYGEN="$STUB_BIN/ssh-keygen"
  export DOTFILES_SOURCE="$CHECKOUT"
}

# authenticated -> gh is already logged in
authenticated() {
  : >"$AUTHED"
}

# checkout <url> -> the dotfiles checkout the script is pointed at
checkout() {
  "$REAL_GIT" init -q "$CHECKOUT"
  "$REAL_GIT" -C "$CHECKOUT" remote add origin "$1"
}

# github_and_ssh -> runs the rendered script
github_and_ssh() {
  chezmoi_config false false false
  local script="$TMP/github-and-ssh.sh"
  render --file "$SCRIPT" >"$script"
  run sh "$script"
}

origin_url() {
  "$REAL_GIT" -C "$CHECKOUT" remote get-url origin
}

# -e, because half of what is looked for starts with a dash.
logged() {
  grep -qF -e "$1" "$LOG"
}

refute_logged() {
  ! grep -qF -e "$1" "$LOG"
}

@test "a Mac without a key gets one RSA 4096 key and GitHub gets its public half" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]

  logged '-t rsa -b 4096'
  logged "-C $(hostname)"
  logged "-f $HOME/.ssh/id_rsa"
  [ -f "$HOME/.ssh/id_rsa" ]
  [ "$(stat -f '%Lp' "$HOME/.ssh/id_rsa")" = 600 ]
  logged "gh ssh-key add $HOME/.ssh/id_rsa.pub --title $(hostname)"
  # What tells the report to print the key for Azure DevOps.
  [ -f "$DOTFILES_STATE/ssh-key-generated" ]
}

@test "a Mac that already has a key keeps it" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  mkdir -p "$HOME/.ssh"
  echo mine >"$HOME/.ssh/id_ed25519"
  github_and_ssh
  [ "$status" -eq 0 ]

  refute_logged '-t rsa'
  [ "$(cat "$HOME/.ssh/id_ed25519")" = mine ]
  [ ! -f "$DOTFILES_STATE/ssh-key-generated" ]
}

@test "the known hosts are seeded from the GitHub API once, never from a scan" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  # Over TLS with a token, not trust-on-first-use from whatever answers a scan.
  logged 'gh api meta --jq .ssh_keys[]'
  [ "$(cat "$HOME/.ssh/known_hosts")" = 'github.com ssh-ed25519 AAAAstubhostkey' ]

  : >"$LOG"
  github_and_ssh
  refute_logged 'api meta'
  [ "$(grep -c '^github.com ' "$HOME/.ssh/known_hosts")" -eq 1 ]
}

@test "an unreachable API leaves the known hosts alone and does not fail the apply" {
  stubs
  authenticated
  : >"$TMP/offline"
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  [ ! -s "$HOME/.ssh/known_hosts" ]
}

@test "an API error body is never written to the known hosts" {
  stubs
  authenticated
  # A revoked token, a rate limit or a 5xx: gh answers with JSON on stdout and
  # exits 1. Pinning that as github.com's host key would leave a line ssh never
  # matches, so every later apply would append another copy and say so.
  : >"$TMP/api-fails"
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  [ ! -s "$HOME/.ssh/known_hosts" ]
  [[ "$output" != *'added github.com'* ]]

  github_and_ssh
  [ "$status" -eq 0 ]
  [ ! -s "$HOME/.ssh/known_hosts" ]
  [ "$output" = '' ]
}

@test "gh logs in only when it is not authenticated" {
  stubs
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  logged 'gh auth login --web --hostname github.com --git-protocol ssh --skip-ssh-key --scopes admin:public_key'

  : >"$LOG"
  github_and_ssh
  refute_logged 'auth login'
}

@test "a settled Mac with no network is never sent to the browser" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]

  # The wifi goes off: the API can no longer confirm the token, but the token
  # is still in the local gh config, so this Mac is logged in and stays out of
  # the browser.
  : >"$TMP/offline"
  : >"$LOG"
  github_and_ssh
  [ "$status" -eq 0 ]
  logged 'gh auth token'
  refute_logged 'auth status'
  refute_logged 'auth login'
  [[ "$output" != *'browser'* ]]
  [ "$(origin_url)" = 'git@github.com:caillou/dotfiles.git' ]
}

@test "a second apply on a settled Mac changes nothing and prints nothing" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]

  : >"$LOG"
  github_and_ssh
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  refute_logged 'ssh-key add'
  [ "$(origin_url)" = 'git@github.com:caillou/dotfiles.git' ]
}

@test "the https origin the bootstrap cloned becomes the ssh url" {
  stubs
  authenticated
  # The bootstrap runs before the repository rename, and GitHub redirects.
  checkout https://github.com/caillou/mac-setup.git
  github_and_ssh
  [ "$status" -eq 0 ]
  [ "$(origin_url)" = 'git@github.com:caillou/dotfiles.git' ]
}

@test "an origin that already speaks ssh is left alone" {
  stubs
  authenticated
  checkout git@github.com:caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  refute_logged 'remote set-url'
}

@test "a login that does not finish leaves the checkout on https" {
  stubs
  : >"$TMP/login-fails"
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  [[ "$output" == *'did not finish'* ]]
  refute_logged 'ssh-key add'
  [ "$(origin_url)" = 'https://github.com/caillou/dotfiles.git' ]
}

@test "a failed key upload is reported and leaves the checkout on https" {
  stubs
  authenticated
  : >"$TMP/upload-fails"
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  [[ "$output" == *'admin:public_key'* ]]
  [ "$(origin_url)" = 'https://github.com/caillou/dotfiles.git' ]
}

@test "the key goes to GitHub once and an offline apply afterwards says nothing" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  logged "gh ssh-key add $HOME/.ssh/id_rsa.pub --title $(hostname)"
  [ "$(cat "$DOTFILES_STATE/ssh-key-uploaded")" = "$HOME/.ssh/id_rsa.pub" ]

  # The upload was the last network call on the settled path: with the wifi
  # off it failed, and the script reported that failure on every apply.
  : >"$TMP/offline"
  : >"$LOG"
  github_and_ssh
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  refute_logged 'ssh-key add'
}

@test "a failed upload leaves no marker and the next apply uploads again" {
  stubs
  authenticated
  : >"$TMP/upload-fails"
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  [ ! -f "$DOTFILES_STATE/ssh-key-uploaded" ]

  rm "$TMP/upload-fails"
  : >"$LOG"
  github_and_ssh
  [ "$status" -eq 0 ]
  logged "gh ssh-key add $HOME/.ssh/id_rsa.pub --title $(hostname)"
  [ "$(cat "$DOTFILES_STATE/ssh-key-uploaded")" = "$HOME/.ssh/id_rsa.pub" ]
}

@test "a key deleted and regenerated at the same path is uploaded again" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  logged "gh ssh-key add $HOME/.ssh/id_rsa.pub --title $(hostname)"
  [ "$(cat "$DOTFILES_STATE/ssh-key-uploaded")" = "$HOME/.ssh/id_rsa.pub" ]

  # The key is thrown away and the next apply makes a new one on the same
  # path. The marker is about the key that is gone, and GitHub has never seen
  # this one, so a marker left standing would mean a silent apply and a push
  # that fails on permission denied.
  rm -f "$HOME"/.ssh/id_rsa "$HOME"/.ssh/id_rsa.pub
  : >"$LOG"
  github_and_ssh
  [ "$status" -eq 0 ]
  logged '-t rsa -b 4096'
  [ -f "$HOME/.ssh/id_rsa" ]
  logged "gh ssh-key add $HOME/.ssh/id_rsa.pub --title $(hostname)"
  [ "$(cat "$DOTFILES_STATE/ssh-key-uploaded")" = "$HOME/.ssh/id_rsa.pub" ]
}

@test "a marker left by another key uploads the key this Mac has now" {
  stubs
  authenticated
  checkout https://github.com/caillou/dotfiles.git
  mkdir -p "$DOTFILES_STATE"
  printf '%s\n' "$HOME/.ssh/id_ed25519.pub" >"$DOTFILES_STATE/ssh-key-uploaded"
  github_and_ssh
  [ "$status" -eq 0 ]
  logged "gh ssh-key add $HOME/.ssh/id_rsa.pub --title $(hostname)"
  [ "$(cat "$DOTFILES_STATE/ssh-key-uploaded")" = "$HOME/.ssh/id_rsa.pub" ]
}

@test "without gh the script says so and touches no repository" {
  stubs
  export DOTFILES_GH="$STUB_BIN/absent-gh"
  checkout https://github.com/caillou/dotfiles.git
  github_and_ssh
  [ "$status" -eq 0 ]
  [[ "$output" == *'gh is not installed'* ]]
  [ "$(origin_url)" = 'https://github.com/caillou/dotfiles.git' ]
  # The ssh half of the script still ran.
  [ -f "$HOME/.ssh/id_rsa" ]
}
