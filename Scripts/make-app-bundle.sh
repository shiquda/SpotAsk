#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCH=$(uname -m)
OUTPUT_DIR="$ROOT_DIR/build/SpotAsk.app"
SIGN_IDENTITY=${SPOTASK_CODESIGN_IDENTITY:-}
REQUIRE_DEVELOPER_ID=${SPOTASK_REQUIRE_DEVELOPER_ID:-0}
BUNDLE_IDENTIFIER=
DISPLAY_NAME=
ENTITLEMENTS_PATH="$ROOT_DIR/Config/SpotAsk.selection-assistant.entitlements"

usage() {
    printf '%s\n' "Usage: $0 [--arch arm64|x86_64] [--output APP_PATH] [--bundle-identifier ID] [--display-name NAME] [--sign-identity IDENTITY] [--entitlements PATH] [--require-developer-id]"
    printf '%s\n' "When --sign-identity is omitted, the first available code signing identity is used so Accessibility grants survive rebuilds."
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
        --bundle-identifier)
            BUNDLE_IDENTIFIER=${2:?"--bundle-identifier requires a value"}
            shift 2
            ;;
        --display-name)
            DISPLAY_NAME=${2:?"--display-name requires a value"}
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

case "$REQUIRE_DEVELOPER_ID" in
    0|1) ;;
    *)
        printf 'SPOTASK_REQUIRE_DEVELOPER_ID must be 0 or 1, got: %s\n' "$REQUIRE_DEVELOPER_ID" >&2
        exit 2
        ;;
esac

if [ "$REQUIRE_DEVELOPER_ID" = 1 ] && [ -z "$SIGN_IDENTITY" ]; then
    printf '%s\n' "A Developer ID Application signing identity is required" >&2
    exit 1
fi

if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
        | sed -n 's/^[[:space:]]*[0-9][0-9]*)[[:space:]]*[0-9A-Fa-f]*[[:space:]]*"\(.*\)".*/\1/p' \
        | head -n 1)
    if [ -n "$SIGN_IDENTITY" ]; then
        printf 'Using stable signing identity: %s\n' "$SIGN_IDENTITY" >&2
    else
        SIGN_IDENTITY=-
        printf '%s\n' 'Warning: no code signing identity found; using ad-hoc signature. Accessibility permission will reset on every rebuild.' >&2
    fi
fi

