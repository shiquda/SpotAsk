#!/bin/sh
# Audit the commits that landed since the last release tag against the pending
# changelog section, so a missing entry is a visible line instead of a silent
# omission.
#
# Report-only: it never edits the changelog and never fails a build. It prints a
# Markdown checklist for the release reviewer, listing every commit whose subject
# shares no keyword with the section (needs a human look) and every commit that
# looks recorded already.
#
# Usage: Scripts/audit-changelog-diff.sh [--base <ref>] [--section <label>]
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHANGELOG="$ROOT_DIR/CHANGELOG.md"

usage() {
    printf 'Usage: %s [--base <ref>] [--section <label>]\n' "$0" >&2
    printf '%s\n' \
        '  --base <ref>      audit `<ref>..HEAD` (default: the newest `vX.Y.Z` tag reachable from HEAD)' \
        '  --section <label> changelog section to audit against, e.g. `Unreleased` or `0.2.4`' \
        '                    (default: `Unreleased`); read from CHANGELOG.md' \
        '' \
        'Prints a Markdown report and always exits 0. Exit 2 means the range or' \
        'the changelog section could not be resolved. Only `chore` / `docs` / `ci` /' \
        '`test` / `build` / `style` / `release` commits and changes limited to' \
        'documentation, tests, or CI files are skipped; every skip states its reason.' \
        'See DEVELOPMENT.md for the release audit SOP.' >&2
}

BASE=
SECTION=Unreleased

while [ "$#" -gt 0 ]; do
    case "$1" in
        --base)
            if [ "$#" -lt 2 ]; then
                printf 'Missing value for --base\n' >&2
                usage
                exit 2
            fi
            BASE=$2
            shift 2
            ;;
        --section)
            if [ "$#" -lt 2 ]; then
                printf 'Missing value for --section\n' >&2
                usage
                exit 2
            fi
            SECTION=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

