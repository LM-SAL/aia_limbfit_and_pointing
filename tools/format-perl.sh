#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(git ls-files -- '*.pl' '*.pdl')
fi

for file in "${files[@]}"; do
  tmpfile="$(mktemp)"
  perltidy -pro=.perltidyrc -st "$file" >"$tmpfile"
  if ! cmp -s "$file" "$tmpfile"; then
    chmod --reference="$file" "$tmpfile"
    mv "$tmpfile" "$file"
  fi
  rm -f "$tmpfile"
done
