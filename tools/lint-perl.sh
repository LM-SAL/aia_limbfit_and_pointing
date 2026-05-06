#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

declare -a files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(git ls-files -- '*.pl' '*.pdl' | grep -v '^LimbFit_Copy/')
fi

for file in "${files[@]}"; do perl -c "$file"; done
perlcritic --profile .perlcriticrc "${files[@]}"
