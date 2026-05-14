#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

preferred_perl="/homef/nabil/perl5/perlbrew/perls/perl-5.42.0/bin/perl"
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

for file in "${files[@]}"; do "$perl_bin" -c "$file"; done
"$perlcritic_bin" --profile .perlcriticrc "${files[@]}"
