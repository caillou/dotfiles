#!/usr/bin/env bats
#
# The fixed script list. Later issues fill these files in; the names, the
# chezmoi attributes and the order they imply are settled here, because every
# other issue plugs into them.

setup() {
  load helpers
  SCRIPTS="$REPO_ROOT/.chezmoiscripts"
}

expected_scripts() {
  cat <<'EOF'
run_after_10-packages.sh.tmpl
run_after_20-fish-plugins.sh.tmpl
run_after_21-login-shell.sh.tmpl
run_after_30-github-and-ssh.sh.tmpl
run_after_40-asdf.sh.tmpl
run_after_45-claude-code.sh.tmpl
run_after_50-karabiner.sh.tmpl
run_after_63-iterm2.sh.tmpl
run_after_64-display.sh.tmpl
run_after_90-report.sh.tmpl
run_once_before_00-homebrew.sh.tmpl
run_onchange_after_60-defaults.sh.tmpl
run_onchange_after_61-dock.sh.tmpl
run_onchange_after_62-downloads-view.sh.tmpl
EOF
}

@test "the script directory holds exactly the fixed file list" {
  run ls -1 "$SCRIPTS"
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_scripts)" ]
}

@test "every script is a template with a POSIX sh shebang" {
  while read -r script; do
    [ "${script%.sh.tmpl}" != "$script" ]
    [ "$(head -n 1 "$SCRIPTS/$script")" = '#!/bin/sh' ]
  done <<<"$(expected_scripts)"
}

@test "Homebrew is the only before script, runs once and skips the preamble" {
  run bash -c "ls -1 '$SCRIPTS' | grep before_"
  [ "$output" = 'run_once_before_00-homebrew.sh.tmpl' ]
  run grep -c 'template "facts.sh"' "$SCRIPTS/run_once_before_00-homebrew.sh.tmpl"
  [ "$output" = 0 ]
}

@test "every after script inlines the shared preamble" {
  while read -r script; do
    case "$script" in
    *before_*) continue ;;
    esac
    run grep -c '{{ template "facts.sh" . }}' "$SCRIPTS/$script"
    [ "$output" = 1 ]
  done <<<"$(expected_scripts)"
}

@test "only the pure writers are change-triggered" {
  run bash -c "ls -1 '$SCRIPTS' | grep onchange_"
  [ "$output" = 'run_onchange_after_60-defaults.sh.tmpl
run_onchange_after_61-dock.sh.tmpl
run_onchange_after_62-downloads-view.sh.tmpl' ]
}

@test "every state-dependent script runs on every apply" {
  while read -r script; do
    case "$script" in
    run_once_before_00-homebrew.sh.tmpl | run_onchange_after_6[012]-*) continue ;;
    esac
    [ "${script#run_after_}" != "$script" ]
  done <<<"$(expected_scripts)"
}

@test "the numbering fixes the order chezmoi runs the scripts in" {
  # chezmoi orders scripts by target name, which is the source name without
  # its attributes, so the two-digit prefixes decide the run order.
  run bash -c "ls -1 '$SCRIPTS' | sed -E 's/^run_(once|onchange)?_?(before|after)_//' | sort"
  [ "$output" = '00-homebrew.sh.tmpl
10-packages.sh.tmpl
20-fish-plugins.sh.tmpl
21-login-shell.sh.tmpl
30-github-and-ssh.sh.tmpl
40-asdf.sh.tmpl
45-claude-code.sh.tmpl
50-karabiner.sh.tmpl
60-defaults.sh.tmpl
61-dock.sh.tmpl
62-downloads-view.sh.tmpl
63-iterm2.sh.tmpl
64-display.sh.tmpl
90-report.sh.tmpl' ]
}

@test "every script renders for a managed and for an unmanaged machine" {
  for managed in true false; do
    chezmoi_config "$managed" true true
    while read -r script; do
      run render --file "$SCRIPTS/$script"
      [ "$status" -eq 0 ]
      [ -n "$output" ]
    done <<<"$(expected_scripts)"
  done
}
