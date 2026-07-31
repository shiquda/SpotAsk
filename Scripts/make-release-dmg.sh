#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCH=$(uname -m)
OUTPUT_DIR="$ROOT_DIR/dist"

usage() {
    printf '%s\n' "Usage: $0 [--arch arm64|x86_64] [--output DIRECTORY]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch)
            ARCH=${2:?"--arch requires a value"}
            shift 2
            ;;
        --output)
            OUTPUT_DIR=${2:?"--output requires a value"}
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

case "$ARCH" in
    arm64|x86_64) ;;
    *)
        printf 'Unsupported architecture: %s\n' "$ARCH" >&2
        exit 2
        ;;
esac

case "$OUTPUT_DIR" in
    /*) DIST_DIR="$OUTPUT_DIR" ;;
    *) DIST_DIR="$ROOT_DIR/$OUTPUT_DIR" ;;
esac

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")
STAGING_DIR="$DIST_DIR/.staging-SpotAsk-$ARCH"
DMG_PATH="$DIST_DIR/SpotAsk-$VERSION-$ARCH.dmg"

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

"$ROOT_DIR/Scripts/make-app-bundle.sh" --arch "$ARCH" --output "$STAGING_DIR/SpotAsk.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "SpotAsk" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR"

printf 'Built DMG without Developer ID: %s\n' "$DMG_PATH"
