#!/usr/bin/env bats
#
# The rules every script in .chezmoiscripts follows: the file name shape, the
# shebang, the shared preamble, which scripts may be change-triggered, and the
# numbering that fixes the run order. The list itself is whatever is in the
# directory: adding a script means adding the file, nothing else.

setup() {
  load helpers
  SCRIPTS="$REPO_ROOT/.chezmoiscripts"
}

scripts() {
  ls -1 "$SCRIPTS"
}

@test "every script is a template with a POSIX sh shebang" {
  while read -r script; do
    [ "${script%.sh.tmpl}" != "$script" ]
    [ "$(head -n 1 "$SCRIPTS/$script")" = '#!/bin/sh' ]
  done <<<"$(scripts)"
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
  done <<<"$(scripts)"
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
  done <<<"$(scripts)"
}

@test "every script carries a two-digit prefix and no two share one" {
  # chezmoi orders scripts by target name, which is the source name without
  # its attributes, so the two-digit prefixes decide the run order.
  run bash -c "ls -1 '$SCRIPTS' | sed -E 's/^run_(once|onchange)?_?(before|after)_//'"
  while read -r target; do
    [[ "$target" =~ ^[0-9][0-9]-[a-z-]+\.sh\.tmpl$ ]]
  done <<<"$output"
  run bash -c "ls -1 '$SCRIPTS' | sed -E 's/^run_(once|onchange)?_?(before|after)_([0-9]{2}).*/\3/' | sort | uniq -d"
  [ -z "$output" ]
}

@test "Homebrew runs first and the report last" {
  run bash -c "ls -1 '$SCRIPTS' | sed -E 's/^run_(once|onchange)?_?(before|after)_//' | sort"
  [ "${lines[0]}" = '00-homebrew.sh.tmpl' ]
  [ "${lines[${#lines[@]} - 1]}" = '90-report.sh.tmpl' ]
}

@test "every script renders for a managed and for an unmanaged machine" {
  for managed in true false; do
    chezmoi_config "$managed" true true
    while read -r script; do
      run render --file "$SCRIPTS/$script"
      [ "$status" -eq 0 ]
      [ -n "$output" ]
    done <<<"$(scripts)"
  done
}
