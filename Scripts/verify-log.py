#!/usr/bin/env python3
"""One execution, one full log, unlimited reads.

A piped check (`npm run test | grep failed`) throws away the pass/fail line and
the counts, so the same suite gets run again just to read what the first run
already printed. This tool writes stdout+stderr and the real exit code of one
execution into `.verification-logs/<id>/`, then answers status, counts and
failures from that log as many times as needed.

    ./scripts/verify-log.py run --label unit -- npm run test
    ./scripts/verify-log.py summary            # newest run
    ./scripts/verify-log.py failures           # newest run
    ./scripts/verify-log.py reuse              # is the newest run still valid evidence?
    ./scripts/verify-log.py list

`run` exits with the command's own exit code. It never reports "passed" on its
own authority: the exit code decides, and a log that contains failure markers
while the exit code is 0 is reported as `inconclusive`, never as success.

Identity of the evidence (what makes it reusable) is recorded at run start:
HEAD, the full dirty-worktree content (tracked diff + index + untracked file
contents, not just the commit), dependency manifests, and toolchain versions.
`reuse` recomputes them and refuses evidence as soon as anything moved.

Standard library only, Python 3.9+, because both repositories that use this
file (WhyFirst `scripts/verify-log.py`, SpotAsk `Scripts/verify-log.py`) must be
able to run it from a bare checkout. The two copies are the same file: change
them together, or they will drift.
"""

import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime

LOG_DIR = ".verification-logs"
SCHEMA = 1
CHUNK = 64 * 1024

# Dependency inputs are fingerprinted regardless of `--scope`: a lockfile or
# manifest change invalidates evidence even when the check only covered part of
# the tree, because it can change what the whole checkout resolves to.
DEPENDENCY_BASENAMES = {
    "package.json",
    "package-lock.json",
    "pnpm-lock.yaml",
    "pnpm-workspace.yaml",
    "yarn.lock",
    "Cargo.toml",
    "Cargo.lock",
    "rust-toolchain.toml",
    "pyproject.toml",
    "uv.lock",
    "Package.swift",
    "Package.resolved",
}

ENV_PROBES = [
    ("node", ["node", "--version"]),
    ("npm", ["npm", "--version"]),
    ("pnpm", ["pnpm", "--version"]),
    ("swift", ["swift", "--version"]),
    ("python3", [sys.executable, "--version"]),
]

# Installed dependency trees decide what the check actually runs against, and
# hashing them is too expensive. Recording presence and entry count still catches
# the real case that bit us: a suite that failed only because `website/node_modules`
# had not been installed yet, then passed after `npm ci` with identical manifests.
# Only installer-owned trees belong here — a build output such as `.build/` is
# produced by the run itself and would mark its own evidence stale.
INSTALL_PROBES = ("node_modules", "website/node_modules", "backend/node_modules")

# Markers that mean "this log contains a failure", independent of the exit code.
# Covers vitest (`FAIL`, `×`), XCTest/swift-testing (`✘`, `error:`), cargo
# (`test name ... FAILED`), pytest (`FAILED tests/...`, `E   AssertionError`) and
# plain `not ok N` TAP output.
FAILURE_LINE = re.compile(
    r"^\s*(?:FAIL\b|FAILED\b|✘|×|not ok \d+)"
    r"|^\s*test .* \.\.\. FAILED\b"
    r"|^\s*E\s+AssertionError\b"
    r"|^\s*AssertionError\b"
    r"|:\d+: error: "
    r"|XCTAssert\w* failed"
)

VITEST_COUNTS = re.compile(r"^\s*(Tests|Test Files)\s+(.+?)\s*\((\d+)\)\s*$")
VITEST_PART = re.compile(r"(\d+)\s+(passed|failed|skipped|todo)")
SWIFT_TESTING_RUN = re.compile(
    r"Test run with (\d+) tests? (passed|failed) after [\d.]+ seconds?(?: with (\d+) )?(?:issues?)?"
)
XCTEST_TOTAL = re.compile(r"Executed (\d+) tests?, with (\d+) failures?")
CARGO_RESULT = re.compile(r"^test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored")
NODE_TEST_LINE = re.compile(r"^\s*(?:ℹ|#)\s*(tests|pass|fail|skipped|todo)\s+(\d+)\s*$")
PYTEST_SUMMARY = re.compile(r"^=*\s*((?:\d+ \w+(?:, )?)+?) in [\d.]+s\b")


