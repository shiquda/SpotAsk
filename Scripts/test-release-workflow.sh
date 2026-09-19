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
test "$(git --git-dir="$cask_origin" log -1 --format=%s refs/heads/main)" = "cask v1" || fail "cask helper did not push HEAD to origin main"
pass "cask helper pushes HEAD to origin main"

printf 'v2\n' > "$cask_work/Casks/spotask.rb"
git -C "$cask_work" add Casks/spotask.rb
git -C "$cask_work" commit -m "cask v2" >/dev/null
(
    cd "$cask_work"
    CASK_GITHUB_TOKEN=test-token "$PUSH_CASK"
) >/dev/null
test "$(git --git-dir="$cask_origin" log -1 --format=%s refs/heads/main)" = "cask v2" || fail "second cask push did not update origin main"
pass "repeat cask push updates origin main without force"

real_git=$(command -v git)
gitbin="$WORK_DIR/gitbin"
mkdir -p "$gitbin"
cat > "$gitbin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$WORK_DIR/cask-git.args"
exec "$real_git" "\$@"
EOF
chmod +x "$gitbin/git"
: > "$WORK_DIR/cask-git.args"
git -C "$cask_work" config http.https://github.com/.extraheader "AUTHORIZATION: basic CHECKOUTTOKEN"
(
    cd "$cask_work"
    PATH="$gitbin:$PATH" CASK_GITHUB_TOKEN=test-token "$PUSH_CASK"
) >/dev/null
test -z "$(git -C "$cask_work" config --get http.https://github.com/.extraheader || true)" || fail "checkout extraheader still set after cask push"
grep -F "http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:test-token' | base64 | tr -d '\r\n')" "$WORK_DIR/cask-git.args" >/dev/null \
    || fail "push did not use URL-scoped PAT extraheader"
grep -F 'AUTHORIZATION: basic CHECKOUTTOKEN' "$WORK_DIR/cask-git.args" >/dev/null \
    && fail "push still passed the checkout extraheader"
pass "cask helper drops checkout credentials and pushes with the PAT"

grep -q 'open-homebrew-cask-pr.sh' "$ROOT_DIR/.github/workflows/release.yml" && fail "Release workflow still opens a Homebrew cask PR"
grep -q 'push-homebrew-cask.sh' "$ROOT_DIR/.github/workflows/release.yml" || fail "Release workflow does not call the cask push helper"
grep -q 'secrets.CASK_GITHUB_TOKEN || github.token' "$ROOT_DIR/.github/workflows/release.yml" && fail "CASK_GITHUB_TOKEN still falls back to GITHUB_TOKEN"
grep -q 'persist-credentials: false' "$ROOT_DIR/.github/workflows/release.yml" || fail "Release checkout still persists GITHUB_TOKEN credentials"


grep -q -- '--deep' "$ROOT_DIR/Scripts/make-app-bundle.sh" && fail "make-app-bundle.sh still uses codesign --deep"
grep -q 'Sparkle.framework' "$ROOT_DIR/Scripts/make-app-bundle.sh" || fail "make-app-bundle.sh does not sign Sparkle.framework"
grep -q 'XPCServices/Downloader.xpc' "$ROOT_DIR/Scripts/make-app-bundle.sh" || fail "make-app-bundle.sh does not sign Downloader.xpc"
grep -q 'appcast-arm64.xml' "$ROOT_DIR/.github/workflows/release.yml" || fail "Release workflow does not publish appcast-arm64.xml"
grep -q 'generate-appcast.sh' "$ROOT_DIR/.github/workflows/release.yml" || fail "Release workflow does not generate Sparkle appcasts"
grep -q 'verify-sparkle-appcast.py' "$ROOT_DIR/.github/workflows/release.yml" || fail "Release workflow does not restore the appcast verifier"
grep -q 'SPARKLE_ALLOW_MISSING_ED_KEY' "$ROOT_DIR/.github/workflows/release.yml" && fail "Release workflow still allows missing EdDSA keys"
grep -q 'SPARKLE_ALLOW_MISSING_ED_KEY' "$ROOT_DIR/Scripts/generate-appcast.sh" && fail "generate-appcast.sh still allows missing EdDSA keys"
grep -q -- '--embed-release-notes' "$ROOT_DIR/Scripts/generate-appcast.sh" || fail "generate-appcast.sh does not embed release notes"
grep -q -- '--notes-zh' "$ROOT_DIR/Scripts/generate-appcast.sh" || fail "generate-appcast.sh does not support --notes-zh"
grep -q 'xml:lang="zh-CN"' "$ROOT_DIR/Scripts/generate-appcast.sh" || fail "generate-appcast.sh does not generate xml:lang=zh-CN"
grep -q 'if \[ -f dist/appcast-arm64.xml \]' "$ROOT_DIR/.github/workflows/release.yml" && fail "Release workflow still treats appcasts as optional assets"
grep -q 'test -n "$SPARKLE_ED_PRIVATE_KEY"' "$ROOT_DIR/.github/workflows/release.yml" || fail "Release workflow does not fail closed without SPARKLE_ED_PRIVATE_KEY"