# Accept `unreleased`, `X.Y.Z`, and `vX.Y.Z`.
case "$SECTION" in
    [Uu]nreleased) SECTION=Unreleased ;;
    v*) SECTION=${SECTION#v} ;;
esac

if ! command -v git >/dev/null 2>&1; then
    printf 'audit-changelog-diff: git is not available\n' >&2
    exit 2
fi

cd "$ROOT_DIR"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'audit-changelog-diff: %s is not a git checkout\n' "$ROOT_DIR" >&2
    exit 2
fi

if [ ! -f "$CHANGELOG" ]; then
    printf 'audit-changelog-diff: %s is missing\n' "$CHANGELOG" >&2
    exit 2
fi

if [ -z "$BASE" ]; then
    if ! BASE=$(git describe --tags --abbrev=0 --match 'v*' HEAD 2>/dev/null); then
        printf 'audit-changelog-diff: no `vX.Y.Z` tag is reachable from HEAD; pass --base <ref>\n' >&2
        exit 2
    fi
fi

if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    printf 'audit-changelog-diff: unknown base ref `%s`\n' "$BASE" >&2
    exit 2
fi

# Same section shape the release notes extractor reads, so the audit and the
# published release notes never disagree about where a section ends.
if ! SECTION_BODY=$(awk -v version="$SECTION" '
    $0 ~ "^## \\[" version "\\]" { found = 1; next }
    found && /^## / { exit }
    found && /^\[[^]]*\]:/ { exit }
    found { print }
    END { if (!found) exit 1 }
' "$CHANGELOG"); then
    printf 'audit-changelog-diff: CHANGELOG.md has no `## [%s]` section\n' "$SECTION" >&2
    exit 2
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spotask-changelog-audit.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
printf '%s\n' "$SECTION_BODY" > "$WORK_DIR/section.md"

TOTAL=$(git rev-list --no-merges --count "$BASE..HEAD")
DIFFSTAT=$(git diff --stat "$BASE..HEAD") || DIFFSTAT=

printf '# Changelog audit — `[%s]`\n\n' "$SECTION"
printf '%s\n' "- Range: \`$BASE..HEAD\` — $TOTAL commit(s)"
printf '%s\n' "- Section: \`[$SECTION]\` in \`CHANGELOG.md\`"
printf '%s\n' '- Skipped as not changelog-relevant: `chore` / `docs` / `ci` / `test` / `build` / `style` / `release` commits, and changes limited to documentation, tests, or CI files'
printf '\n'

printf '## Diff stat\n\n```\n'
if [ -n "$DIFFSTAT" ]; then
    printf '%s\n' "$DIFFSTAT"
else
    printf '(no changes)\n'
fi
printf '```\n\n'

git log --no-merges --name-only --format='COMMIT%x09%h%x09%s' "$BASE..HEAD" | awk \
    -v section="$SECTION" -v base="$BASE" '
function file_list(   i, n, s) {
    s = ""
    n = (ncur > 6 ? 6 : ncur)
    for (i = 1; i <= n; i++) s = s (i > 1 ? ", " : "") "`" cur_files[i] "`"
    if (ncur > n) s = s sprintf(", … %d more", ncur - n)
    return (s == "" ? "(no files)" : s)
}

function classify(   head, type, desc, i, f, only_docs, line, nw, words, k, w, matched, nmatched, note) {
    type = "unknown"
    desc = cur_subject
    if (match(cur_subject, /^[a-z]+(\([^)]*\))?!?: /)) {
        head = substr(cur_subject, 1, RLENGTH)
        desc = substr(cur_subject, RLENGTH + 1)
        type = head
        sub(/[(!:].*$/, "", type)
    }

    only_docs = (ncur > 0)
    for (i = 1; i <= ncur; i++) {
        f = cur_files[i]
        if (!(f ~ /^docs\// || f ~ /^Tests\// || f ~ /^\.github\// || f ~ /\.md$/)) only_docs = 0
    }

    # Only provably non-user-visible work is skipped, and every skip states why,
    # so an unusual commit type or an odd path can never hide a missing entry.
    if (ncur == 0) {
        other[++nother] = sprintf("- `%s` %s — the commit changes no file", cur_hash, cur_subject)
        return
    }
    if (type in excluded_type) {
        other[++nother] = sprintf("- `%s` %s — `%s:` commits are not changelog-relevant", cur_hash, cur_subject, type)
        return
    }
    if (only_docs) {
        other[++nother] = sprintf("- `%s` %s — only touches documentation, tests, or CI files", cur_hash, cur_subject)
        return
    }

    line = tolower(desc)
    gsub(/[^a-z0-9]+/, " ", line)
    nw = split(line, words, " ")
    matched = ""
    nmatched = 0
    for (k = 1; k <= nw; k++) {
        w = words[k]
        if (length(w) < 4) continue
        if (w in stopword) continue
        if ((cur_hash SUBSEP w) in seen_word) continue
        seen_word[cur_hash SUBSEP w] = 1
        if (index(corpus, " " w " ") > 0) {
            matched = matched (nmatched ? ", " : "") "`" w "`"
            nmatched++
        }
    }

    if (nmatched > 0) {
        maybe[++nmaybe] = sprintf("- [x] `%s` %s\n  - files: %s\n  - matches `[%s]`: %s", cur_hash, cur_subject, file_list(), section, matched)
    } else {
        note = (type == "unknown" ? " (no conventional commit prefix)" : "")
        needs[++nneeds] = sprintf("- [ ] `%s` %s\n  - files: %s\n  - no subject keyword found in `[%s]`%s", cur_hash, cur_subject, file_list(), section, note)
    }
}

function print_group(title, count, items,   i) {
    printf "## %s (%d)\n\n", title, count
    if (count == 0) {
        print "None."
    } else {
        for (i = 1; i <= count; i++) print items[i]
    }
    print ""
}

BEGIN {
    split("chore docs ci test tests build style release", excluded_types, " ")
    for (i in excluded_types) excluded_type[excluded_types[i]] = 1

    split("also more most when with from into that this than then they them their have has been will would should could does done make makes made only just over after before while still each same back both some such there where which what your onto upon using used", filler, " ")
    for (i in filler) stopword[filler[i]] = 1

    corpus = " "
}

FNR == NR {
    if ($0 ~ /^### /) next
    line = tolower($0)
    gsub(/[^a-z0-9]+/, " ", line)
    corpus = corpus line " "
    next
}

{
    if (substr($0, 1, 6) == "COMMIT" && substr($0, 7, 1) == "\t") {
        if (pending) classify()
        rest = substr($0, 8)
        cut = index(rest, "\t")
        if (cut == 0) { cur_hash = rest; cur_subject = "" }
        else { cur_hash = substr(rest, 1, cut - 1); cur_subject = substr(rest, cut + 1) }
        ncur = 0
        pending = 1
        next
    }
    if ($0 == "") next
    if (pending) cur_files[++ncur] = $0
}

END {
    if (pending) classify()

    if (!pending) {
        printf "No commits in `%s..HEAD`.\n", base
        exit 0
    }

    print_group("Needs review — no matching bullet found", nneeds, needs)
    print_group("Possibly recorded — overlapping keywords", nmaybe, maybe)
    print_group("Not changelog-relevant", nother, other)

    printf "%d candidate commit(s): %d need review, %d possibly recorded; %d skipped as not changelog-relevant.\n", \
        nneeds + nmaybe, nneeds, nmaybe, nother
}
' "$WORK_DIR/section.md" -
