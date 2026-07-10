#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

preferred_perl="$HOME/perl5/perlbrew/perls/perl-5.42.0/bin/perl"
perl_bin="${AIA_LIMBFIT_PERL:-$preferred_perl}"
[[ -x "$perl_bin" ]] || { echo "Preferred Perl not found or not executable: $perl_bin" >&2; exit 1; }

perlcritic_bin="${AIA_LIMBFIT_PERLCRITIC:-$(dirname "$perl_bin")/perlcritic}"
[[ -x "$perlcritic_bin" ]] || perlcritic_bin="$(command -v perlcritic)"

declare -a files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(git -c core.fsmonitor=false ls-files -- '*.pl' '*.pdl' | grep -v '^LimbFit_Copy/')
fi

syntax_ok=1
for file in "${files[@]}"; do
  err=$("$perl_bin" -c "$file" 2>&1) && rc=0 || rc=$?
  if [[ $rc -ne 0 ]] && echo "$err" | grep -q "Can't locate"; then
    echo "SKIP $file (missing module)" >&2
  elif [[ $rc -ne 0 ]]; then
    echo "$err" >&2
    syntax_ok=0
  else
    echo "$err"
  fi
done
[[ $syntax_ok -eq 1 ]] || { echo "Syntax errors found above." >&2; exit 1; }
"$perlcritic_bin" --profile .perlcriticrc "${files[@]}"
