#/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "$([[ -v BASH_SOURCE ]] && echo "${BASH_SOURCE[0]}" || echo "$0")")"
cd ..

out=$(nix eval .#tests "$@")
if [[ $out == null ]]; then
  echo "all tests passed"
else
  echo "some tests failed:"
  echo "$out"
  exit 1
fi
