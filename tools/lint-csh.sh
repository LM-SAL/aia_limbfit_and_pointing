#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
Usage:
  ./tools/lint-csh.sh
  ./tools/lint-csh.sh path/to/script.csh [more files...]
EOF
}

require_cmd() {
  local cmd="$1"
  local install_hint="${2:-}"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    if [[ -n "$install_hint" ]]; then
      echo "$install_hint" >&2
    fi
    exit 1
  fi
}

collect_all_files() {
  git ls-files -- '*.csh'
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
  echo "No C shell files to lint."
  exit 0
fi

require_cmd csh

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

  csh -n "$file"
done
