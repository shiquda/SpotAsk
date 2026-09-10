#!/bin/sh
set -eu

# Push the current HEAD to a cask-update branch and open (or reuse) a PR.
# Never push to main: the default branch requires CI status checks.

RELEASE_TAG=${RELEASE_TAG:?RELEASE_TAG is required}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}

branch="chore/homebrew-cask-${RELEASE_TAG}"
git push --force-with-lease origin "HEAD:refs/heads/${branch}"

existing=$(gh pr list --repo "$GITHUB_REPOSITORY" --head "$branch" --base main --state open --json number --jq '.[0].number // empty')
if [ -n "$existing" ]; then
    echo "Updated existing Homebrew cask PR #${existing}"
    gh pr view "$existing" --repo "$GITHUB_REPOSITORY" --json url --jq .url
    exit 0
fi

gh pr create --repo "$GITHUB_REPOSITORY" \
    --base main \
    --head "$branch" \
    --title "chore: update Homebrew cask for ${RELEASE_TAG}" \
    --body "The Release workflow published ${RELEASE_TAG} and needs the Homebrew cask hashes updated.

\`main\` requires arm64/x86_64 status checks, so this commit cannot be pushed directly."
