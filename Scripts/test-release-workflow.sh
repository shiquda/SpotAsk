#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PUBLISH="$ROOT_DIR/Scripts/publish-github-release.sh"
NOTARIZE="$ROOT_DIR/Scripts/notarize-dmg.sh"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spotask-release-test.XXXXXX")
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

pass() {
    printf 'PASS: %s\n' "$1"
}

command -v jq >/dev/null || fail "jq is required"
command -v shasum >/dev/null || fail "shasum is required"

# --- checksums use basenames so downloaded assets verify ---
checksum_src="$WORK_DIR/checksum-src"
checksum_dl="$WORK_DIR/checksum-dl"
mkdir -p "$checksum_src" "$checksum_dl"
printf 'arm64-fixture\n' > "$checksum_src/SpotAsk-0.2.1-arm64.dmg"
printf 'x86-fixture\n' > "$checksum_src/SpotAsk-0.2.1-x86_64.dmg"
(
    cd "$checksum_src"
    shasum -a 256 SpotAsk-*.dmg > SpotAsk-v0.2.1-SHA256SUMS.txt
)
grep -q '^dist/' "$checksum_src/SpotAsk-v0.2.1-SHA256SUMS.txt" && fail "checksums still include dist/ prefixes"
cp "$checksum_src/SpotAsk-0.2.1-arm64.dmg" \
    "$checksum_src/SpotAsk-0.2.1-x86_64.dmg" \
    "$checksum_src/SpotAsk-v0.2.1-SHA256SUMS.txt" \
    "$checksum_dl/"
(
    cd "$checksum_dl"
    shasum -a 256 -c SpotAsk-v0.2.1-SHA256SUMS.txt
) >/dev/null
pass "basename checksums verify next to downloaded DMGs"

# --- gh stub for publish ordering / immutability ---
install_gh_stub() {
    stub_dir=$1
    state_dir=$2
    mkdir -p "$stub_dir" "$state_dir"
    printf '%s\n' "$state_dir" > "$stub_dir/.state-dir"
    cat > "$stub_dir/gh" <<'EOF'
#!/bin/sh
set -eu
STATE_DIR=$(cat "$(dirname "$0")/.state-dir")
LOG=$STATE_DIR/commands.log
printf '%s\n' "$*" >> "$LOG"

case "${1-} ${2-}" in
    "release view")
        tag=$3
        if [ ! -f "$STATE_DIR/$tag.state" ]; then
            exit 1
        fi
        state=$(cat "$STATE_DIR/$tag.state")
        json_flag=
        jq_filter=
        shift 3
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --json) json_flag=$2; shift 2 ;;
                --jq) jq_filter=$2; shift 2 ;;
                --repo) shift 2 ;;
                *) shift ;;
            esac
        done
        if [ "$json_flag" = isDraft ]; then
            if [ "$state" = draft ]; then
                printf '%s\n' '{"isDraft":true}'
            else
                printf '%s\n' '{"isDraft":false}'
            fi
            exit 0
        fi
        if [ "$json_flag" = assets ]; then
            assets='[]'
            if [ -f "$STATE_DIR/$tag.assets" ]; then
                assets=$(jq -R -s -c 'split("\n") | map(select(length>0)) | map({name:.})' "$STATE_DIR/$tag.assets")
            fi
            payload=$(printf '{"assets":%s}' "$assets")
            if [ -n "$jq_filter" ]; then
                printf '%s\n' "$payload" | jq -r "$jq_filter"
            else
                printf '%s\n' "$payload"
            fi
            exit 0
        fi
        exit 1
        ;;
    "release create")
        tag=$3
        printf '%s\n' draft > "$STATE_DIR/$tag.state"
        : > "$STATE_DIR/$tag.assets"
        i=1
        while [ "$i" -le "$#" ]; do
            eval "arg=\${$i}"
            case "$arg" in
                --draft=false)
                    echo "create published immediately" >&2
                    exit 1
                    ;;
            esac
            i=$((i + 1))
        done
        exit 0
        ;;
    "release edit")
        tag=$3
        draft_false=0
        shift 3
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --draft=false) draft_false=1; shift ;;
                --repo|--notes-file|--title) shift 2 ;;
                *) shift ;;
            esac
        done
        if [ "$draft_false" -eq 1 ]; then
            printf '%s\n' published > "$STATE_DIR/$tag.state"
        fi
        exit 0
        ;;
    "release upload")
        tag=$3
        if [ "${GH_UPLOAD_FAIL:-}" = 1 ]; then
            exit 22
        fi
        shift 3
        : > "$STATE_DIR/$tag.assets"
        for arg in "$@"; do
            case "$arg" in
                --repo|--clobber) continue ;;
                *)
                    if [ -f "$arg" ]; then
                        basename "$arg" >> "$STATE_DIR/$tag.assets"
                    fi
                    ;;
            esac
        done
        exit 0
        ;;
    "release delete-asset")
        exit 0
        ;;
    *)
        printf 'unexpected gh invocation: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "$stub_dir/gh"
}