VERIFY="$ROOT_DIR/Scripts/verify-sparkle-appcast.py"
GENERATE_APPCAST="$ROOT_DIR/Scripts/generate-appcast.sh"
python3 -m py_compile "$VERIFY" || fail "verify-sparkle-appcast.py does not compile"

# --- verifier: signature, public key, and embedded notes ---
python3 - "$WORK_DIR" "$VERIFY" <<'PY' || fail "appcast verifier regressions failed"
import base64, subprocess, sys, tempfile
from pathlib import Path

work = Path(sys.argv[1]) / "verifier"
work.mkdir()
verify = sys.argv[2]
archive = work / "SpotAsk-1.2.3-arm64.zip"
archive.write_bytes(b"spotask-archive-bytes\n" * 64)

pem = work / "priv.pem"
subprocess.check_call(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(pem)])
der = subprocess.check_output(["openssl", "pkey", "-in", str(pem), "-outform", "DER"])
pub_der = subprocess.check_output(["openssl", "pkey", "-in", str(pem), "-pubout", "-outform", "DER"])
pub = pub_der[-32:]
sig_path = work / "sig.bin"
subprocess.check_call(
    ["openssl", "pkeyutl", "-sign", "-inkey", str(pem), "-rawin", "-in", str(archive), "-out", str(sig_path)]
)
sig_b64 = base64.b64encode(sig_path.read_bytes()).decode()
pub_b64 = base64.b64encode(pub).decode()
wrong_b64 = base64.b64encode(bytes(b ^ 0xFF for b in pub)).decode()

def write_xml(path, signature=sig_b64, notes_link=False, description=True):
    notes = ""
    if notes_link:
        notes += '            <sparkle:releaseNotesLink>https://example.test/missing.md</sparkle:releaseNotesLink>\n'
    if description:
        notes += '            <description sparkle:format="markdown"><![CDATA[# Dummy 1.2.3\n\nUnique notes token ALPHA-NOTES\n]]></description>\n'
    enclosure = '            <enclosure url="https://example.test/SpotAsk-1.2.3-arm64.zip" length="10" type="application/octet-stream"'
    if signature:
        enclosure += f' sparkle:edSignature="{signature}"'
    enclosure += "/>"
    path.write_text(
        '<?xml version="1.0" standalone="yes"?>\n'
        '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
        "    <channel>\n        <item>\n            <title>1.2.3</title>\n"
        f"{notes}{enclosure}\n        </item>\n    </channel>\n</rss>\n"
    )

good = work / "good.xml"
write_xml(good)
subprocess.check_call(
    ["python3", verify, "--xml", str(good), "--archive", str(archive), "--public-key", pub_b64, "--notes-token", "ALPHA-NOTES"]
)

missing_sig = work / "missing-sig.xml"
write_xml(missing_sig, signature="")
r = subprocess.run(
    ["python3", verify, "--xml", str(missing_sig), "--archive", str(archive), "--public-key", pub_b64],
    capture_output=True,
    text=True,
)
assert r.returncode != 0, "missing signature was accepted"
assert "edSignature" in r.stderr

linked = work / "notes-link.xml"
write_xml(linked, notes_link=True)
r = subprocess.run(
    ["python3", verify, "--xml", str(linked), "--archive", str(archive), "--public-key", pub_b64, "--notes-token", "ALPHA-NOTES"],
    capture_output=True,
    text=True,
)
assert r.returncode != 0, "releaseNotesLink was accepted"
assert "releaseNotesLink" in r.stderr

