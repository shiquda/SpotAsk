#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCH=$(uname -m)
APP_DIR=${SPOTASK_DEBUG_APP_PATH:-"$HOME/Applications/SpotAsk Debug.app"}
BUNDLE_IDENTIFIER=com.spotask.app.debug
DISPLAY_NAME="SpotAsk Debug"

SIGN_IDENTITY=${SPOTASK_DEBUG_CODESIGN_IDENTITY:-}
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
        | sed -n 's/^[[:space:]]*[0-9][0-9]*)[[:space:]]*[0-9A-Fa-f]*[[:space:]]*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)
fi
if [ -z "$SIGN_IDENTITY" ]; then
    printf '%s\n' 'No Apple Development signing identity is available for SpotAsk Debug.' >&2
    printf '%s\n' 'Open Xcode > Settings > Accounts and create an Apple Development certificate.' >&2
    exit 1
fi

DEBUG_EXECUTABLE="$APP_DIR/Contents/MacOS/SpotAsk"
for pid in $(pgrep -x SpotAsk || true); do
    if [ "$(ps -p "$pid" -o command=)" = "$DEBUG_EXECUTABLE" ]; then
        kill -TERM "$pid"
    fi
done

SPOTASK_SKIP_MIGRATION=1 "$ROOT_DIR/Scripts/make-app-bundle.sh" \
    --arch "$ARCH" \
    --configuration Debug \
    --output "$APP_DIR" \
    --bundle-identifier "$BUNDLE_IDENTIFIER" \
    --display-name "$DISPLAY_NAME" \
    --sign-identity "$SIGN_IDENTITY"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$APP_DIR"

printf 'Installed SpotAsk Debug: %s\n' "$APP_DIR"
printf 'Bundle identifier: %s\n' "$BUNDLE_IDENTIFIER"
open "$APP_DIR"
