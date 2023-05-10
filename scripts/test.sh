#/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "$([[ -v BASH_SOURCE ]] && echo "${BASH_SOURCE[0]}" || echo "$0")")"
cd ..

if [[ -v CI && $CI == true ]]; then
  NIXCFG_ROOT=$PWD
  sed "s|@NIXCFG_ROOT@|$NIXCFG_ROOT|g" test/lib/flake.tpl.nix > test/lib/flake.nix
fi

out=$(nix eval ./test/lib#tests "$@")
if [[ $out == null ]]; then
  echo "all tests passed"
else
  echo "some tests failed:"
  echo "$out"
  exit 1
fi