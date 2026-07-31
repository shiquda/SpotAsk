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

BUILD_DIR="$ROOT_DIR/.build/release-$ARCH"
TRIPLE="$ARCH-apple-macosx15.0"
RELEASE_DIR="$BUILD_DIR/$ARCH-apple-macosx/release"

cd "$ROOT_DIR"
swift build -c release --triple "$TRIPLE" --scratch-path "$BUILD_DIR"

if [ ! -x "$RELEASE_DIR/SpotAsk" ] || [ ! -d "$RELEASE_DIR/SpotAsk_SpotAsk.bundle" ]; then
    printf 'Release artifacts are missing from %s\n' "$RELEASE_DIR" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/en.lproj" "$APP_DIR/Contents/Resources/zh-Hans.lproj"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$RELEASE_DIR/SpotAsk" "$APP_DIR/Contents/MacOS/SpotAsk"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$RELEASE_DIR/SpotAsk_SpotAsk.bundle" "$APP_DIR/"
cp "$ROOT_DIR/Sources/SpotAsk/Resources/en.lproj/AppShortcuts.strings" "$APP_DIR/Contents/Resources/en.lproj/"
cp "$ROOT_DIR/Sources/SpotAsk/Resources/zh-Hans.lproj/AppShortcuts.strings" "$APP_DIR/Contents/Resources/zh-Hans.lproj/"

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
if ! file "$APP_DIR/Contents/MacOS/SpotAsk" | grep -q "$ARCH"; then
    printf 'Bundle executable does not contain the requested %s architecture\n' "$ARCH" >&2
    exit 1
fi
if [ ! -f "$APP_DIR/SpotAsk_SpotAsk.bundle/en.lproj/Localizable.strings" ] \
    || [ ! -f "$APP_DIR/SpotAsk_SpotAsk.bundle/zh-hans.lproj/Localizable.strings" ] \
    || [ ! -f "$APP_DIR/Contents/Resources/en.lproj/AppShortcuts.strings" ] \
    || [ ! -f "$APP_DIR/Contents/Resources/zh-Hans.lproj/AppShortcuts.strings" ]; then
    printf '%s\n' "Release bundle is missing localized app or shortcut resources" >&2
    exit 1
fi

printf 'Built Release bundle: %s\n' "$APP_DIR"
