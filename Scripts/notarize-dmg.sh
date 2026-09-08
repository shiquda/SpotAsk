#!/bin/sh
set -eu

PROFILE=${SPOTASK_NOTARY_KEYCHAIN_PROFILE:-}
APPLE_ID=${SPOTASK_NOTARY_APPLE_ID:-}
TEAM_ID=${SPOTASK_NOTARY_TEAM_ID:-}
PASSWORD=${SPOTASK_NOTARY_PASSWORD:-}

usage() {
    printf '%s\n' "Usage: $0 submit DMG [--wait|--no-wait] | info SUBMISSION_ID | log SUBMISSION_ID [OUTPUT_PATH] | staple DMG"
}

run_notarytool() {
    command=$1
    shift

    if [ -n "$PROFILE" ]; then
        xcrun notarytool "$command" --keychain-profile "$PROFILE" "$@"
        return
    fi

    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$PASSWORD" ]; then
        printf '%s\n' "Set SPOTASK_NOTARY_KEYCHAIN_PROFILE or all direct Apple ID credentials" >&2
        exit 1
    fi

    xcrun notarytool "$command" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$PASSWORD" \
        "$@"
}

command=${1:-}
case "$command" in
    submit)
        DMG_PATH=${2:?"submit requires a DMG path"}
        shift 2 || true
        WAIT_FLAG="--wait"
        for arg in "$@"; do
            case "$arg" in
                --no-wait) WAIT_FLAG="--no-wait" ;;
                --wait) WAIT_FLAG="--wait" ;;
            esac
        done
        if [ "$WAIT_FLAG" = "--wait" ]; then
            run_notarytool submit "$DMG_PATH" --wait --timeout 30m
        else
            run_notarytool submit "$DMG_PATH" --no-wait --output-format json
        fi
        ;;
    info)
        SUBMISSION_ID=${2:?"info requires a submission ID"}
        run_notarytool info "$SUBMISSION_ID" --output-format json
        ;;
    log)
        SUBMISSION_ID=${2:?"log requires a submission ID"}
        if [ "$#" -ge 3 ]; then
            run_notarytool log "$SUBMISSION_ID" "$3"
        else
            run_notarytool log "$SUBMISSION_ID"
        fi
        ;;
    staple)
        DMG_PATH=${2:?"staple requires a DMG path"}
        xcrun stapler staple "$DMG_PATH"
        xcrun stapler validate "$DMG_PATH"
        spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
