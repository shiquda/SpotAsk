#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCH=$(uname -m)
OUTPUT_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY=${SPOTASK_CODESIGN_IDENTITY:--}
REQUIRE_DEVELOPER_ID=${SPOTASK_REQUIRE_DEVELOPER_ID:-0}
REQUIRE_NOTARIZATION=${SPOTASK_REQUIRE_NOTARIZATION:-0}
NOTARY_KEYCHAIN_PROFILE=${SPOTASK_NOTARY_KEYCHAIN_PROFILE:-}
NOTARY_KEYCHAIN=${SPOTASK_NOTARY_KEYCHAIN:-}
ENTITLEMENTS_PATH=${SPOTASK_ENTITLEMENTS_PATH:-"$ROOT_DIR/Config/SpotAsk.selection-assistant.entitlements"}

usage() {
    printf '%s\n' "Usage: $0 [--arch arm64|x86_64] [--output DIRECTORY] [--sign-identity IDENTITY] [--entitlements PATH] [--require-developer-id]"
    printf '%s\n' "The default entitlements are the non-sandboxed selection assistant configuration used by the local release build."
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
        --sign-identity)
            SIGN_IDENTITY=${2:?"--sign-identity requires a value"}
            shift 2
            ;;
        --entitlements)
            ENTITLEMENTS_PATH=${2:?"--entitlements requires a value"}
            shift 2
            ;;
        --require-developer-id)
            REQUIRE_DEVELOPER_ID=1
            shift
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

case "$REQUIRE_NOTARIZATION" in
    0|1) ;;
    *)
        printf 'SPOTASK_REQUIRE_NOTARIZATION must be 0 or 1, got: %s\n' "$REQUIRE_NOTARIZATION" >&2
        exit 2
        ;;
esac

if [ "$REQUIRE_NOTARIZATION" = 1 ] && [ -z "$NOTARY_KEYCHAIN_PROFILE" ]; then
    printf '%s\n' "A notarytool keychain profile is required" >&2
    exit 1
fi

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

set -- --arch "$ARCH" --output "$STAGING_DIR/SpotAsk.app" --sign-identity "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS_PATH"
if [ "$REQUIRE_DEVELOPER_ID" = 1 ]; then
    set -- "$@" --require-developer-id
fi
"$ROOT_DIR/Scripts/make-app-bundle.sh" "$@"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "SpotAsk" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
if [ "$SIGN_IDENTITY" != - ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR"

if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
    set -- submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait --timeout 30m
    if [ -n "$NOTARY_KEYCHAIN" ]; then
        set -- "$@" --keychain "$NOTARY_KEYCHAIN"
    fi
    xcrun notarytool "$@"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

if [ "$REQUIRE_DEVELOPER_ID" = 1 ]; then
    codesign --verify --verbose=4 "$DMG_PATH"
fi

printf 'Built DMG: %s\n' "$DMG_PATH"