notes="$WORK_DIR/notes.md"
printf 'notes\n' > "$notes"
arm64="$WORK_DIR/SpotAsk-0.2.1-arm64.dmg"
x86="$WORK_DIR/SpotAsk-0.2.1-x86_64.dmg"
sums="$WORK_DIR/SpotAsk-v0.2.1-SHA256SUMS.txt"
printf 'arm\n' > "$arm64"
printf 'x86\n' > "$x86"
printf 'sums\n' > "$sums"

# New release: draft, upload, then publish
state1="$WORK_DIR/state-new"
path1="$WORK_DIR/bin-new"
install_gh_stub "$path1" "$state1"
PATH="$path1:$PATH" \
    "$PUBLISH" --tag v0.2.1 --repo shiquda/SpotAsk --notes "$notes" -- "$arm64" "$x86" "$sums"
grep -q 'release create v0.2.1 .*--draft' "$state1/commands.log" || fail "new release was not created as a draft"
if awk 'BEGIN{pub=0} /release upload /{if(pub) exit 1} /--draft=false/{pub=1} END{if(!pub) exit 1}' "$state1/commands.log"; then
    :
else
    fail "new release published before upload completed"
fi
test "$(cat "$state1/v0.2.1.state")" = published || fail "new release did not publish after complete upload"
pass "new release stays draft until assets upload"

# Existing draft + upload failure remains draft
state2="$WORK_DIR/state-fail"
path2="$WORK_DIR/bin-fail"
install_gh_stub "$path2" "$state2"
printf '%s\n' draft > "$state2/v0.2.1.state"
: > "$state2/v0.2.1.assets"
if GH_UPLOAD_FAIL=1 PATH="$path2:$PATH" \
    "$PUBLISH" --tag v0.2.1 --repo shiquda/SpotAsk --notes "$notes" -- "$arm64" "$x86" "$sums"
then
    fail "upload failure should fail the publish helper"
fi
test "$(cat "$state2/v0.2.1.state")" = draft || fail "upload failure published the draft"
grep -q -- '--draft=false' "$state2/commands.log" && fail "upload failure still called --draft=false"
pass "upload failure leaves an existing draft unpublished"

# Published release refuses clobber
state3="$WORK_DIR/state-pub"
path3="$WORK_DIR/bin-pub"
install_gh_stub "$path3" "$state3"
printf '%s\n' published > "$state3/v0.2.1.state"
if PATH="$path3:$PATH" \
    "$PUBLISH" --tag v0.2.1 --repo shiquda/SpotAsk --notes "$notes" -- "$arm64" "$x86" "$sums"
then
    fail "published release should refuse replacement"
fi
grep -q 'release upload' "$state3/commands.log" && fail "published release uploaded replacement assets"
grep -q -- '--clobber' "$state3/commands.log" && fail "published release used --clobber"
test "$(cat "$state3/v0.2.1.state")" = published || fail "published release state changed"
pass "published release refuses asset replacement"

# Existing draft success publishes only after upload
state4="$WORK_DIR/state-draft"
path4="$WORK_DIR/bin-draft"
install_gh_stub "$path4" "$state4"
printf '%s\n' draft > "$state4/v0.2.1.state"
: > "$state4/v0.2.1.assets"
PATH="$path4:$PATH" \
    "$PUBLISH" --tag v0.2.1 --repo shiquda/SpotAsk --notes "$notes" -- "$arm64" "$x86" "$sums"
if awk 'BEGIN{pub=0} /release upload /{if(pub) exit 1} /--draft=false/{pub=1} END{if(!pub) exit 1}' "$state4/commands.log"; then
    :
else
    fail "existing draft published before upload completed"
fi
test "$(cat "$state4/v0.2.1.state")" = published || fail "existing draft did not publish after upload"
pass "existing draft publishes only after complete upload"

# --- helper wait is taken from the workflow commit, not the app tag ---
xcrun_dir="$WORK_DIR/xcrun-bin"
mkdir -p "$xcrun_dir"
cat > "$xcrun_dir/xcrun" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${XCRUN_LOG:?}"
if [ "${1-}" = notarytool ] && [ "${2-}" = submit ]; then
    printf '%s\n' '{"id":"stub","status":"Accepted"}'
fi
exit 0
EOF
chmod +x "$xcrun_dir/xcrun"

old_helper="$WORK_DIR/old-notarize-dmg.sh"
cat > "$old_helper" <<'EOF'
#!/bin/sh
set -eu
# v0.2.1 submit path: --wait is ignored
DMG_PATH=${2:?"submit requires a DMG path"}
xcrun notarytool submit "$DMG_PATH" --keychain-profile "${SPOTASK_NOTARY_KEYCHAIN_PROFILE:?}" --no-wait --output-format json
EOF
chmod +x "$old_helper"

XCRUN_LOG="$WORK_DIR/old-xcrun.log"
PATH="$xcrun_dir:$PATH" XCRUN_LOG="$XCRUN_LOG" SPOTASK_NOTARY_KEYCHAIN_PROFILE=review-dummy \
    "$old_helper" submit "$arm64" --wait >/dev/null
