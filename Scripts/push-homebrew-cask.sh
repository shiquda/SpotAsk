#!/bin/sh
set -eu

# Push HEAD to origin main. Requires CASK_GITHUB_TOKEN (repo admin PAT).
# Never force-push. github-actions cannot bypass required status checks
# on this personal repository.
#
# actions/checkout writes a URL-scoped
# http.https://github.com/.extraheader that wins over a generic
# http.extraheader. Strip it, then pass a same-specificity PAT header
# via -c so the push is not still authenticated as GITHUB_TOKEN.

if [ -z "${CASK_GITHUB_TOKEN:-}" ]; then
    echo "CASK_GITHUB_TOKEN is required to push Casks/spotask.rb to main." >&2
    echo "Use a repository admin PAT so the push can bypass required status checks." >&2
    echo "The default GITHUB_TOKEN cannot: GitHub Actions is not a ruleset bypass actor here." >&2
    exit 1
fi

remote=${CASK_PUSH_REMOTE:-origin}
refspec=${CASK_PUSH_REFSPEC:-HEAD:refs/heads/main}
pat_header="AUTHORIZATION: bearer ${CASK_GITHUB_TOKEN}"

git config --unset-all http.https://github.com/.extraheader 2>/dev/null || true

git -c "http.https://github.com/.extraheader=${pat_header}" \
    push "$remote" "$refspec"
