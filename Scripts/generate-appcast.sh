#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SPARKLE_VERSION=2.9.6
OUTPUT_DIR="$ROOT_DIR/dist"
ARM64_DMG=
X86_64_DMG=
VERSION=
TAG=
NOTES=
DOWNLOAD_URL_PREFIX=
PUBLIC_KEY=
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERIFY="$SCRIPT_DIR/verify-sparkle-appcast.py"

usage() {
    printf '%s\n' "Usage: $0 --version VERSION --tag TAG --arm64-dmg PATH --x86_64-dmg PATH --notes FILE [--output DIR] [--download-url-prefix URL] [--public-key B64] [--info-plist PATH]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            VERSION=${2:?"--version requires a value"}
            shift 2
            ;;
        --tag)
            TAG=${2:?"--tag requires a value"}
            shift 2
            ;;
        --arm64-dmg)
            ARM64_DMG=${2:?"--arm64-dmg requires a value"}
            shift 2
            ;;
        --x86_64-dmg)
            X86_64_DMG=${2:?"--x86_64-dmg requires a value"}
            shift 2
            ;;
        --output)
            OUTPUT_DIR=${2:?"--output requires a value"}
            shift 2
            ;;
        --notes)
            NOTES=${2:?"--notes requires a value"}
            shift 2
            ;;
        --download-url-prefix)
            DOWNLOAD_URL_PREFIX=${2:?"--download-url-prefix requires a value"}
            shift 2
            ;;
        --public-key)
            PUBLIC_KEY=${2:?"--public-key requires a value"}
            shift 2
            ;;
        --info-plist)
            INFO_PLIST=${2:?"--info-plist requires a value"}
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

if [ -z "$VERSION" ] || [ -z "$TAG" ] || [ -z "$ARM64_DMG" ] || [ -z "$X86_64_DMG" ] || [ -z "$NOTES" ]; then
    usage >&2
    exit 2
fi

