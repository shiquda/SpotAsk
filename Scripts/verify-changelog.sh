#!/bin/sh
# Assert that CHANGELOG.md and CHANGELOG.zh-CN.md describe exactly the same
# releases.
#
# Both files feed the documentation site's changelog pages and the GitHub
# Release notes, so a version that exists in only one language, a heading whose
# date does not parse, or a version without a link reference renders broken or
# half-translated on a published page. This script is a required CI gate.
#
# Usage: Scripts/verify-changelog.sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EN_FILE="$ROOT_DIR/CHANGELOG.md"
ZH_FILE="$ROOT_DIR/CHANGELOG.zh-CN.md"

usage() {
    printf 'Usage: %s\n' "$0" >&2
    printf '%s\n' \
        'Checks that CHANGELOG.md and CHANGELOG.zh-CN.md stay in lockstep:' \
        '  - the same version sections in the same order, newest first' \
        '  - `[Unreleased]` first and dateless' \
        '  - a valid ` - YYYY-MM-DD` date on every released section, identical in both files' \
        '  - the same `### subsection` headings and bullet counts per version' \
        '  - a link reference for every version, with the same labels in both files' >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
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

for file in "$EN_FILE" "$ZH_FILE"; do
    if [ ! -s "$file" ]; then
        printf 'FAIL: %s is missing or empty\n' "${file#"$ROOT_DIR"/}" >&2
        exit 1
    fi
done

awk -v en_name='CHANGELOG.md' -v zh_name='CHANGELOG.zh-CN.md' '
function report(msg) {
    printf "FAIL: %s\n", msg > "/dev/stderr"
    problems++
}

function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}

function days_in_month(y, m) {
    if (m == 2) return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
    if (m == 4 || m == 6 || m == 9 || m == 11) return 30
    return 31
}

# "" when the date is a real calendar date, otherwise why it is not.
function date_problem(d,   y, m, day) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return "release date `" d "` is not YYYY-MM-DD"
    y = substr(d, 1, 4) + 0
    m = substr(d, 6, 2) + 0
    day = substr(d, 9, 2) + 0
    if (y < 2000 || y > 2100) return "release date `" d "` is outside 2000-2100"
    if (m < 1 || m > 12) return "release date `" d "` has an invalid month"
    if (day < 1 || day > days_in_month(y, m)) return "release date `" d "` has an invalid day"
    return ""
}

function valid_label(l) {
    if (l == "Unreleased") return 1
    return (l ~ /^[0-9]+\.[0-9]+\.[0-9]+$/)
}

# 1 when a > b, -1 when a < b, 0 when equal.
function version_cmp(a, b,   xa, xb, i) {
    split(a, xa, ".")
    split(b, xb, ".")
    for (i = 1; i <= 3; i++) {
        if (xa[i] + 0 > xb[i] + 0) return 1
        if (xa[i] + 0 < xb[i] + 0) return -1
    }
    return 0
}

function has_key(arr, f, k) { return ((f SUBSEP k) in arr) }

function open_section(file, label, date,   i) {
    i = nsec[file] + 1
    nsec[file] = i
    label_of[file, i] = label
    date_of[file, i] = date
    section_index[file, label] = i
    cur_sec[file] = i
    cur_sub[file] = ""
}

BEGIN {
    name[1] = en_name
    name[2] = zh_name
}

FNR == 1 { f++ }