mismatch = work / "mismatch.xml"
write_xml(mismatch)
r = subprocess.run(
    ["python3", verify, "--xml", str(mismatch), "--archive", str(archive), "--public-key", wrong_b64],
    capture_output=True,
    text=True,
)
assert r.returncode != 0, "mismatched SUPublicEDKey was accepted"
bilingual_good = work / "bilingual-good.xml"
bilingual_good.write_text(
    '<?xml version="1.0" standalone="yes"?>\n'
    '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
    '    <channel>\n        <item>\n            <title>1.2.3</title>\n'
    '            <description sparkle:format="markdown" xml:lang="en"><![CDATA[# Dummy 1.2.3\n\nUnique notes token ALPHA-NOTES\n]]></description>\n'
    '            <description sparkle:format="markdown" xml:lang="zh-CN"><![CDATA[# Dummy 1.2.3\n\nUnique notes token ZH-NOTES\n]]></description>\n'
    f'            <enclosure url="https://example.test/SpotAsk-1.2.3-arm64.zip" length="10" type="application/octet-stream" sparkle:edSignature="{sig_b64}"/>\n'
    '        </item>\n    </channel>\n</rss>\n'
)
subprocess.check_call(
    ["python3", verify, "--xml", str(bilingual_good), "--archive", str(archive), "--public-key", pub_b64, "--notes-token", "ALPHA-NOTES", "--notes-zh-token", "ZH-NOTES"]
)

bilingual_missing_zh = work / "bilingual-missing-zh.xml"
bilingual_missing_zh.write_text(
    '<?xml version="1.0" standalone="yes"?>\n'
    '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
    '    <channel>\n        <item>\n            <title>1.2.3</title>\n'
    '            <description sparkle:format="markdown" xml:lang="en"><![CDATA[# Dummy 1.2.3\n\nUnique notes token ALPHA-NOTES\n]]></description>\n'
    f'            <enclosure url="https://example.test/SpotAsk-1.2.3-arm64.zip" length="10" type="application/octet-stream" sparkle:edSignature="{sig_b64}"/>\n'
    '        </item>\n    </channel>\n</rss>\n'
)
r = subprocess.run(
    ["python3", verify, "--xml", str(bilingual_missing_zh), "--archive", str(archive), "--public-key", pub_b64, "--notes-token", "ALPHA-NOTES", "--notes-zh-token", "ZH-NOTES"],
    capture_output=True,
    text=True,
)
assert r.returncode != 0, "missing zh description was accepted"
assert 'xml:lang="zh-CN"' in r.stderr

bilingual_missing_lang = work / "bilingual-missing-lang.xml"
bilingual_missing_lang.write_text(
    '<?xml version="1.0" standalone="yes"?>\n'
    '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
    '    <channel>\n        <item>\n            <title>1.2.3</title>\n'
    '            <description sparkle:format="markdown"><![CDATA[# Dummy 1.2.3\n\nUnique notes token ALPHA-NOTES\n]]></description>\n'
    '            <description sparkle:format="markdown" xml:lang="zh-CN"><![CDATA[# Dummy 1.2.3\n\nUnique notes token ZH-NOTES\n]]></description>\n'
    f'            <enclosure url="https://example.test/SpotAsk-1.2.3-arm64.zip" length="10" type="application/octet-stream" sparkle:edSignature="{sig_b64}"/>\n'
    '        </item>\n    </channel>\n</rss>\n'
)
r = subprocess.run(
    ["python3", verify, "--xml", str(bilingual_missing_lang), "--archive", str(archive), "--public-key", pub_b64, "--notes-token", "ALPHA-NOTES", "--notes-zh-token", "ZH-NOTES"],
    capture_output=True,
    text=True,
)
assert r.returncode != 0, "description lacking xml:lang was accepted"
assert "lacks xml:lang" in r.stderr

print("verifier cases ok")
PY
pass "appcast verifier rejects missing signatures, notes links, and key mismatch"

# --- generate-appcast fail-closed without a key ---
notes="$WORK_DIR/appcast-notes.md"
printf '# Dummy 1.2.3\n\nUnique notes token ALPHA-NOTES\n' > "$notes"
dummy_arm="$WORK_DIR/SpotAsk-1.2.3-arm64.zip"
dummy_x86="$WORK_DIR/SpotAsk-1.2.3-x86_64.zip"
printf 'arm-archive\n' > "$dummy_arm"
printf 'x86-archive\n' > "$dummy_x86"
if SPARKLE_ED_PRIVATE_KEY= SPARKLE_ED_PRIVATE_KEY_FILE= \
    "$GENERATE_APPCAST" \
    --version 1.2.3 \
    --tag v1.2.3 \
    --arm64-dmg "$dummy_arm" \
    --x86_64-dmg "$dummy_x86" \
    --notes "$notes" \
    --output "$WORK_DIR/appcast-missing-key" \
    --download-url-prefix "https://example.test/" \
    2>"$WORK_DIR/missing-key.err"; then
    fail "generate-appcast succeeded without an EdDSA key"