grep -q -- '--no-wait' "$XCRUN_LOG" || fail "v0.2.1 helper should ignore --wait"
grep -q -- '--wait' "$XCRUN_LOG" && fail "v0.2.1 helper unexpectedly waited"

XCRUN_LOG="$WORK_DIR/new-xcrun.log"
PATH="$xcrun_dir:$PATH" XCRUN_LOG="$XCRUN_LOG" SPOTASK_NOTARY_KEYCHAIN_PROFILE=review-dummy \
    "$NOTARIZE" submit "$arm64" --wait >/dev/null
grep -q -- '--wait' "$XCRUN_LOG" || fail "current helper did not pass --wait"
grep -q -- '--no-wait' "$XCRUN_LOG" && fail "current helper passed --no-wait"

# Simulate workflow restore: tag tree has the old helper, workflow copies the current one over it
tag_scripts="$WORK_DIR/tag-scripts"
mkdir -p "$tag_scripts"
cp "$old_helper" "$tag_scripts/notarize-dmg.sh"
cp "$NOTARIZE" "$WORK_DIR/workflow-notarize-dmg.sh"
cp "$WORK_DIR/workflow-notarize-dmg.sh" "$tag_scripts/notarize-dmg.sh"
grep -q 'WAIT_FLAG' "$tag_scripts/notarize-dmg.sh" || fail "restored tag helper still lacks WAIT_FLAG"
XCRUN_LOG="$WORK_DIR/restored-xcrun.log"
PATH="$xcrun_dir:$PATH" XCRUN_LOG="$XCRUN_LOG" SPOTASK_NOTARY_KEYCHAIN_PROFILE=review-dummy \
    "$tag_scripts/notarize-dmg.sh" submit "$arm64" --wait >/dev/null
grep -q -- '--wait' "$XCRUN_LOG" || fail "restored helper did not wait"
grep -q -- '--no-wait' "$XCRUN_LOG" && fail "restored helper used --no-wait"
pass "workflow helpers wait even when the app tag has the old notarize script"

# --- Homebrew cask pushes to main with an admin PAT ---
PUSH_CASK="$ROOT_DIR/Scripts/push-homebrew-cask.sh"
if CASK_GITHUB_TOKEN= "$PUSH_CASK" 2>"$WORK_DIR/cask-missing.err"; then
    fail "cask helper accepted an empty token"
fi
grep -q 'CASK_GITHUB_TOKEN is required' "$WORK_DIR/cask-missing.err" || fail "empty token did not fail-fast"
pass "missing CASK_GITHUB_TOKEN fails before push"

cask_origin="$WORK_DIR/cask-origin.git"
cask_work="$WORK_DIR/cask-work"
git init --bare "$cask_origin" >/dev/null
git init -b main "$cask_work" >/dev/null
git -C "$cask_work" config user.name "cask-test"
git -C "$cask_work" config user.email "cask-test@example.com"
mkdir -p "$cask_work/Casks"
printf 'v1\n' > "$cask_work/Casks/spotask.rb"
git -C "$cask_work" add Casks/spotask.rb
git -C "$cask_work" commit -m "cask v1" >/dev/null
git -C "$cask_work" remote add origin "$cask_origin"
(
    cd "$cask_work"
    CASK_GITHUB_TOKEN=test-token "$PUSH_CASK"
) >/dev/null
test "$(git --git-dir="$cask_origin" log -1 --format=%s)" = "cask v1" || fail "cask helper did not push HEAD to origin main"
pass "cask helper pushes HEAD to origin main"

printf 'v2\n' > "$cask_work/Casks/spotask.rb"
git -C "$cask_work" add Casks/spotask.rb
git -C "$cask_work" commit -m "cask v2" >/dev/null
(
    cd "$cask_work"
    CASK_GITHUB_TOKEN=test-token "$PUSH_CASK"
) >/dev/null
test "$(git --git-dir="$cask_origin" log -1 --format=%s)" = "cask v2" || fail "second cask push did not update origin main"
pass "repeat cask push updates origin main without force"

grep -q 'open-homebrew-cask-pr.sh' "$ROOT_DIR/.github/workflows/release.yml" && fail "Release workflow still opens a Homebrew cask PR"
grep -q 'push-homebrew-cask.sh' "$ROOT_DIR/.github/workflows/release.yml" || fail "Release workflow does not call the cask push helper"
grep -q 'secrets.CASK_GITHUB_TOKEN || github.token' "$ROOT_DIR/.github/workflows/release.yml" && fail "CASK_GITHUB_TOKEN still falls back to GITHUB_TOKEN"

# --- script syntax ---
/bin/sh -n "$PUBLISH"
/bin/sh -n "$NOTARIZE"
/bin/sh -n "$PUSH_CASK"
/bin/sh -n "$ROOT_DIR/Scripts/make-release-dmg.sh"
/bin/sh -n "$ROOT_DIR/Scripts/test-release-workflow.sh"
pass "release scripts parse"

printf '%s\n' "All release workflow regressions passed."
