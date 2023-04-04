#/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "$([[ -v BASH_SOURCE ]] && echo "${BASH_SOURCE[0]}" || echo "$0")")"
cd ..

out=$(nix eval .#tests)
if [[ $out == null ]]; then
    echo "all tests passed"
else
    echo "some tests failed:"
    nix run github:msteen/alejandra/f65d485359c3972afe79caae5f9748ffac6b7a4a -- -q <<< "$out"
    exit 1
fi
