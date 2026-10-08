#!/usr/bin/env python3
"""Check that SpotAsk.xcodeproj compiles every Swift source in Sources/.

SwiftPM's `swift test` reads the filesystem, but the Release build in
`Scripts/make-release-dmg.sh` builds `SpotAsk.xcodeproj`, which only compiles
the files registered in the project. A source file that exists on disk but is
missing from the project compiles locally and in pull requests, and only fails
the "Package the DMG" step after it merges to main — a gate pull requests never
reach, because packaging runs on `push` only.

This script is a required CI gate. It fails when a `Sources/**/*.swift` file is
not wired into the target, when the target references a file that no longer
exists, or when the project lists the same file twice.

Usage: Scripts/verify-xcode-project-files.py [--root DIR]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

OBJECT_ID = r"[0-9A-Fa-f]{24}"
PROJECT_NAME = "SpotAsk.xcodeproj"
PROJECT_FILE = Path(PROJECT_NAME) / "project.pbxproj"
SOURCES_DIR = Path("Sources")

# `ID /* comment */ = {` opens an object; its body may wrap across lines.
OBJECT_START = re.compile(r"^\s*(" + OBJECT_ID + r")\b[^\n]*?= \{", re.MULTILINE)
ATTRIBUTE = r"(?:^\s*|;\s*)%s = ([^;]+);"
SOURCES_PHASE_FILES = re.compile(r"files = \((.*?)\);", re.DOTALL)


def attribute(body: str, name: str) -> str | None:
    match = re.search(ATTRIBUTE % re.escape(name), body)
    if match is None:
        return None
    # Xcode appends the referenced object's name as a comment: `fileRef = 001… /* SpotAskApp.swift */;`
    value = re.sub(r"\s*/\*.*?\*/\s*$", "", match.group(1)).strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    return value


def object_bodies(text: str):
    """Yield (object_id, body) for every `ID /* comment */ = { ... };` entry."""
    for match in OBJECT_START.finditer(text):
        index = depth = 0
        index = match.end()
        depth = 1
        while index < len(text) and depth > 0:
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            index += 1
        yield match.group(1), text[match.end() : index - 1]


class Project:
    """The parts of project.pbxproj this check reasons about."""

    def __init__(self, text: str) -> None:
        self.paths: dict[str, str] = {}
        self.source_trees: dict[str, str] = {}
        self.build_ids_of_file_ref: dict[str, list[str]] = {}
        self.phase_lists: list[list[str]] = []

        for object_id, body in object_bodies(text):
            isa = attribute(body, "isa")
            if isa == "PBXFileReference":
                path = attribute(body, "path") or attribute(body, "name")
                if path is not None:
                    self.paths[object_id] = path
                    self.source_trees[object_id] = attribute(body, "sourceTree") or "<group>"
            elif isa == "PBXBuildFile":
                file_ref = attribute(body, "fileRef")
                if file_ref is not None:
                    self.build_ids_of_file_ref.setdefault(file_ref, []).append(object_id)
            elif isa == "PBXSourcesBuildPhase":
                files = SOURCES_PHASE_FILES.search(body)
                self.phase_lists.append(re.findall(OBJECT_ID, files.group(1)) if files else [])

    def resolve(self, object_id: str, by_basename: dict[str, list[Path]]) -> Path | None:
        """The on-disk path a file reference points at, if it can be resolved."""
        raw = self.paths[object_id]
        if self.source_trees.get(object_id) == "SOURCE_ROOT" or raw.startswith("Sources/"):
            return Path(raw)
        # A reference created through Xcode's UI carries only the file name and
        # inherits the directory from its group. Resolve it through the on-disk
        # basename when that is unambiguous, so adding a file the default way
        # does not read as an omission here.
        names = by_basename.get(Path(raw).name, [])
        return names[0] if len(names) == 1 else None


def disk_sources(root: Path) -> dict[str, list[Path]]:
    """Every Swift source under Sources/, indexed by basename."""
    by_basename: dict[str, list[Path]] = {}
    for path in sorted((root / SOURCES_DIR).rglob("*.swift")):
        by_basename.setdefault(path.name, []).append(path.relative_to(root))
    return by_basename


def check(root: Path, project: Project) -> list[str]:
    problems: list[str] = []

    if len(project.phase_lists) != 1:
        return [
            f"{PROJECT_FILE} declares {len(project.phase_lists)} PBXSourcesBuildPhase "
            "sections; this check expects exactly one"
        ]

    phase = project.phase_lists[0]
    if len(phase) != len(set(phase)):
        repeated = sorted({object_id for object_id in phase if phase.count(object_id) > 1})
        problems.append(f"the Sources build phase lists {len(repeated)} build file(s) twice: {', '.join(repeated)}")
    in_phase = set(phase)

    by_basename = disk_sources(root)

    # Several references can point at the same file; report each file once.
    resolved: dict[Path | None, list[str]] = {}
    for object_id, raw in project.paths.items():
        if not raw.endswith(".swift"):
            continue
        resolved.setdefault(project.resolve(object_id, by_basename), []).append(object_id)

    for path, object_ids in sorted(resolved.items(), key=lambda item: str(item[0])):
        if path is None:
            names = sorted({project.paths[object_id] for object_id in object_ids})
            problems.append(f"{PROJECT_FILE} references {', '.join(names)}, which is not a path this check can resolve")
            continue
        if len(object_ids) > 1:
            problems.append(f"{PROJECT_FILE} references {path} {len(object_ids)} times")
        if not (root / path).is_file():
            problems.append(f"{PROJECT_FILE} references {path}, which no longer exists")

    for path in sorted({p for paths in by_basename.values() for p in paths}):
        object_ids = resolved.get(path, [])
        if not object_ids:
            problems.append(f"{path} is not part of {PROJECT_NAME}; add it to the SpotAsk target")
            continue
        build_ids = [
            build_id for object_id in object_ids for build_id in project.build_ids_of_file_ref.get(object_id, [])
        ]
        if not build_ids:
            problems.append(f"{path} is not built by the SpotAsk target; add it to a Compile Sources build phase")
        elif not set(build_ids) & in_phase:
            problems.append(
                f"{path} is not in the SpotAsk target's Sources build phase; "
                "the Release build of SpotAsk.xcodeproj never compiles it"
            )

    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=None, help="repository root (default: the parent of Scripts/)")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parent.parent
    project_file = root / PROJECT_FILE
    if not project_file.is_file():
        print(f"FAIL: {PROJECT_FILE} not found under {root}", file=sys.stderr)
        return 1

    project = Project(project_file.read_text(encoding="utf-8"))
    problems = check(root, project)

    if problems:
        for problem in problems:
            print(f"FAIL: {problem}", file=sys.stderr)
        print(f"{len(problems)} Xcode project problem(s)", file=sys.stderr)
        return 1

    swift_sources = sum(len(paths) for paths in disk_sources(root).values())
    print(
        f"verify-xcode-project-files: {swift_sources} Swift sources in Sources/ are wired into the SpotAsk target."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
