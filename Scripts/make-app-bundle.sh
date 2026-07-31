#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCH=$(uname -m)
OUTPUT_DIR="$ROOT_DIR/build/SpotAsk.app"

usage() {
    printf '%s\n' "Usage: $0 [--arch arm64|x86_64] [--output APP_PATH]"
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
    /*) APP_DIR="$OUTPUT_DIR" ;;
    *) APP_DIR="$ROOT_DIR/$OUTPUT_DIR" ;;
esac

BUILD_DIR="$ROOT_DIR/.build/xcode-release-$ARCH"
RELEASE_APP_DIR="$BUILD_DIR/Build/Products/Release/SpotAsk.app"

cd "$ROOT_DIR"
xcodebuild \
    -project SpotAsk.xcodeproj \
    -scheme SpotAsk \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    ARCHS="$ARCH" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build

if [ ! -x "$RELEASE_APP_DIR/Contents/MacOS/SpotAsk" ]; then
    printf 'Release app is missing from %s\n' "$RELEASE_APP_DIR" >&2
    exit 1
fi

rm -rf "$APP_DIR"
ditto "$RELEASE_APP_DIR" "$APP_DIR"
codesign --force --sign - --entitlements "$ROOT_DIR/Config/SpotAsk.entitlements" "$APP_DIR"

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
if ! file "$APP_DIR/Contents/MacOS/SpotAsk" | grep -q "$ARCH"; then
    printf 'Bundle executable does not contain the requested %s architecture\n' "$ARCH" >&2
    exit 1
fi
if [ ! -f "$APP_DIR/Contents/Resources/Metadata.appintents/extract.actionsdata" ] \
    || [ ! -f "$APP_DIR/Contents/Resources/en.lproj/Localizable.strings" ] \
    || [ ! -f "$APP_DIR/Contents/Resources/zh-Hans.lproj/Localizable.strings" ] \
    || [ ! -f "$APP_DIR/Contents/Resources/en.lproj/AppShortcuts.strings" ] \
    || [ ! -f "$APP_DIR/Contents/Resources/zh-Hans.lproj/AppShortcuts.strings" ]; then
    printf '%s\n' "Release bundle is missing App Intents or localized resources" >&2
    exit 1
fi
codesign --verify --strict "$APP_DIR"

printf 'Built Release bundle: %s\n' "$APP_DIR"