case "$ENTITLEMENTS_PATH" in
    /*) ;;
    *) ENTITLEMENTS_PATH="$ROOT_DIR/$ENTITLEMENTS_PATH" ;;
esac

if [ ! -f "$ENTITLEMENTS_PATH" ]; then
    printf 'Entitlements file is missing: %s\n' "$ENTITLEMENTS_PATH" >&2
    exit 1
fi

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

OLD_REQUIREMENT=
HAD_PREVIOUS_INSTALL=0
if [ -d "$APP_DIR" ]; then
    HAD_PREVIOUS_INSTALL=1
    OLD_REQUIREMENT=$(codesign -d -r- "$APP_DIR" 2>/dev/null \
        | sed -n 's/^designated => //p')
fi

rm -rf "$APP_DIR"
ditto "$RELEASE_APP_DIR" "$APP_DIR"
if [ -n "$BUNDLE_IDENTIFIER" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
fi
if [ -n "$DISPLAY_NAME" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$APP_DIR/Contents/Info.plist"
fi
if [ "$SIGN_IDENTITY" = - ]; then
    codesign --force --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_DIR"
else
    codesign \
        --force \
        --sign "$SIGN_IDENTITY" \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS_PATH" \
        "$APP_DIR"
fi

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

NEW_REQUIREMENT=$(codesign -d -r- "$APP_DIR" 2>/dev/null \
    | sed -n 's/^designated => //p')
INSTALLED_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)
if [ "$HAD_PREVIOUS_INSTALL" = 1 ] \
    && [ "$OLD_REQUIREMENT" != "$NEW_REQUIREMENT" ] \
    && [ -n "$INSTALLED_BUNDLE_ID" ]; then
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
    if tccutil reset Accessibility "$INSTALLED_BUNDLE_ID" >/dev/null 2>&1; then
        printf 'Reset stale Accessibility grant for %s due to signing identity change.\n' "$INSTALLED_BUNDLE_ID"
    else
        printf 'Warning: unable to reset stale Accessibility grant for %s; re-grant it manually after install.\n' "$INSTALLED_BUNDLE_ID" >&2
    fi
fi

SIGNATURE_DETAILS=$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)
TEAM_ID=$(printf '%s\n' "$SIGNATURE_DETAILS" | sed -n 's/^TeamIdentifier=//p')
if [ "$REQUIRE_DEVELOPER_ID" = 1 ]; then
    if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -q '^Authority=Developer ID Application:'; then
        printf '%s\n' "Release bundle is not signed with a Developer ID Application certificate" >&2
        exit 1
    fi
    if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" = "not set" ]; then
        printf '%s\n' "Release bundle does not have a TeamIdentifier" >&2
        exit 1
    fi
    if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -q 'flags=.*runtime'; then
        printf '%s\n' "Release bundle does not have hardened runtime enabled" >&2
        exit 1
    fi
fi

printf 'Built Release bundle: %s (TeamIdentifier: %s)\n' "$APP_DIR" "${TEAM_ID:-not set}"

migrate_unsandboxed_data() {
    [ "${SPOTASK_SKIP_MIGRATION:-0}" = 1 ] && return 0

    HOME_DIR=${HOME:-}
    [ -n "$HOME_DIR" ] || { printf '%s\n' 'Warning: cannot resolve home directory; skipping data migration.' >&2; return 0; }

    CONTAINER_PREFS="$HOME_DIR/Library/Containers/com.spotask.app/Data/Library/Preferences/com.spotask.app.plist"
    DEST_PREFS="$HOME_DIR/Library/Preferences/com.spotask.app.plist"
    CONTAINER_SUPPORT="$HOME_DIR/Library/Containers/com.spotask.app/Data/Library/Application Support/SpotAsk"
    DEST_SUPPORT="$HOME_DIR/Library/Application Support/SpotAsk"
    BACKUP_SUFFIX=".pre-unsandbox-$(date +%Y%m%d%H%M%S)"

    if [ -f "$CONTAINER_PREFS" ]; then
        if [ -f "$DEST_PREFS" ]; then
            cp -p "$DEST_PREFS" "$DEST_PREFS$BACKUP_SUFFIX"
            printf 'Backed up existing preferences to %s\n' "$DEST_PREFS$BACKUP_SUFFIX" >&2
        fi
        mkdir -p "$(dirname "$DEST_PREFS")"
        cp "$CONTAINER_PREFS" "$DEST_PREFS"
        chmod 600 "$DEST_PREFS"
        printf 'Migrated preferences from sandbox container to %s\n' "$DEST_PREFS" >&2
    fi

    if [ -f "$CONTAINER_SUPPORT/credentials.json" ]; then
        mkdir -p "$DEST_SUPPORT"
        if [ -f "$DEST_SUPPORT/credentials.json" ]; then
            cp -p "$DEST_SUPPORT/credentials.json" "$DEST_SUPPORT/credentials.json$BACKUP_SUFFIX"
            printf 'Backed up existing credentials to %s\n' "$DEST_SUPPORT/credentials.json$BACKUP_SUFFIX" >&2
        fi
        cp "$CONTAINER_SUPPORT/credentials.json" "$DEST_SUPPORT/credentials.json"
        chmod 600 "$DEST_SUPPORT/credentials.json"
        printf 'Migrated credentials from sandbox container to %s\n' "$DEST_SUPPORT/credentials.json" >&2
    fi

    if [ ! -f "$DEST_SUPPORT/Diagnostics/diagnostics.json" ] && [ -f "$CONTAINER_SUPPORT/Diagnostics/diagnostics.json" ]; then
        mkdir -p "$DEST_SUPPORT/Diagnostics"
        cp "$CONTAINER_SUPPORT/Diagnostics/diagnostics.json" "$DEST_SUPPORT/Diagnostics/diagnostics.json"
        chmod 600 "$DEST_SUPPORT/Diagnostics/diagnostics.json"
        printf 'Migrated diagnostics from sandbox container to %s\n' "$DEST_SUPPORT/Diagnostics/diagnostics.json" >&2
    fi
}

migrate_unsandboxed_data
