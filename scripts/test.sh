#/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "$([[ -v BASH_SOURCE ]] && echo "${BASH_SOURCE[0]}" || echo "$0")")"
cd ..

out=$(nix eval .#tests "$@")
if [[ $out == '[ ]' ]]; then
  echo "all tests passed"
else
  echo "some tests failed:"
  alejandra <<< "$out"
  exit 1
fi
