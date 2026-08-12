#!/usr/bin/env python3
"""Local diagnostic for missing SpotAsk localization keys.

This is intentionally not wired into CI. It checks Swift L10n.string calls
against Localizable.strings and verifies every language table matches English.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "Sources" / "SpotAsk"
RESOURCES_DIR = SOURCE_DIR / "Resources"

STRING_ENTRY = re.compile(
    r'^\s*"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;',
    re.MULTILINE,
)
L10N_CALL = re.compile(r'\bL10n\.string\(\s*"(?P<key>(?:[^"\\]|\\.)*)"')


def parse_strings(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    content = path.read_text(encoding="utf-8")
    for match in STRING_ENTRY.finditer(content):
        key = match.group("key")
        if key in entries:
            print(f"warning: duplicate key {key!r} in {path.relative_to(ROOT)}", file=sys.stderr)
        entries[key] = match.group("value")
    return entries


def collect_l10n_calls() -> dict[str, list[str]]:
    calls: dict[str, list[str]] = {}
    for path in SOURCE_DIR.rglob("*.swift"):
        content = path.read_text(encoding="utf-8")
        for match in L10N_CALL.finditer(content):
            key = match.group("key")
            line = content.count("\n", 0, match.start()) + 1
            calls.setdefault(key, []).append(f"{path.relative_to(ROOT)}:{line}")
    return calls


def print_missing(title: str, keys: set[str], references: dict[str, list[str]] | None = None) -> None:
    print(f"\n{title}")
    for key in sorted(keys):
        print(f"  {key}")
        if references:
            for ref in sorted(references.get(key, [])):
                print(f"    {ref}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--include-unused",
        action="store_true",
        help="also list English keys not referenced by L10n.string",
    )
    args = parser.parse_args()

    tables: dict[str, dict[str, str]] = {}
    for lproj in sorted(RESOURCES_DIR.glob("*.lproj")):
        table = lproj / "Localizable.strings"
        if not table.exists():
            print(f"error: missing {table.relative_to(ROOT)}", file=sys.stderr)
            return 1
        tables[lproj.name] = parse_strings(table)

    if "en.lproj" not in tables:
        print("error: English localization table is missing", file=sys.stderr)
        return 1

    english = tables["en.lproj"]
    calls = collect_l10n_calls()
    failed = False

    missing_from_english = set(calls) - set(english)
    if missing_from_english:
        failed = True
        print_missing(
            "Missing from en.lproj/Localizable.strings (referenced by L10n.string):",
            missing_from_english,
            calls,
        )

    required_keys = set(english) | set(calls)

    for language, keys in tables.items():
        if language == "en.lproj":
            continue

        missing = required_keys - set(keys)
        if missing:
            failed = True
            print_missing(
                f"Missing from {language}/Localizable.strings (present in English or referenced by L10n.string):",
                missing,
            )

        extra = set(keys) - set(english)
        if extra:
            failed = True
            print_missing(
                f"Extra in {language}/Localizable.strings (not present in English):",
                extra,
            )

    if args.include_unused:
        unused = set(english) - set(calls)
        if unused:
            print_missing("English keys not referenced by L10n.string:", unused)

    if failed:
        print("\nLocalization check failed.", file=sys.stderr)
        return 1

    print("Localization check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
