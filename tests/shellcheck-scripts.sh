#!/bin/sh
# Renders every chezmoi script, for a managed and for an unmanaged machine,
# and runs shellcheck over the result. chezmoi's dry-run never executes
# scripts, so this is what checks their content.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

config="$tmp/chezmoi.toml"

# check_profile <label> <managed> <personal> <embedded>
check_profile() {
  # The same config tests/helpers.bash writes; POSIX sh cannot source that file.
  cat >"$config" <<EOF
sourceDir = "$root"

[data]
managed = $2
personal = $3
embedded = $4
EOF
  out="$tmp/$1"
  mkdir -p "$out"
  for template in "$root"/.chezmoiscripts/*.tmpl; do
    name="${template##*/}"
    chezmoi --config "$config" --source "$root" \
      execute-template --file "$template" >"$out/${name%.tmpl}"
  done
  echo "shellcheck: $1"
  shellcheck --shell=sh "$out"/*
}

check_profile managed true false false
check_profile personal false true true

echo "shellcheck: tests"
shellcheck --shell=sh "$root"/tests/*.sh