fi
grep -q 'SPARKLE_ED_PRIVATE_KEY or SPARKLE_ED_PRIVATE_KEY_FILE is required' "$WORK_DIR/missing-key.err" \
    || fail "missing key did not fail closed"
pass "generate-appcast fails closed without an EdDSA key"

# --- generate_appcast embeds notes and signs against the public key ---
python3 - "$WORK_DIR" "$ROOT_DIR" <<'PY' || fail "signed embedded appcast generation failed"
import base64, os, plistlib, subprocess, sys
from pathlib import Path

work = Path(sys.argv[1]) / "signed-appcast"
root = Path(sys.argv[2])
work.mkdir()
def locate_or_fetch_generate_appcast(root_path: Path) -> Path:
    env_dir = os.environ.get("SPARKLE_TOOLS_DIR")
    if env_dir:
        candidate = Path(env_dir) / "generate_appcast"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate

    spm_bin = root_path / ".build" / "artifacts" / "sparkle" / "Sparkle" / "bin" / "generate_appcast"
    if spm_bin.is_file() and os.access(spm_bin, os.X_OK):
        return spm_bin

    tools_cache = root_path / ".build" / "sparkle-tools-2.9.6"
    cached_bin = tools_cache / "bin" / "generate_appcast"
    if cached_bin.is_file() and os.access(cached_bin, os.X_OK):
        return cached_bin

    tools_cache.mkdir(parents=True, exist_ok=True)
    zip_path = tools_cache / "Sparkle-for-Swift-Package-Manager.zip"
    url = "https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip"
    subprocess.check_call(["curl", "-fsSL", url, "-o", str(zip_path)])
    subprocess.check_call(["unzip", "-qo", str(zip_path), "-d", str(tools_cache)])
    if cached_bin.is_file() and os.access(cached_bin, os.X_OK):
        return cached_bin

    raise RuntimeError(f"Unable to locate or fetch Sparkle generate_appcast into {tools_cache}")

tools_bin = locate_or_fetch_generate_appcast(root)

pem = work / "priv.pem"
subprocess.check_call(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(pem)])
der = subprocess.check_output(["openssl", "pkey", "-in", str(pem), "-outform", "DER"])
pub = subprocess.check_output(["openssl", "pkey", "-in", str(pem), "-pubout", "-outform", "DER"])[-32:]
idx = der.find(b"\x04\x20")
seed = der[idx + 2:idx + 34]
pub_b64 = base64.b64encode(pub).decode()
key_file = work / "eddsa_priv.key"
key_file.write_text(base64.b64encode(seed).decode() + "\n")
key_file.chmod(0o600)

