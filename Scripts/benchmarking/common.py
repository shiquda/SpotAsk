"""Shared helpers for the math benchmark harness."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
PROBE = REPO / "Scripts" / "ax_probe"
BUNDLE_ID = "com.spotask.benchmark"
APP_BUNDLE = Path("/tmp/SpotAskBenchmark.app")
SUPPORT = Path.home() / "Library" / "Application Support" / BUNDLE_ID
WORK = Path("/tmp/spotask-bench")
BASELINE_REF = "db1cca0f06c5270e6dc063bb0bf83236f0475189"
BASELINE_WORKTREE = REPO.parent / "baseline-spotask"
OUT_DIR = REPO / "benchmarks"
LOG_DIR = OUT_DIR / "logs"
SHOT_DIR = OUT_DIR / "screenshots"

BUILD_FLAGS = ["-c", "release", "-Xswiftc", "-DSPOTASK_BENCHMARK"]


class BenchError(RuntimeError):
    pass


def log(message: str) -> None:
    print(message, flush=True)


def run(cmd, *, cwd=None, check=True, capture=True, env=None, text=True):
    result = subprocess.run(
        [str(part) for part in cmd],
        cwd=str(cwd) if cwd else None,
        capture_output=capture,
        text=text,
        env=env,
    )
    if check and result.returncode != 0:
        stderr = result.stderr.strip() if result.stderr else ""
        raise BenchError(f"command failed ({result.returncode}): {cmd}\n{stderr}")
    return result


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(src: Path, *args: str) -> str:
    return run(["git", "-C", src, *args]).stdout.strip()


def tool_version(cmd) -> str:
    try:
        return run([cmd, "--version"], check=False).stdout.strip().splitlines()[0]
    except Exception:
        return "unknown"


def footprint_bytes(pid: int) -> int | None:
    """Physical footprint from /usr/bin/footprint, in bytes."""
    result = run(["/usr/bin/footprint", "-f", "bytes", str(pid)], check=False)
    if result.returncode != 0:
        return None
    match = re.search(r"phys_footprint:\s*([0-9.]+)\s*(KB|MB|GB|B)?", result.stdout)
    if not match:
        return None
    value = float(match.group(1))
    unit = match.group(2) or "B"
    scale = {"B": 1, "KB": 1024, "MB": 1024 ** 2, "GB": 1024 ** 3}[unit]
    return int(value * scale)


def rss_bytes(pid: int) -> int | None:
    result = run(["ps", "-o", "rss=", "-p", str(pid)], check=False)
    text = result.stdout.strip()
    if not text:
        return None
    try:
        return int(text.splitlines()[0].strip()) * 1024
    except ValueError:
        return None


def mib(value: int | None) -> float | None:
    return None if value is None else round(value / (1024 ** 2), 2)


def stats(values):
    values = [value for value in values if value is not None]
    if not values:
        return {"samples": [], "min": None, "median": None, "max": None}
    ordered = sorted(values)
    return {
        "samples": values,
        "min": ordered[0],
        "median": ordered[len(ordered) // 2],
        "max": ordered[-1],
    }


def ensure_dirs() -> None:
    for directory in (LOG_DIR, SHOT_DIR, WORK):
        directory.mkdir(parents=True, exist_ok=True)


def write_jsonl(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def read_jsonl(path: Path):
    if not path.exists():
        return []
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def clean_support() -> None:
    shutil.rmtree(SUPPORT, ignore_errors=True)
    run(["defaults", "delete", BUNDLE_ID], check=False)


def cleanup_work() -> None:
    shutil.rmtree(APP_BUNDLE, ignore_errors=True)
    shutil.rmtree(WORK, ignore_errors=True)


def exit_with(message: str) -> None:
    print(message, file=sys.stderr, flush=True)
    sys.exit(1)
