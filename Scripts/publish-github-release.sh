#!/bin/sh
set -eu

usage() {
    printf '%s\n' "Usage: $0 --tag TAG --repo OWNER/NAME --notes FILE -- asset [asset...]" >&2
}

TAG=
REPO=
NOTES=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            TAG=${2:?--tag requires a value}
            shift 2
            ;;
        --repo)
            REPO=${2:?--repo requires a value}
            shift 2
            ;;
        --notes)
            NOTES=${2:?--notes requires a value}
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [ -z "$TAG" ] || [ -z "$REPO" ] || [ -z "$NOTES" ] || [ "$#" -eq 0 ]; then
    usage
    exit 2
fi

if [ ! -f "$NOTES" ]; then
    printf '%s\n' "Release notes file not found: $NOTES" >&2
    exit 1
fi

for asset in "$@"; do
    if [ ! -f "$asset" ]; then
        printf '%s\n' "Release asset not found: $asset" >&2
        exit 1
    fi
done

if release_json=$(gh release view "$TAG" --repo "$REPO" --json isDraft 2>/dev/null); then
    is_draft=$(printf '%s' "$release_json" | jq -r '.isDraft')
    if [ "$is_draft" != true ]; then
        printf '%s\n' "Release $TAG is already published; refusing to replace assets." >&2
        exit 1
    fi
    gh release edit "$TAG" --repo "$REPO" --notes-file "$NOTES"
else
    gh release create "$TAG" \
        --repo "$REPO" \
        --draft \
        --verify-tag \
        --title "$TAG" \
        --notes-file "$NOTES"
fi

gh release upload "$TAG" --repo "$REPO" "$@" --clobber

asset_names=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')
for asset in "$@"; do
    name=$(basename "$asset")
    if ! printf '%s\n' "$asset_names" | grep -qx "$name"; then
        printf '%s\n' "Release $TAG is missing asset $name; leaving it as a draft." >&2
        exit 1
    fi
done

printf '%s\n' "$asset_names" | while IFS= read -r name; do
    case "$name" in
        notary-*.json)
            gh release delete-asset "$TAG" "$name" --yes --repo "$REPO" || true
            ;;
    esac
done

gh release edit "$TAG" --repo "$REPO" --draft=false
printf '%s\n' "Published $TAG"