f <= 2 {
    line = $0

    # "## [label]" or "## [label] - YYYY-MM-DD"
    if (line ~ /^## \[/) {
        rest = line
        sub(/^## \[/, "", rest)
        close_at = index(rest, "]")
        if (close_at == 0) {
            report(sprintf("%s:%d: malformed version heading `%s`", name[f], FNR, line))
            cur_sec[f] = 0
            next
        }
        label = substr(rest, 1, close_at - 1)
        tail = trim(substr(rest, close_at + 1))
        date = ""
        if (tail != "") {
            if (substr(tail, 1, 2) == "- ") date = trim(substr(tail, 3))
            else report(sprintf("%s:%d: unexpected text after `[%s]`: `%s`", name[f], FNR, label, tail))
        }
        if (!valid_label(label)) {
            report(sprintf("%s:%d: `[%s]` is neither `Unreleased` nor `MAJOR.MINOR.PATCH`", name[f], FNR, label))
        }
        if (has_key(section_index, f, label)) {
            report(sprintf("%s: `## [%s]` is defined twice", name[f], label))
            cur_sec[f] = 0
            next
        }
        open_section(f, label, date)
        next
    }

    if (line ~ /^### /) {
        sub_name = trim(substr(line, 5))
        i = cur_sec[f]
        if (i == 0) {
            report(sprintf("%s:%d: `### %s` appears before any `## [version]` section", name[f], FNR, sub_name))
            next
        }
        if (has_key(sub_index, f, i SUBSEP sub_name)) {
            report(sprintf("%s: `[%s]` repeats the `### %s` subsection", name[f], label_of[f, i], sub_name))
            next
        }
        nsub[f, i]++
        sub_of[f, i, nsub[f, i]] = sub_name
        sub_index[f, i SUBSEP sub_name] = 1
        cur_sub[f] = sub_name
        next
    }

    if (line ~ /^- /) {
        i = cur_sec[f]
        if (i > 0) bullets[f, i, cur_sub[f]]++
        next
    }

    if (line ~ /^\[[^]]+\]:/) {
        ref_label = line
        sub(/^\[/, "", ref_label)
        sub(/\]:.*$/, "", ref_label)
        if (has_key(ref_index, f, ref_label)) {
            report(sprintf("%s: link reference `[%s]` is defined twice", name[f], ref_label))
            next
        }
        ref_index[f, ref_label] = 1
        nref[f]++
        ref_of[f, nref[f]] = ref_label
        next
    }
}

