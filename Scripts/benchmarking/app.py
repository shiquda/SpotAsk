"""Isolated app bundle, session seeding, launching and the control channel."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
import uuid
from pathlib import Path

from .common import (
    APP_BUNDLE,
    BUNDLE_ID,
    LOG_DIR,
    BenchError,
    PROBE,
    SUPPORT,
    log,
    run,
    rss_bytes,
)

BENCHMARK_TIMEOUT = 25.0

INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>{bundle_id}</string>
  <key>CFBundleExecutable</key><string>SpotAsk</string>
  <key>CFBundleName</key><string>SpotAskBenchmark</string>
  <key>CFBundleDisplayName</key><string>SpotAskBenchmark</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.0</string>
  <key>CFBundleVersion</key><string>0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
"""


def install_bundle(binary: Path) -> Path:
    """Copies a built binary into a dedicated benchmark bundle; returns the copy."""
    if APP_BUNDLE.exists():
        shutil.rmtree(APP_BUNDLE)
    contents = APP_BUNDLE / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    frameworks = contents / "Frameworks"
    for directory in (macos, resources, frameworks):
        directory.mkdir(parents=True, exist_ok=True)

    (contents / "Info.plist").write_text(INFO_PLIST.format(bundle_id=BUNDLE_ID), encoding="utf-8")
    executable = macos / "SpotAsk"
    shutil.copyfile(binary, executable)
    executable.chmod(0o755)

    for bundle in sorted(binary.parent.glob("*.bundle")):
        for target in (resources, macos):
            destination = target / bundle.name
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(bundle, destination)

    sparkle = binary.parent / "ExecutableModules" / "Sparkle.framework"
    if sparkle.exists():
        shutil.copytree(sparkle, frameworks / "Sparkle.framework", symlinks=True)
    else:
        for candidate in binary.parent.glob("**/Sparkle.framework"):
            shutil.copytree(candidate, frameworks / "Sparkle.framework", symlinks=True)
            break

    return executable


def terminate_stray_benchmark_apps() -> None:
    """Kills leftover copies of the benchmark bundle only (never the user's app)."""
    run(["pkill", "-f", str(APP_BUNDLE / "Contents/MacOS/SpotAsk")], check=False)
    time.sleep(0.3)


def warm_up(executable: Path, out_dir: Path) -> None:
    """First launch after copying a fresh binary can be slow (LaunchServices,
    code-signing verification). Pay that cost once, before measurements."""
    terminate_stray_benchmark_apps()
    prepare_support()
    write_session([])
    app = AppProcess(executable, out_dir).launch()
    try:
        probe(app.pid, timeout=90)
    finally:
        app.terminate()


def prepare_support() -> None:
    terminate_stray_benchmark_apps()
    shutil.rmtree(SUPPORT, ignore_errors=True)
    SUPPORT.mkdir(parents=True, exist_ok=True)


def write_session(messages) -> None:
    SUPPORT.mkdir(parents=True, exist_ok=True)
    (SUPPORT / "current-session.json").write_text(
        json.dumps(messages, ensure_ascii=False),
        encoding="utf-8",
    )


def set_defaults(**values) -> None:
    for key, value in values.items():
        if isinstance(value, bool):
            run(["defaults", "write", BUNDLE_ID, key, "-bool", "true" if value else "false"])
        elif isinstance(value, (int, float)):
            run(["defaults", "write", BUNDLE_ID, key, "-float", str(value)])
        else:
            run(["defaults", "write", BUNDLE_ID, key, "-string", str(value)])


class AppProcess:
    def __init__(self, executable: Path, out_dir: Path):
        self.executable = executable
        self.out_dir = out_dir
        self.process = None
        self.pid = None
        self.started_at = None
        self._rss_samples = []
        self._sampling = False
        self._sampler = None

    def launch(self) -> "AppProcess":
        out_dir = self.out_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        env["SPOTASK_BENCHMARK_OUT"] = str(out_dir)
        env["DYLD_FRAMEWORK_PATH"] = str(APP_BUNDLE / "Contents" / "Frameworks")
        self.started_at = time.monotonic()
        self.log_handle = open(out_dir / "app.log", "ab")
        self.process = subprocess.Popen(
            [str(self.executable)],
            env=env,
            stdout=self.log_handle,
            stderr=self.log_handle,
        )
        self.pid = self.process.pid
        self._sampling = True
        self._sampler = threading.Thread(target=self._sample_rss, daemon=True)
        self._sampler.start()
        return self

    def _sample_rss(self) -> None:
        while self._sampling:
            value = rss_bytes(self.pid)
            if value:
                self._rss_samples.append(value)
            time.sleep(0.2)

    @property
    def rss_peak(self):
        return max(self._rss_samples) if self._rss_samples else None

    def elapsed_ms(self) -> float:
        return (time.monotonic() - self.started_at) * 1000

    def terminate(self) -> None:
        self._sampling = False
        if self._sampler:
            self._sampler.join(timeout=2)
        if not self.process:
            return
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.process = None


