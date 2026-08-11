#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RELEASE_TAG=${1:-}

case "$RELEASE_TAG" in
    v*) ;;
    *)
        printf 'Usage: %s <vX.Y.Z>\n' "$0" >&2
        exit 2
        ;;
esac

VERSION=${RELEASE_TAG#v}
awk -v version="$VERSION" '
    $0 ~ "^## \\[" version "\\]" { found = 1; next }
    found && /^## / { exit }
    found { print }
    END { if (!found) exit 1 }
' "$ROOT_DIR/CHANGELOG.md"
