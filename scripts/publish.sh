#! /usr/bin/env nix-shell
#! nix-shell -p ghp-import -i bash
set -euo pipefail
cd "$(dirname -- "$([[ -v BASH_SOURCE ]] && echo "${BASH_SOURCE[0]}" || echo "$0")")"
cd ..

USER=msteen
REPO=nixcfg.lib
GITHUB_PAGES_BRANCH=gh-pages

if [[ -v DEPLOY_TOKEN ]]; then
    GITHUB=https://$USER:"$DEPLOY_TOKEN"@github.com/$USER/$REPO
else
    GITHUB=git@github.com:$USER/$REPO
fi

nix build .#doc
ghp-import -m "ci: publish doc" -b $GITHUB_PAGES_BRANCH ./result/share/doc/nixcfg/
git push "$GITHUB" $GITHUB_PAGES_BRANCH
