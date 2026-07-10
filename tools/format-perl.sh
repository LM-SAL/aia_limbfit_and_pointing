#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

declare -a files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  while IFS= read -r file; do
    [[ -f "$file" ]] && files+=("$file")
  done < <(git ls-files -- '*.pl' '*.pdl')
fi

for file in "${files[@]}"; do
  tmpfile="$(mktemp)"
  perltidy -pro=.perltidyrc -st "$file" >"$tmpfile"
  if ! cmp -s "$file" "$tmpfile"; then
    if mode="$(stat -f '%Lp' "$file" 2>/dev/null)"; then
      chmod "$mode" "$tmpfile"
    else
      chmod "$(stat -c '%a' "$file")" "$tmpfile"
    fi
    mv "$tmpfile" "$file"
  fi
  rm -f "$tmpfile"
done