# --------------------------------------------------------------------------- io


def note(message):
    print(message, file=sys.stderr)


def fail(message, code=2):
    print("verify-log: " + message, file=sys.stderr)
    sys.exit(code)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def human_bytes(size):
    for unit in ("B", "KiB", "MiB", "GiB"):
        if size < 1024 or unit == "GiB":
            return "%.0f %s" % (size, unit) if unit == "B" else "%.1f %s" % (size, unit)
        size /= 1024.0


def human_duration(seconds):
    if seconds < 1:
        return "%d ms" % round(seconds * 1000)
    if seconds < 60:
        return "%.1f s" % seconds
    minutes, rest = divmod(int(round(seconds)), 60)
    return "%d m %02d s" % (minutes, rest)


def utc_stamp(moment=None):
    moment = moment or datetime.utcnow()
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def git(root, args, binary=False):
    """Run git, returning stdout ("" / b"" when git refuses)."""
    try:
        done = subprocess.run(
            ["git", "-C", root] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return b"" if binary else ""
    if done.returncode != 0:
        return b"" if binary else ""
    return done.stdout if binary else done.stdout.decode("utf-8", "replace")


def repo_root(cwd):
    out = git(cwd, ["rev-parse", "--show-toplevel"]).strip()
    return out or cwd


def is_ignored(root, path):
    try:
        done = subprocess.run(
            ["git", "-C", root, "check-ignore", "-q", "--", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return False
    return done.returncode == 0


# ------------------------------------------------------------------- identity


def resolve_scopes(root, cwd, scopes):
    """Scopes are given relative to the caller's cwd, stored relative to the root."""
    resolved = []
    for scope in scopes or ["."]:
        absolute = os.path.normpath(os.path.join(cwd, scope))
        if not absolute.startswith(root + os.sep) and absolute != root:
            fail("scope %s is outside the repository %s" % (scope, root))
        resolved.append(os.path.relpath(absolute, root).replace(os.sep, "/"))
    return resolved


def environment(root):
    probe = {"os": "%s %s %s" % os.uname()[0:3], "arch": os.uname()[4]}
    for name, command in ENV_PROBES:
        try:
            done = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=20,
                cwd=root,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if done.returncode != 0:
            continue
        text = done.stdout.decode("utf-8", "replace").strip()
        if not text:
            continue
        first = text.splitlines()[0].strip()
        probe[name] = first
        if name == "swift" and len(text.splitlines()) > 1:
            # The target triple decides which arch-dependent failures can appear.
            probe["swift_target"] = text.splitlines()[1].strip()
    return probe


def install_state(root):
    state = {}
    for relative in INSTALL_PROBES:
        absolute = os.path.join(root, relative)
        if not os.path.isdir(absolute):
            state[relative] = "absent"
            continue
        try:
            entries = len(os.listdir(absolute))
        except OSError:
            state[relative] = "unreadable"
            continue
        state[relative] = "present:%d" % entries
    return state


def dependency_inputs(root):
    tracked = git(root, ["ls-files", "-z"], binary=True).split(b"\0")
    found = {}
    for raw in tracked:
        if not raw:
            continue
        path = raw.decode("utf-8", "replace")
        if os.path.basename(path) not in DEPENDENCY_BASENAMES:
            continue
        absolute = os.path.join(root, path)
        if os.path.isfile(absolute):
            found[path] = sha256_file(absolute)
        else:
            found[path] = "missing"
    return found


def untracked_content(root, scopes):
    """Hash the content of untracked files so a new file is not "the same tree"."""
    raw = git(root, ["ls-files", "-z", "--others", "--exclude-standard", "--", *scopes], binary=True)
    entries = []
    for item in raw.split(b"\0"):
        if not item:
            continue
        path = item.decode("utf-8", "replace")
        if path.startswith(LOG_DIR + "/") or path == LOG_DIR:
            continue
        absolute = os.path.join(root, path)
        if os.path.islink(absolute):
            entries.append((path, "link:" + os.readlink(absolute)))
        elif os.path.isfile(absolute):
            entries.append((path, sha256_file(absolute)))
        else:
            entries.append((path, "unreadable"))
    return entries


def worktree_fingerprint(root, scopes):
    head = git(root, ["rev-parse", "HEAD"]).strip()
    branch = git(root, ["rev-parse", "--abbrev-ref", "HEAD"]).strip()
    index = git(root, ["ls-files", "-s", "-z", "--", *scopes], binary=True)
    diff = git(root, ["diff", "HEAD", "--binary", "--", *scopes], binary=True) if head else b""
    untracked = untracked_content(root, scopes)
    status_text = git(root, ["status", "--porcelain", "--untracked-files=normal", "--", *scopes])
    status_lines = [
        line
        for line in status_text.splitlines()
        if line.strip() and LOG_DIR not in line
    ]

    digest = hashlib.sha256()
    digest.update(b"head\0" + head.encode("utf-8") + b"\0")
    digest.update(b"index\0" + index + b"\0")
    digest.update(b"diff\0" + diff + b"\0")
    for path, content_hash in untracked:
        digest.update(b"untracked\0" + path.encode("utf-8") + b"\0")
        digest.update(content_hash.encode("utf-8") + b"\0")

    return {
        "head": head or None,
        "branch": branch or None,
        "dirty": bool(status_lines),
        "status": status_lines[:200],
        "scopes": scopes,
        "worktree": "sha256:" + digest.hexdigest(),
    }


def build_inputs(root, scopes):
    inputs = worktree_fingerprint(root, scopes)
    inputs["dependencies"] = dependency_inputs(root)
    inputs["installed"] = install_state(root)
    inputs["probe_set"] = list(INSTALL_PROBES)
    inputs["environment"] = environment(root)

    digest = hashlib.sha256()
    for key in ("head", "worktree"):
        digest.update(key.encode("utf-8") + b"\0")
        digest.update(str(inputs[key]).encode("utf-8") + b"\0")
    digest.update(b"probes\0" + "\0".join(inputs["probe_set"]).encode("utf-8") + b"\0")
    for path in sorted(inputs["dependencies"]):
        digest.update(b"dep\0" + path.encode("utf-8") + b"\0")
        digest.update(inputs["dependencies"][path].encode("utf-8") + b"\0")
    for path in sorted(inputs["installed"]):
        digest.update(b"installed\0" + path.encode("utf-8") + b"\0")
        digest.update(inputs["installed"][path].encode("utf-8") + b"\0")
    for key in sorted(inputs["environment"]):
        digest.update(b"env\0" + key.encode("utf-8") + b"\0")
        digest.update(str(inputs["environment"][key]).encode("utf-8") + b"\0")
    inputs["fingerprint"] = "sha256:" + digest.hexdigest()
    return inputs


# --------------------------------------------------------------------- running


def status_from_exit(code):
    if code is None:
        return "incomplete"
    if code == 0:
        return "passed"
    return "failed"


def run_dir_path(root, label):
    stamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    suffix = hashlib.sha256(("%s %s %s" % (stamp, label, os.getpid())).encode()).hexdigest()[:6]
    return os.path.join(root, LOG_DIR, "%s-%s-%s" % (stamp, label, suffix))


def command_run(args):
    if not args.command:
        fail("run needs a command: verify-log.py run --label unit -- npm run test")
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,48}", args.label):
        fail("--label must match [A-Za-z0-9._-]{1,48}")

    cwd = os.getcwd()
    root = repo_root(cwd)
    scopes = resolve_scopes(root, cwd, args.scope)
    directory = run_dir_path(root, args.label)
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(root, LOG_DIR, ".gitignore"), "w", encoding="utf-8") as handle:
        handle.write("# Verification logs are local evidence, never committed.\n*\n")
    if not is_ignored(root, os.path.join(LOG_DIR, "output.log")):
        note("verify-log: warning: %s/ is not ignored by git; add it to .gitignore" % LOG_DIR)

    inputs = build_inputs(root, scopes)
    log_path = os.path.join(directory, "output.log")
    started_at = utc_stamp()
    started = time.monotonic()
    exit_code = None
    interruption = None
    echoed = bool(args.echo)

    try:
        process = subprocess.Popen(
            args.command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
    except OSError as error:
        fail("cannot start %r: %s" % (args.command[0], error))

    with open(log_path, "wb") as log:
        try:
            while True:
                chunk = process.stdout.read(CHUNK)
                if not chunk:
                    break
                log.write(chunk)
                if echoed:
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
        except KeyboardInterrupt:
            interruption = "keyboard interrupt"
            process.send_signal(signal.SIGINT)
        finally:
            try:
                exit_code = process.wait(timeout=300)
            except subprocess.TimeoutExpired:
                process.kill()
                exit_code = process.wait()
                interruption = interruption or "did not exit after the log stream closed"

    duration = time.monotonic() - started
    if exit_code is not None and exit_code < 0:
        interruption = interruption or "terminated by signal %d" % (-exit_code)
        status = "incomplete"
    else:
        status = status_from_exit(exit_code)
    if interruption:
        status = "incomplete"

    log_bytes = os.path.getsize(log_path)
    meta = {
        "schema": SCHEMA,
        "id": os.path.basename(directory),
        "label": args.label,
        "command": args.command,
        "command_display": " ".join(args.command),
        "cwd": os.path.relpath(cwd, root).replace(os.sep, "/"),
        "started_at": started_at,
        "finished_at": utc_stamp(),
        "duration_s": round(duration, 3),
        "exit_code": exit_code,
        "status": status,
        "interruption": interruption,
        "log": {
            "file": "output.log",
            "bytes": log_bytes,
            "sha256": sha256_file(log_path),
        },
        "inputs": inputs,
    }
    with open(os.path.join(directory, "meta.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2, sort_keys=True)
        handle.write("\n")

    relative = os.path.relpath(directory, root).replace(os.sep, "/")
    print("run: %s" % relative)
    print("status: %s" % status.upper())
    print("exit: %s" % ("-" if exit_code is None else exit_code))
    print("duration: %s" % human_duration(duration))
    print("log: %s/%s (%s)" % (relative, "output.log", human_bytes(log_bytes)))
    if interruption:
        print("interruption: %s" % interruption)
    print("read again without rerunning: %s summary %s" % (sys.argv[0], relative))
    # Non-zero command codes pass through unchanged; a missing code or a signal
    # is reported as 1 so the shell never sees a negative status.
    if exit_code is None or exit_code < 0:
        return 1
    return exit_code


# --------------------------------------------------------------------- reading


def all_runs(root):
    base = os.path.join(root, LOG_DIR)
    if not os.path.isdir(base):
        return []
    runs = [
        os.path.join(base, name)
        for name in sorted(os.listdir(base))
        if os.path.isdir(os.path.join(base, name))
    ]
    return runs


def resolve_run(root, selector, required=True):
    if not selector or selector == "latest":
        runs = all_runs(root)
        if not runs:
            fail("no runs under %s/; run a check first" % LOG_DIR, 1)
        return runs[-1]
    candidate = selector
    if not os.path.isabs(candidate):
        candidate = os.path.join(root, selector)
    if not os.path.isdir(candidate):
        candidate = os.path.join(root, LOG_DIR, selector)
    if not os.path.isdir(candidate):
        if required:
            fail("no such run: %s" % selector, 1)
        return None
    return candidate


def load_meta(directory):
    path = os.path.join(directory, "meta.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def read_log(directory):
    path = os.path.join(directory, "output.log")
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as handle:
        return handle.read().decode("utf-8", "replace")


def parse_counts(text):
    counts = {}
    cargo = None
    node = {}
    for line in text.splitlines():
        match = VITEST_COUNTS.match(line)
        if match:
            bucket = "files" if match.group(1) == "Test Files" else "tests"
            parts = {kind: int(number) for number, kind in VITEST_PART.findall(match.group(2))}
            parts["total"] = int(match.group(3))
            counts[bucket] = parts
            continue
        match = SWIFT_TESTING_RUN.search(line)
        if match:
            bucket = {
                "total": int(match.group(1)),
                "passed": int(match.group(1)) if match.group(2) == "passed" else 0,
                "failed": int(match.group(1)) if match.group(2) == "failed" else 0,
            }
            if match.group(3):
                bucket["issues"] = int(match.group(3))
            counts["swift-testing"] = bucket
            continue
        match = XCTEST_TOTAL.search(line)
        if match:
            counts["xctest"] = {
                "total": int(match.group(1)),
                "failures": int(match.group(2)),
                "passed": int(match.group(1)) - int(match.group(2)),
            }
            continue
        match = CARGO_RESULT.match(line)
        if match:
            # One line per test binary; summing them gives the workspace total.
            passed, failed, ignored = (int(match.group(i)) for i in (2, 3, 4))
            cargo = cargo or {"passed": 0, "failed": 0, "ignored": 0, "binaries": 0}
            cargo["passed"] += passed
            cargo["failed"] += failed
            cargo["ignored"] += ignored
            cargo["binaries"] += 1
            continue
        match = NODE_TEST_LINE.match(line)
        if match:
            node[match.group(1)] = int(match.group(2))
            continue
        match = PYTEST_SUMMARY.match(line)
        if match:
            parts = {
                kind: int(number)
                for number, kind in re.findall(r"(\d+) (\w+)", match.group(1))
            }
            if any(kind in parts for kind in ("passed", "failed", "error", "errors")):
                errors = parts.pop("errors", 0) + parts.pop("error", 0)
                counts["pytest"] = {
                    "passed": parts.get("passed", 0),
                    "failed": parts.get("failed", 0),
                    "errors": errors,
                    "skipped": parts.get("skipped", 0),
                    "total": parts.get("passed", 0) + parts.get("failed", 0) + errors
                    + parts.get("skipped", 0),
                }
    if cargo:
        cargo["total"] = cargo["passed"] + cargo["failed"]
        counts["cargo"] = cargo
    if "tests" in node:
        counts["node"] = dict(
            node,
            passed=node.get("pass", 0),
            failed=node.get("fail", 0),
            total=node["tests"],
        )
    return counts


def failure_lines(text, limit=40):
    hits = []
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.rstrip()
        if FAILURE_LINE.search(stripped):
            hits.append((number, stripped))
            if len(hits) >= limit:
                break
    return hits


def describe_run(directory, root):
    """Status always comes from the exit code; the log can only make it worse."""
    meta = load_meta(directory)
    record = {
        "run": os.path.relpath(directory, root).replace(os.sep, "/"),
        "meta": bool(meta),
        "status": "incomplete",
        "exit_code": None,
        "notes": [],
    }
    if not meta:
        record["notes"].append("no meta.json: the run never finished, so this is not success evidence")
        record["strategy"] = None
        return record

    record.update(
        {
            "label": meta.get("label"),
            "command": meta.get("command_display") or " ".join(meta.get("command") or []),
            "cwd": meta.get("cwd"),
            "started_at": meta.get("started_at"),
            "finished_at": meta.get("finished_at"),
            "duration_s": meta.get("duration_s"),
            "exit_code": meta.get("exit_code"),
            "interruption": meta.get("interruption"),
            "inputs": meta.get("inputs") or {},
            "log": meta.get("log") or {},
        }
    )

    text = read_log(directory)
    if text is None:
        record["strategy"] = None
        record["notes"].append("output.log is missing: evidence cannot be read")
        return record

    recorded_hash = (meta.get("log") or {}).get("sha256")
    if recorded_hash and sha256_bytes(text.encode("utf-8")) != recorded_hash:
        record["notes"].append("output.log no longer matches its recorded sha256")
        log_intact = False
    else:
        log_intact = True

    markers = failure_lines(text)
    record["failure_lines"] = len(markers)
    record["counts"] = parse_counts(text)

    exit_code = meta.get("exit_code")
    if meta.get("status") == "incomplete" or exit_code is None or exit_code < 0:
        record["status"] = "incomplete"
        record["notes"].append(
            "run incomplete (%s)" % (meta.get("interruption") or "no exit code"),
        )
    elif exit_code != 0:
        record["status"] = "failed"
    elif not log_intact:
        record["status"] = "inconclusive"
    elif markers:
        record["status"] = "inconclusive"
        record["notes"].append(
            "%d failure line(s) in the log although the exit code is 0" % len(markers)
        )
    else:
        record["status"] = "passed"
    return record


def print_summary(record, as_json):
    if as_json:
        print(json.dumps(record, indent=2, sort_keys=True))
        return
    inputs = record.get("inputs") or {}
    log = record.get("log") or {}
    rows = [
        ("run", record["run"]),
        ("status", record["status"].upper()),
        ("exit", "-" if record.get("exit_code") is None else record["exit_code"]),
        ("command", record.get("command") or "-"),
        ("cwd", record.get("cwd") or "-"),
        ("started", record.get("started_at") or "-"),
        ("duration", human_duration(record["duration_s"]) if record.get("duration_s") is not None else "-"),
        (
            "inputs",
            "HEAD %s%s %s"
            % (
                (inputs.get("head") or "-")[:12],
                " (dirty)" if inputs.get("dirty") else "",
                (inputs.get("fingerprint") or "-")[:19],
            ),
        ),
        (
            "log",
            "%s/%s (%s)" % (record["run"], "output.log", human_bytes(log.get("bytes", 0))),
        ),
    ]
    for key, value in rows:
        print("%-10s %s" % (key + ":", value))
    counts = record.get("counts") or {}
    for name in ("tests", "files", "swift-testing", "xctest", "cargo", "node", "pytest"):
        if name in counts:
            parts = " ".join("%s=%s" % (k, counts[name][k]) for k in sorted(counts[name]))
            print("%-10s %s %s" % ("counts:", name, parts))
    if record.get("failure_lines"):
        print("%-10s %d (read them with: %s failures %s)" % ("failures:", record["failure_lines"], sys.argv[0], record["run"]))
    for message in record.get("notes", []):
        print("%-10s %s" % ("note:", message))


def command_summary(args):
    root = repo_root(os.getcwd())
    record = describe_run(resolve_run(root, args.run), root)
    print_summary(record, args.json)
    return 0 if record["status"] == "passed" else 1


def command_failures(args):
    root = repo_root(os.getcwd())
    directory = resolve_run(root, args.run)
    record = describe_run(directory, root)
    text = read_log(directory)
    if text is None:
        fail("run has no output.log: %s" % record["run"], 1)
    hits = failure_lines(text, args.limit)
    if args.json:
        print(
            json.dumps(
                {
                    "run": record["run"],
                    "status": record["status"],
                    "exit_code": record.get("exit_code"),
                    "lines": [{"line": number, "text": text_line} for number, text_line in hits],
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0
    print("status: %s (exit %s)" % (record["status"].upper(), record.get("exit_code")))
    if not hits:
        print("no failure lines in %s/output.log" % record["run"])
    for number, text_line in hits:
        print("%s:%d: %s" % (record["run"], number, text_line))
    if record.get("failure_lines", 0) > len(hits):
        print("... %d more; raise --limit" % (record["failure_lines"] - len(hits)))
    return 0


def command_reuse(args):
    root = repo_root(os.getcwd())
    directory = resolve_run(root, args.run)
    record = describe_run(directory, root)
    reasons = []
    if record["status"] != "passed":
        reasons.append("evidence status is %s, not a complete success" % record["status"])

    meta = load_meta(directory) or {}
    recorded = meta.get("inputs") or {}
    if recorded:
        current = build_inputs(root, recorded.get("scopes") or ["."])
        if recorded.get("head") != current.get("head"):
            reasons.append("HEAD moved %s -> %s" % ((recorded.get("head") or "-")[:12], (current.get("head") or "-")[:12]))
        if recorded.get("worktree") != current.get("worktree"):
            changed = sorted(
                set(recorded.get("status") or []) ^ set(current.get("status") or [])
            )
            detail = "; ".join(changed[:5])
            reasons.append("worktree content changed" + (": " + detail if detail else " (dirty state differs)"))
        old_deps, new_deps = recorded.get("dependencies") or {}, current.get("dependencies") or {}
        for path in sorted(set(old_deps) | set(new_deps)):
            if old_deps.get(path) != new_deps.get(path):
                reasons.append("dependency input changed: %s" % path)
        old_env, new_env = recorded.get("environment") or {}, current.get("environment") or {}
        for key in sorted(set(old_env) | set(new_env)):
            if old_env.get(key) != new_env.get(key):
                reasons.append(
                    "environment changed: %s %r -> %r" % (key, old_env.get(key), new_env.get(key))
                )
        old_installed = recorded.get("installed") or {}
        new_installed = current.get("installed") or {}
        probe_changed = (recorded.get("probe_set") or []) != (current.get("probe_set") or [])
        if probe_changed:
            # The sets are not comparable; one reason covers it instead of listing
            # every path that only one of them probed.
            reasons.append(
                "what this tool fingerprints changed (probe set %s -> %s); rerun to record comparable inputs"
                % (recorded.get("probe_set"), current.get("probe_set"))
            )
        for path in (() if probe_changed else sorted(set(old_installed) | set(new_installed))):
            if old_installed.get(path) != new_installed.get(path):
                reasons.append(
                    "installed dependencies changed: %s %s -> %s"
                    % (path, old_installed.get(path), new_installed.get(path))
                )
    else:
        reasons.append("run recorded no input identity, so it cannot be reused")

    verdict = "reusable" if not reasons else "stale"
    if args.json:
        print(
            json.dumps(
                {
                    "run": record["run"],
                    "verdict": verdict,
                    "status": record["status"],
                    "reasons": reasons,
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        print("run:      %s" % record["run"])
        print("verdict:  %s" % verdict.upper())
        print("status:   %s" % record["status"].upper())
        if reasons:
            print("reasons:")
            for reason in reasons:
                print("  - %s" % reason)
        else:
            print("the recorded inputs still match this worktree; read the existing log instead of rerunning")
    return 0 if verdict == "reusable" else 1


def command_list(args):
    root = repo_root(os.getcwd())
    runs = list(reversed(all_runs(root)))
    if args.json:
        print(json.dumps([describe_run(run, root) for run in runs], indent=2, sort_keys=True))
        return 0
    if not runs:
        print("no runs under %s/" % LOG_DIR)
        return 0
    for run in runs:
        record = describe_run(run, root)
        size = human_bytes((record.get("log") or {}).get("bytes", 0))
        print(
            "%-28s %-9s exit=%-4s %-14s %10s  %s"
            % (
                os.path.basename(run)[:28],
                record["status"],
                "-" if record.get("exit_code") is None else record["exit_code"],
                (record.get("label") or "-")[:14],
                size,
                (record.get("command") or "")[:60],
            )
        )
    return 0


# ------------------------------------------------------------------------ main


def main(argv):
    parser = argparse.ArgumentParser(
        prog="verify-log.py",
        description="Run a check once with a full log, then read status/counts/failures from that log.",
    )
    sub = parser.add_subparsers(dest="action", required=True)

    run = sub.add_parser("run", help="execute a command and record its full log, exit code and input identity")
    run.add_argument("--label", required=True, help="short name for this check, e.g. unit or e2e")
    run.add_argument("--echo", action="store_true", help="also stream the log to the terminal")
    run.add_argument(
        "--scope",
        action="append",
        metavar="PATH",
        help="path the evidence covers, relative to the current directory (repeatable; default: whole repo)",
    )
    run.add_argument("command", nargs=argparse.REMAINDER, help="-- command to run")

    summary = sub.add_parser("summary", help="status, counts and evidence identity of one run")
    summary.add_argument("run", nargs="?", default="latest")
    summary.add_argument("--json", action="store_true")

    failures = sub.add_parser("failures", help="failure lines from a recorded log")
    failures.add_argument("run", nargs="?", default="latest")
    failures.add_argument("--limit", type=int, default=40)
    failures.add_argument("--json", action="store_true")

    reuse = sub.add_parser("reuse", help="is this run still valid evidence for the current worktree?")
    reuse.add_argument("run", nargs="?", default="latest")
    reuse.add_argument("--json", action="store_true")

    listing = sub.add_parser("list", help="recorded runs, newest first")
    listing.add_argument("--json", action="store_true")

    args = parser.parse_args(argv)
    if args.action == "run":
        command = list(args.command)
        if command and command[0] == "--":
            command = command[1:]
        if command and command[0] == "--":
            command = command[1:]
        args.command = command
        return command_run(args)
    if args.action == "summary":
        return command_summary(args)
    if args.action == "failures":
        return command_failures(args)
    if args.action == "reuse":
        return command_reuse(args)
    return command_list(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
