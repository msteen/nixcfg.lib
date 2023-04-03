#/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "$([[ -v BASH_SOURCE ]] && echo "${BASH_SOURCE[0]}" || echo "$0")")"
cd ..

out=$(nix eval --raw .#tests)
if (( $(jq 'if . | type == "null" then 1 else 0 end' <<< "$out") )); then
    echo "all tests passed"
else
    echo "some tests failed:"
    jq <<< "$out"
    exit 1
fi