case "$OUTPUT_DIR" in
    /*) ;;
    *) OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR" ;;
esac

case "$ARM64_DMG" in
    /*) ;;
    *) ARM64_DMG="$ROOT_DIR/$ARM64_DMG" ;;
esac

case "$X86_64_DMG" in
    /*) ;;
    *) X86_64_DMG="$ROOT_DIR/$X86_64_DMG" ;;
esac

case "$NOTES" in
    /*) NOTES_PATH=$NOTES ;;
    *) NOTES_PATH="$ROOT_DIR/$NOTES" ;;
esac

case "$INFO_PLIST" in
    /*) ;;
    *) INFO_PLIST="$ROOT_DIR/$INFO_PLIST" ;;
esac

if [ ! -f "$ARM64_DMG" ]; then
    printf 'arm64 DMG is missing: %s\n' "$ARM64_DMG" >&2
    exit 1
fi
if [ ! -f "$X86_64_DMG" ]; then
    printf 'x86_64 DMG is missing: %s\n' "$X86_64_DMG" >&2
    exit 1
fi
if [ ! -f "$NOTES_PATH" ]; then
    printf 'Release notes file is missing: %s\n' "$NOTES_PATH" >&2
    exit 1
fi
if [ ! -s "$NOTES_PATH" ]; then
    printf 'Release notes file is empty: %s\n' "$NOTES_PATH" >&2
    exit 1
fi
if [ ! -x "$VERIFY" ]; then
    printf 'Appcast verifier is missing: %s\n' "$VERIFY" >&2
    exit 1
fi

if [ -z "$DOWNLOAD_URL_PREFIX" ]; then
    DOWNLOAD_URL_PREFIX="https://github.com/shiquda/SpotAsk/releases/download/${TAG}/"
fi

KEY_FILE=${SPARKLE_ED_PRIVATE_KEY_FILE:-}
if [ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ] && [ -z "$KEY_FILE" ]; then
    printf '%s\n' "SPARKLE_ED_PRIVATE_KEY or SPARKLE_ED_PRIVATE_KEY_FILE is required to sign appcasts." >&2
    exit 1
fi
if [ -n "$KEY_FILE" ] && [ ! -f "$KEY_FILE" ]; then
    printf 'EdDSA private key file is missing: %s\n' "$KEY_FILE" >&2
    exit 1
fi

NOTES_TOKEN=$(awk 'NF { print; exit }' "$NOTES_PATH")
if [ -z "$NOTES_TOKEN" ]; then
    printf 'Release notes file has no text: %s\n' "$NOTES_PATH" >&2
    exit 1
fi

find_generate_appcast() {
    if [ -n "${SPARKLE_TOOLS_DIR:-}" ] && [ -x "$SPARKLE_TOOLS_DIR/generate_appcast" ]; then
        printf '%s\n' "$SPARKLE_TOOLS_DIR/generate_appcast"
        return
    fi
    if [ -x "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" ]; then
        printf '%s\n' "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
        return
    fi

    tools_cache="$ROOT_DIR/.build/sparkle-tools-$SPARKLE_VERSION"
    if [ ! -x "$tools_cache/bin/generate_appcast" ]; then
        mkdir -p "$tools_cache"
        zip_path="$tools_cache/Sparkle-for-Swift-Package-Manager.zip"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip" -o "$zip_path"
        unzip -qo "$zip_path" -d "$tools_cache"
    fi
    if [ -x "$tools_cache/bin/generate_appcast" ]; then
        printf '%s\n' "$tools_cache/bin/generate_appcast"
        return
    fi
    printf '%s\n' "Unable to locate Sparkle generate_appcast" >&2
    exit 1
}

GENERATE_APPCAST=$(find_generate_appcast)

run_generate_appcast() {
    archive_dir=$1
    output_path=$2
    if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
        printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$GENERATE_APPCAST" \
            --ed-key-file - \
            --embed-release-notes \
            --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
            --link "https://github.com/shiquda/SpotAsk/releases/latest" \
            --maximum-deltas 0 \
            -o "$output_path" \
            "$archive_dir"
    else
        "$GENERATE_APPCAST" \
            --ed-key-file "$KEY_FILE" \
            --embed-release-notes \
            --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
            --link "https://github.com/shiquda/SpotAsk/releases/latest" \
            --maximum-deltas 0 \
            -o "$output_path" \
            "$archive_dir"
    fi
}

stage_archive() {
    archive_dir=$1
    dmg_path=$2
    mkdir -p "$archive_dir"
    cp "$dmg_path" "$archive_dir/$(basename "$dmg_path")"
    dmg_name=$(basename "$dmg_path")
    cp "$NOTES_PATH" "$archive_dir/${dmg_name%.*}.md"
}

verify_feed() {
    xml_path=$1
    archive_path=$2
    if [ -n "$PUBLIC_KEY" ]; then
        python3 "$VERIFY" \
            --xml "$xml_path" \
            --archive "$archive_path" \
            --public-key "$PUBLIC_KEY" \
            --notes-token "$NOTES_TOKEN"
    else
        python3 "$VERIFY" \
            --xml "$xml_path" \
            --archive "$archive_path" \
            --info-plist "$INFO_PLIST" \
            --notes-token "$NOTES_TOKEN"
    fi
}

mkdir -p "$OUTPUT_DIR"
ARM64_DIR="$OUTPUT_DIR/.appcast-arm64"
X86_DIR="$OUTPUT_DIR/.appcast-x86_64"
rm -rf "$ARM64_DIR" "$X86_DIR"
stage_archive "$ARM64_DIR" "$ARM64_DMG"
stage_archive "$X86_DIR" "$X86_64_DMG"

run_generate_appcast "$ARM64_DIR" "$OUTPUT_DIR/appcast-arm64.xml"
run_generate_appcast "$X86_DIR" "$OUTPUT_DIR/appcast-x86_64.xml"

if [ ! -s "$OUTPUT_DIR/appcast-arm64.xml" ] || [ ! -s "$OUTPUT_DIR/appcast-x86_64.xml" ]; then
    printf '%s\n' "generate_appcast did not write both architecture feeds" >&2
    exit 1
fi

verify_feed "$OUTPUT_DIR/appcast-arm64.xml" "$ARM64_DMG"
verify_feed "$OUTPUT_DIR/appcast-x86_64.xml" "$X86_64_DMG"

printf 'Wrote %s and %s\n' "$OUTPUT_DIR/appcast-arm64.xml" "$OUTPUT_DIR/appcast-x86_64.xml"
