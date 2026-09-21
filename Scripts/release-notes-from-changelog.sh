#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EN_CHANGELOG="$ROOT_DIR/CHANGELOG.md"
ZH_CHANGELOG="$ROOT_DIR/CHANGELOG.zh-CN.md"

usage() {
    printf 'Usage: %s <vX.Y.Z> [--en|--zh|--all]\n' "$0" >&2
    printf '%s\n' \
        '  --en   English section from CHANGELOG.md' \
        '  --zh   Chinese section from CHANGELOG.zh-CN.md' \
        '  --all  Chinese section first, English section second (default);' \
        '         degrades to English only when the Chinese section is missing' >&2
}

RELEASE_TAG=
MODE=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --en|--zh|--all)
            if [ -n "$MODE" ]; then
                printf 'Release notes mode flags are mutually exclusive\n' >&2
                usage
                exit 2
            fi
            MODE=${1#--}
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            printf 'Unknown option: %s\n' "$1" >&2
            usage
            exit 2
            ;;
        *)
            if [ -n "$RELEASE_TAG" ]; then
                printf 'Unexpected extra argument: %s\n' "$1" >&2
                usage
                exit 2
            fi
            RELEASE_TAG=$1
            shift
            ;;
    esac
done

if [ -z "$MODE" ]; then
    MODE=all
fi

case "$RELEASE_TAG" in
    v*) ;;
    *)
        usage
        exit 2
        ;;
esac

VERSION=${RELEASE_TAG#v}

# Print the body of the "## [VERSION]" section of one changelog.
# Exits 1 when the changelog, the section, or the section content is missing.
changelog_section() {
    changelog=$1
    [ -f "$changelog" ] || return 1
    body=$(awk -v version="$VERSION" '
        $0 ~ "^## \\[" version "\\]" { found = 1; next }
        found && /^## / { exit }
        found && /^\[[^]]*\]:/ { exit }
        found { print }
        END { if (!found) exit 1 }
    ' "$changelog") || return 1
    body=$(printf '%s\n' "$body" | awk '
        /^[[:space:]]*$/ { if (seen) blank++; next }
        { while (blank > 0) { print ""; blank-- } print; seen = 1 }
    ')
    [ -n "$body" ] || return 1
    printf '%s\n' "$body"
}

if ! EN_NOTES=$(changelog_section "$EN_CHANGELOG"); then
    printf 'CHANGELOG.md has no release notes for %s\n' "$RELEASE_TAG" >&2
    exit 1
fi

case "$MODE" in
    en)
        printf '%s\n' "$EN_NOTES"
        exit 0
        ;;
    zh|all) ;;
esac

if ZH_NOTES=$(changelog_section "$ZH_CHANGELOG"); then
    ZH_AVAILABLE=1
else
    ZH_NOTES=
    ZH_AVAILABLE=0
fi

if [ "$MODE" = zh ]; then
    if [ "$ZH_AVAILABLE" -eq 0 ]; then
        printf 'CHANGELOG.zh-CN.md has no release notes for %s\n' "$RELEASE_TAG" >&2
        exit 1
    fi
    printf '%s\n' "$ZH_NOTES"
    exit 0
fi

if [ "$ZH_AVAILABLE" -eq 1 ]; then
    printf '**中文**\n\n%s\n\n---\n\n**English**\n\n%s\n' "$ZH_NOTES" "$EN_NOTES"
else
    printf 'CHANGELOG.zh-CN.md has no release notes for %s; writing English-only release notes\n' "$RELEASE_TAG" >&2
    printf '%s\n' "$EN_NOTES"
fi