app = work / "Dummy.app"
macos = app / "Contents" / "MacOS"
macos.mkdir(parents=True)
subprocess.check_call(["cp", "/usr/bin/true", str(macos / "Dummy")])
plist = {
    "CFBundleExecutable": "Dummy",
    "CFBundleIdentifier": "com.example.dummy",
    "CFBundleName": "Dummy",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "1.2.3",
    "CFBundleVersion": "123",
    "LSMinimumSystemVersion": "15.0",
    "SUPublicEDKey": pub_b64,
}
(app / "Contents" / "Info.plist").write_bytes(plistlib.dumps(plist))
subprocess.check_call(["codesign", "--force", "--sign", "-", str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

arm = work / "SpotAsk-1.2.3-arm64.zip"
x86 = work / "SpotAsk-1.2.3-x86_64.zip"
subprocess.check_call(["ditto", "-c", "-k", "--keepParent", str(app), str(arm)])
subprocess.check_call(["ditto", "-c", "-k", "--keepParent", str(app), str(x86)])
notes = work / "notes.md"
notes.write_text("# Dummy 1.2.3\n\nUnique notes token ALPHA-NOTES\n")
notes_zh = work / "notes.zh-CN.md"
notes_zh.write_text("# Dummy 1.2.3\n\nUnique notes token ZH-NOTES\n")

env = os.environ.copy()
env["SPARKLE_TOOLS_DIR"] = str(tools_bin.parent)
env["SPARKLE_ED_PRIVATE_KEY_FILE"] = str(key_file)
env.pop("SPARKLE_ED_PRIVATE_KEY", None)
out = work / "out"
subprocess.check_call(
    [
        str(root / "Scripts" / "generate-appcast.sh"),
        "--version", "1.2.3",
        "--tag", "v1.2.3",
        "--arm64-dmg", str(arm),
        "--x86_64-dmg", str(x86),
        "--notes", str(notes),
        "--notes-zh", str(notes_zh),
        "--output", str(out),
        "--download-url-prefix", "https://example.test/v1.2.3/",
        "--public-key", pub_b64,
    ],
    env=env,
)

for name in ("appcast-arm64.xml", "appcast-x86_64.xml"):
    xml = (out / name).read_text()
    assert "sparkle:edSignature=" in xml, name
    assert "releaseNotesLink" not in xml, name
    assert "ALPHA-NOTES" in xml, name
    assert "ZH-NOTES" in xml, name
    assert 'xml:lang="en"' in xml, name
    assert 'xml:lang="zh-CN"' in xml, name
    assert 'sparkle:format="markdown"' in xml, name
    assert "<description" in xml, name

subprocess.check_call(
    [
        "python3",
        str(root / "Scripts" / "verify-sparkle-appcast.py"),
        "--xml", str(out / "appcast-arm64.xml"),
        "--archive", str(arm),
        "--public-key", pub_b64,
        "--notes-token", "ALPHA-NOTES",
        "--notes-zh-token", "ZH-NOTES",
    ]
)
wrong_zh = subprocess.run(
    [
        "python3",
        str(root / "Scripts" / "verify-sparkle-appcast.py"),
        "--xml", str(out / "appcast-arm64.xml"),
        "--archive", str(arm),
        "--public-key", pub_b64,
        "--notes-token", "ALPHA-NOTES",
        "--notes-zh-token", "NONEXISTENT-ZH-TOKEN",
    ],
    capture_output=True,
    text=True,
)
assert wrong_zh.returncode != 0, "wrong zh notes token was accepted"
assert "NONEXISTENT-ZH-TOKEN" in wrong_zh.stderr

out_fallback = work / "out_fallback"
subprocess.check_call(
    [
        str(root / "Scripts" / "generate-appcast.sh"),
        "--version", "1.2.3",
        "--tag", "v1.2.3",
        "--arm64-dmg", str(arm),
        "--x86_64-dmg", str(x86),
        "--notes", str(notes),
        "--output", str(out_fallback),
        "--download-url-prefix", "https://example.test/v1.2.3/",
        "--public-key", pub_b64,
    ],
    env=env,
)
for name in ("appcast-arm64.xml", "appcast-x86_64.xml"):
    xml_fb = (out_fallback / name).read_text()
    assert 'xml:lang="en"' in xml_fb, name
    assert 'xml:lang="zh-CN"' in xml_fb, name
    assert "ZH-NOTES" in xml_fb, name

standalone_notes = work / "standalone.md"
standalone_notes.write_text("# Standalone 1.2.3\n\nStandalone token SOLO-NOTES\n")
out_solo = work / "out_solo"
subprocess.check_call(
    [
        str(root / "Scripts" / "generate-appcast.sh"),
        "--version", "1.2.3",
        "--tag", "v1.2.3",
        "--arm64-dmg", str(arm),
        "--x86_64-dmg", str(x86),
        "--notes", str(standalone_notes),
        "--output", str(out_solo),
        "--download-url-prefix", "https://example.test/v1.2.3/",
        "--public-key", pub_b64,
    ],
    env=env,
)
xml_solo = (out_solo / "appcast-arm64.xml").read_text()
assert 'xml:lang="en"' in xml_solo
assert 'xml:lang="zh-CN"' in xml_solo
assert "SOLO-NOTES" in xml_solo


wrong = base64.b64encode(bytes(b ^ 0xFF for b in pub)).decode()
r = subprocess.run(
    [
        "python3",
        str(root / "Scripts" / "verify-sparkle-appcast.py"),
        "--xml", str(out / "appcast-arm64.xml"),
        "--archive", str(arm),
        "--public-key", wrong,
    ],
    capture_output=True,
    text=True,
)
assert r.returncode != 0, "generated appcast verified against the wrong public key"
print("signed embedded appcasts ok")
PY
pass "generate-appcast embeds notes and verifies sparkle:edSignature against the public key"

# --- script syntax ---
/bin/sh -n "$PUBLISH"
/bin/sh -n "$NOTARIZE"
/bin/sh -n "$PUSH_CASK"
/bin/sh -n "$ROOT_DIR/Scripts/make-release-dmg.sh"
/bin/sh -n "$ROOT_DIR/Scripts/make-app-bundle.sh"
/bin/sh -n "$ROOT_DIR/Scripts/generate-appcast.sh"
/bin/sh -n "$ROOT_DIR/Scripts/generate-sparkle-keys.sh"
/bin/sh -n "$ROOT_DIR/Scripts/test-release-workflow.sh"
pass "release scripts parse"

printf '%s\n' "All release workflow regressions passed."