def probe(
    pid: int,
    *,
    expect_texts=(),
    absent_texts=(),
    expect_formulas=(),
    absent_formulas=(),
    timeout: float = BENCHMARK_TIMEOUT,
    screenshot: Path | None = None,
    window_size=None,
    click_new_conversation: bool = False,
    click_text: str | None = None,
    drag_from: str | None = None,
    drag_to: str | None = None,
    copy_selection: bool = False,
    scroll_vertical: int | None = None,
    scroll_horizontal: int | None = None,
    dump_tree: bool = False,
) -> dict:
    """Runs the AX probe; raises when any expectation fails."""
    cmd = [PROBE, str(pid), "--timeout", str(timeout)]
    for text in expect_texts:
        cmd += ["--expect-text", text]
    for text in absent_texts:
        cmd += ["--absent-text", text]
    for formula in expect_formulas:
        cmd += ["--expect-formula", formula]
    for formula in absent_formulas:
        cmd += ["--absent-formula", formula]
    if click_new_conversation:
        cmd.append("--click-new-conversation")
    if click_text:
        cmd += ["--click-text", click_text]
    if drag_from and drag_to:
        cmd += ["--drag-text", drag_from, drag_to]
    if copy_selection:
        cmd.append("--copy-selection")
    if scroll_vertical:
        cmd += ["--scroll-vertical", str(scroll_vertical)]
    if window_size:
        cmd += ["--set-window-size", str(window_size[0]), str(window_size[1])]
    if scroll_horizontal:
        cmd += ["--scroll-horizontal", str(scroll_horizontal)]
    if screenshot:
        screenshot.parent.mkdir(parents=True, exist_ok=True)
        cmd += ["--screenshot", str(screenshot)]
    if dump_tree:
        cmd.append("--dump-tree")

    started = time.monotonic()
    result = run(cmd, check=False)
    wall_ms = (time.monotonic() - started) * 1000
    payload = {}
    if result.stdout.strip():
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            payload = {"ok": False, "error": result.stdout[:400]}
    payload["probeWallMs"] = round(wall_ms, 1)
    payload["probeExitCode"] = result.returncode
    if result.returncode != 0 or not payload.get("ok"):
        failed = [check for check in payload.get("checks", []) if not check.get("ok")]
        failure_dir = LOG_DIR / "probe-failures"
        failure_dir.mkdir(parents=True, exist_ok=True)
        dump = failure_dir / f"probe-{time.time():.0f}-{uuid.uuid4().hex[:6]}.json"
        dump.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
        error = BenchError(
            "accessibility verification failed:\n"
            + json.dumps(
                {
                    "failed": failed or payload,
                    "windows": payload.get("windowCount"),
                    "texts": payload.get("texts", [])[:10],
                    "formulas": payload.get("formulas", [])[:5],
                    "error": payload.get("error"),
                    "dump": str(dump),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        error.payload = payload
        error.dump = str(dump)
        raise error
    return payload


IDEMPOTENT_COMMANDS = {"reload", "resetStats", "stats", "clearCache", "newConversation"}


def command(
    action: str,
    payload: dict | None = None,
    *,
    out_dir: Path,
    timeout: float = 30.0,
    attempts: int = 2,
) -> dict:
    """Sends a benchmark command and waits for the app's acknowledgement file.

    The app polls the output directory, so a dropped post is not a failure mode;
    a retry with a fresh request id covers a delayed file-system notification
    only. The number of attempts is reported instead of being hidden.
    """
    tries = attempts if action in IDEMPOTENT_COMMANDS else 1
    last_error: BenchError | None = None
    for attempt in range(1, tries + 1):
        try:
            data = _command_once(action, payload, out_dir=out_dir, timeout=timeout)
            if attempt > 1:
                log(f"[command] {action} needed {attempt} attempts")
            data["attempts"] = attempt
            return data
        except BenchError as error:
            last_error = error
            if attempt == tries or "no acknowledgement" not in str(error):
                raise
            log(f"[command] {action} timed out; retrying once")
    raise last_error if last_error else BenchError(f"benchmark command {action} failed")


def _command_once(
    action: str,
    payload: dict | None,
    *,
    out_dir: Path,
    timeout: float,
) -> dict:
    request_id = f"{action}-{uuid.uuid4().hex[:10]}"
    out_dir.mkdir(parents=True, exist_ok=True)
    request_path = out_dir / f"{request_id}.request.json"
    ack_path = out_dir / f"{request_id}.json"
    request_path.write_text(
        json.dumps({"action": action, "payload": payload or {}}, ensure_ascii=False),
        encoding="utf-8",
    )
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if ack_path.exists():
            try:
                data = json.loads(ack_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                time.sleep(0.05)
                continue
            ack_path.unlink(missing_ok=True)
            request_path.unlink(missing_ok=True)
            if not data.get("ok"):
                raise BenchError(f"benchmark command {action} failed: {data}")
            return data
        time.sleep(0.05)
    request_path.unlink(missing_ok=True)
    raise BenchError(f"no acknowledgement for benchmark command {action}")



