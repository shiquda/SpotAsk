#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/build/SpotAsk.app"

cd "$ROOT_DIR"
swift build
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/.build/debug/SpotAsk" "$APP_DIR/Contents/MacOS/SpotAsk"

printf 'Built %s\n' "$APP_DIR"