END {
    for (file = 1; file <= 2; file++) {
        if (nsec[file] == 0) {
            report(sprintf("%s has no `## [version]` sections", name[file]))
        }
    }

    # Same version sections per file, named individually so the message says which file.
    for (i = 1; i <= nsec[1]; i++) {
        label = label_of[1, i]
        if (!has_key(section_index, 2, label)) {
            report(sprintf("`[%s]` is missing from %s", label, zh_name))
        }
    }
    for (i = 1; i <= nsec[2]; i++) {
        label = label_of[2, i]
        if (!has_key(section_index, 1, label)) {
            report(sprintf("`[%s]` is missing from %s", label, en_name))
        }
    }

    # Newest first, strictly descending, dates non-increasing as versions descend.
    for (file = 1; file <= 2; file++) {
        if (nsec[file] > 0 && label_of[file, 1] != "Unreleased") {
            report(sprintf("%s: the newest section must be `## [Unreleased]`, found `## [%s]`", name[file], label_of[file, 1]))
        }
        for (i = 2; i <= nsec[file]; i++) {
            prev = label_of[file, i - 1]
            cur = label_of[file, i]
            if (prev == "Unreleased" || cur == "Unreleased") continue
            cmp = version_cmp(prev, cur)
            if (cmp == 0) {
                report(sprintf("%s: `[%s]` follows `[%s]`", name[file], cur, prev))
            } else if (cmp < 0) {
                report(sprintf("%s: `[%s]` must be listed before `[%s]` (newest first)", name[file], cur, prev))
            } else if (date_of[file, i] != "" && date_of[file, i - 1] != "" && date_of[file, i] > date_of[file, i - 1]) {
                report(sprintf("%s: `[%s]` is dated %s and comes before `[%s]` dated %s", name[file], prev, date_of[file, i - 1], cur, date_of[file, i]))
            }
        }
    }

    # Dates: present and valid exactly once per released section.
    for (file = 1; file <= 2; file++) {
        for (i = 1; i <= nsec[file]; i++) {
            label = label_of[file, i]
            date = date_of[file, i]
            if (label == "Unreleased") {
                if (date != "") report(sprintf("%s: `[Unreleased]` must not carry a release date (found `%s`)", name[file], date))
            } else if (date == "") {
                report(sprintf("%s: `[%s]` has no ` - YYYY-MM-DD` release date", name[file], label))
            } else {
                why = date_problem(date)
                if (why != "") report(sprintf("%s: `[%s]` %s", name[file], label, why))
            }
        }
    }

    # Dates and subsection structure must match across the two files.
    for (i = 1; i <= nsec[1]; i++) {
        label = label_of[1, i]
        if (!has_key(section_index, 2, label)) continue
        j = section_index[2, label]

        if (date_of[1, i] != date_of[2, j]) {
            report(sprintf("`[%s]` is dated `%s` in %s but `%s` in %s", label,
                (date_of[1, i] == "" ? "(none)" : date_of[1, i]), en_name,
                (date_of[2, j] == "" ? "(none)" : date_of[2, j]), zh_name))
        }

        if (nsub[1, i] != nsub[2, j]) {
            report(sprintf("`[%s]` has %d `### ` subsections in %s but %d in %s", label, nsub[1, i], en_name, nsub[2, j], zh_name))
        }
        shared = (nsub[1, i] < nsub[2, j] ? nsub[1, i] : nsub[2, j])
        for (k = 1; k <= shared; k++) {
            if (sub_of[1, i, k] != sub_of[2, j, k]) {
                report(sprintf("`[%s]` subsection %d is `### %s` in %s but `### %s` in %s", label, k,
                    sub_of[1, i, k], en_name, sub_of[2, j, k], zh_name))
            }
        }

        # A translation that drops or adds an entry is the drift this gate exists for.
        for (k = 0; k <= nsub[1, i]; k++) {
            sub_name = (k == 0 ? "" : sub_of[1, i, k])
            if (k > 0 && !has_key(sub_index, 2, j SUBSEP sub_name)) continue
            en_bullets = bullets[1, i, sub_name] + 0
            zh_bullets = bullets[2, j, sub_name] + 0
            if (en_bullets != zh_bullets) {
                where = (sub_name == "" ? "`[%s]`" : sprintf("`[%s]` / `### %s`", label, sub_name))
                report(sprintf("%s has %d bullets in %s but %d in %s", where, en_bullets, en_name, zh_bullets, zh_name))
            }
        }
    }

    # Every version heading needs its link reference, or it renders as literal text.
    for (file = 1; file <= 2; file++) {
        for (i = 1; i <= nsec[file]; i++) {
            label = label_of[file, i]
            if (!has_key(ref_index, file, label)) {
                report(sprintf("%s: `## [%s]` has no `[%s]: ...` link reference", name[file], label, label))
            }
        }
    }
    for (k = 1; k <= nref[1]; k++) {
        label = ref_of[1, k]
        if (!has_key(ref_index, 2, label)) {
            report(sprintf("link reference `[%s]` exists in %s but not in %s", label, en_name, zh_name))
        }
    }
    for (k = 1; k <= nref[2]; k++) {
        label = ref_of[2, k]
        if (!has_key(ref_index, 1, label)) {
            report(sprintf("link reference `[%s]` exists in %s but not in %s", label, zh_name, en_name))
        }
    }

    if (problems == 0) {
        newest = (nsec[1] >= 2 ? sprintf("newest %s (%s)", label_of[1, 2], date_of[1, 2]) : "no released section yet")
        printf "verify-changelog: %s and %s are aligned — %d unreleased + %d released sections, %s.\n", \
            en_name, zh_name, (nsec[1] >= 1 ? 1 : 0), (nsec[1] >= 1 ? nsec[1] - 1 : 0), newest
    } else {
        printf "%d changelog problem(s) in %s / %s\n", problems, en_name, zh_name > "/dev/stderr"
    }
    exit (problems ? 1 : 0)
}
' "$EN_FILE" "$ZH_FILE"
