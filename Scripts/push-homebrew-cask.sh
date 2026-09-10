#!/bin/sh
set -eu

# Push HEAD to origin main. Requires CASK_GITHUB_TOKEN (repo admin PAT).
# Never force-push. github-actions cannot bypass required status checks
# on this personal repository.

if [ -z "${CASK_GITHUB_TOKEN:-}" ]; then
    echo "CASK_GITHUB_TOKEN is required to push Casks/spotask.rb to main." >&2
    echo "Use a repository admin PAT so the push can bypass required status checks." >&2
    echo "The default GITHUB_TOKEN cannot: GitHub Actions is not a ruleset bypass actor here." >&2
    exit 1
fi

remote=${CASK_PUSH_REMOTE:-origin}
refspec=${CASK_PUSH_REFSPEC:-HEAD:refs/heads/main}

git -c "http.extraheader=AUTHORIZATION: bearer ${CASK_GITHUB_TOKEN}" \
    push "$remote" "$refspec"
