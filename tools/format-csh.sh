#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
Usage:
  ./tools/format-csh.sh
  ./tools/format-csh.sh path/to/script.csh [more files...]
EOF
}

collect_all_files() {
  git ls-files -- '*.csh'
}

format_file() {
  local file="$1"
  local tmpfile

  tmpfile="$(mktemp)"
  awk '
    function clamp_indent() {
      if (indent < 0) {
        indent = 0
      }
    }

    function print_line(text) {
      printf("%*s%s\n", indent * 2, "", text)
    }

    {
      line = $0
      sub(/[ \t]+$/, "", line)

      if (NR == 1 && line ~ /^#!/) {
        print line
        next
      }

      stripped = line
      sub(/^[ \t]*/, "", stripped)

      if (stripped == "") {
        print ""
        next
      }

      if (stripped ~ /^(endif|endsw|end)([ \t]|$)/) {
        indent--
        clamp_indent()
      } else if (stripped ~ /^else([ \t]|$)/) {
        indent--
        clamp_indent()
      }

      print_line(stripped)

      if (stripped ~ /^if([ \t]|$).*[ \t]then([ \t]*(#.*)?)$/) {
        indent++
      } else if (stripped ~ /^else[ \t]+if([ \t]|$).*[ \t]then([ \t]*(#.*)?)$/) {
        indent++
      } else if (stripped ~ /^else([ \t]|$)/) {
        indent++
      } else if (stripped ~ /^(foreach|while|switch)([ \t]|$)/) {
        indent++
      } else if (stripped ~ /^(case|default):/) {
        indent++
      } else if (stripped ~ /^breaksw([ \t]|$)/) {
        indent--
        clamp_indent()
      }
    }
  ' "$file" >"$tmpfile"

  if ! cmp -s "$file" "$tmpfile"; then
    chmod --reference="$file" "$tmpfile"
    mv "$tmpfile" "$file"
  else
    rm -f "$tmpfile"
  fi
}

declare -a files=()

case "${1:-}" in
  ""|--all)
    while IFS= read -r file; do
      [[ -n "$file" ]] && files+=("$file")
    done < <(collect_all_files)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    files=("$@")
    ;;
esac

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No C shell files to format."
  exit 0
fi

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "File not found: $file" >&2
    exit 1
  fi

  case "$file" in
    *.csh) ;;
    *)
      echo "Unsupported file type: $file" >&2
      exit 1
      ;;
  esac

  format_file "$file"
done
