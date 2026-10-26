"""Builds, provenance, measurement runs and evidence capture."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from . import scenarios as samples
from .app import AppProcess, command, install_bundle, prepare_support, probe, set_defaults, write_session
from .common import (
    BASELINE_REF,
    BASELINE_WORKTREE,
    BUILD_FLAGS,
    LOG_DIR,
    REPO,
    SHOT_DIR,
    WORK,
    BenchError,
    footprint_bytes,
    git,
    log,
    mib,
    run,
    sha256_bytes,
    sha256_file,
    stats,
    tool_version,
    write_jsonl,
)


def _benchmark_block(path: Path, marker: str = "#if SPOTASK_BENCHMARK") -> str:
    text = path.read_text(encoding="utf-8")
    start = text.index(marker)
    end = text.index("#endif", start) + len("#endif")
    lines = text[start:end].splitlines()
    return "\n".join(line[4:] if line.startswith("    ") else line for line in lines)


def generate_baseline_patch(source: Path) -> str:
    """Adds the benchmark control channel to a checkout of the baseline commit.

    The baseline predates the math pipeline, so it gets the same control file
    with an empty cache-clear hook, the same view-model helpers as a file-local
    extension, and the install/teardown calls in the chat view.
    """
    control = REPO / "Sources/SpotAsk/Benchmark/BenchmarkControl.swift"
    target_control = source / "Sources/SpotAsk/Benchmark/BenchmarkControl.swift"
    target_control.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(control, target_control)

    view_model = source / "Sources/SpotAsk/Chat/ChatViewModel.swift"
    helpers = _benchmark_block(REPO / "Sources/SpotAsk/Chat/ChatViewModel.swift")
    view_model.write_text(
        view_model.read_text(encoding="utf-8")
        + "\n\nextension ChatViewModel {\n"
        + helpers
        + "\n}\n",
        encoding="utf-8",
    )

    chat_view = source / "Sources/SpotAsk/Rendering/ChatView.swift"
    text = chat_view.read_text(encoding="utf-8")
    text = text.replace(
        "        installShortcutDispatcher()\n",
        "        installShortcutDispatcher()\n"
        "        #if SPOTASK_BENCHMARK\n"
        "        BenchmarkControl.shared.install(viewModel: viewModel)\n"
        "        #endif\n",
        1,
    )
    text = text.replace(
        "        isPanelVisible = false\n",
        "        isPanelVisible = false\n"
        "        #if SPOTASK_BENCHMARK\n"
        "        BenchmarkControl.shared.uninstall()\n"
        "        #endif\n",
        1,
    )
    chat_view.write_text(text, encoding="utf-8")

    run(["git", "-C", str(source), "add", "-A"])
    return run(["git", "-C", str(source), "diff", "--cached"]).stdout


def prepare_source(target: str) -> Path:
    if target != "baseline":
        return REPO

    if BASELINE_WORKTREE.exists():
        run(["git", "-C", REPO, "worktree", "remove", "--force", str(BASELINE_WORKTREE)], check=False)
        shutil.rmtree(BASELINE_WORKTREE, ignore_errors=True)
    run(["git", "-C", REPO, "worktree", "add", "--detach", str(BASELINE_WORKTREE), BASELINE_REF])
    patch = generate_baseline_patch(BASELINE_WORKTREE)
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "baseline-control.patch").write_text(patch, encoding="utf-8")
    return BASELINE_WORKTREE


SOURCE_ROOTS = ["Sources", "Vendor", "Package.swift", "Package.resolved"]


def source_fingerprint(source: Path) -> tuple[str, int]:
    """Hash every file the build consumes, including untracked ones.

    `git diff HEAD` alone misses untracked files, and a reused scratch build only
    proves the installed copy matches the product on disk, not that the product
    was built from the current sources. Hashing the consumed files closes both
    gaps.
    """
    listing = run(
        ["git", "-C", str(source), "ls-files", "-z", "-co", "--exclude-standard", "--", *SOURCE_ROOTS],
        check=False,
    ).stdout
    entries = []
    for name in sorted(filter(None, listing.split("\0"))):
        path = source / name
        if path.is_file():
            entries.append(f"{name} {sha256_file(path)}")
    digest = sha256_bytes("\n".join(entries).encode("utf-8"))
    return digest, len(entries)


def build_target(target: str, source: Path) -> dict:
    scratch = WORK / "build" / target
    base_cmd = ["swift", "build", *BUILD_FLAGS, "--scratch-path", str(scratch)]

    # Always run the build: an incremental no-op build is cheap and proves the
    # product matches the current sources instead of an earlier checkout.
    log(f"[build] {target}: {' '.join(base_cmd)}")
    result = run(base_cmd, cwd=source, check=False)
    (LOG_DIR / f"build-{target}.log").parent.mkdir(parents=True, exist_ok=True)
    (LOG_DIR / f"build-{target}.log").write_text(
        (result.stdout or "") + (result.stderr or ""),
        encoding="utf-8",
    )
    if result.returncode != 0:
        raise BenchError(f"build failed for {target}; see logs/build-{target}.log")

    bin_path = run(base_cmd + ["--show-bin-path"], cwd=source).stdout.strip().splitlines()[-1]
    binary = Path(bin_path) / "SpotAsk"
    if not binary.exists():
        raise BenchError(f"missing product {binary}")

    fingerprint, file_count = source_fingerprint(source)
    status = git(source, "status", "--porcelain")
    diff = git(source, "diff", "HEAD")
    return {
        "target": target,
        "source": str(source),
        "head": git(source, "rev-parse", "HEAD"),
        "product": str(binary),
        "product_sha256": sha256_file(binary),
        "source_fingerprint": fingerprint,
        "source_files_hashed": file_count,
        "build_command": " ".join(base_cmd),
        "swift_version": tool_version("swift"),
        "dirty_entries": [line for line in status.splitlines() if line.strip()],
        "worktree_diff_sha256": sha256_bytes(diff.encode("utf-8")),
        "baseline_ref": BASELINE_REF if target == "baseline" else None,
        "baseline_patch_sha256": sha256_file(WORK / "baseline-control.patch")
        if target == "baseline"
        else None,
        "measured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


def installed_binary(binary: Path) -> tuple[Path, str]:
    executable = install_bundle(binary)
    return executable, sha256_file(executable)


def _default_settings(dark: bool) -> None:
    set_defaults(
        retainSession=True,
        appearance="dark" if dark else "light",
        confirmBeforeStartingNewConversation=False,
        streaming=True,
    )


def _reset_stats(out_dir: Path) -> None:
    command("resetStats", out_dir=out_dir, timeout=40)


def _read_stats(out_dir: Path) -> dict:
    try:
        data = command("stats", out_dir=out_dir, timeout=5)
    except BenchError:
        return {}
    data.pop("ok", None)
    return data


def _probe_scenario(target: str, app: AppProcess, scenario: dict, screenshot: Path | None):
    """Strict AX verification on the integrated build.

    The baseline build rasterises math paragraphs and exposes neither their text
    nor the formulas through accessibility (see ``run_ax_gap_probe``), so its
    math scenarios are verified by proving the assistant message container is
    rendered (via the "Copy full answer" action) and marked as container-only.
    Non-math scenarios on the baseline verify their preview text strictly.
    """
    if target == "baseline" and scenario.get("expect_formulas"):
        return (
            probe(
                app.pid,
                expect_texts=["Copy full answer"],
                timeout=40,
                screenshot=screenshot,
            ),
            None,
        )
    try:
        return (
            probe(
                app.pid,
                expect_texts=scenario["expect_texts"],
                expect_formulas=scenario["expect_formulas"],
                timeout=40,
                screenshot=screenshot,
            ),
            None,
        )
    except BenchError as error:
        # A failed run is only useful with the shape of the tree it failed on.
        try:
            tree = probe(app.pid, timeout=5, dump_tree=True)
            payload = dict(getattr(error, "payload", {}) or {})
            payload["tree"] = tree.get("tree")
            error.payload = payload
            if getattr(error, "dump", None):
                Path(error.dump).write_text(
                    json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8"
                )
        except BenchError:
            pass
        raise


def run_ax_gap_probe(target: str, executable: Path) -> dict:
    """Records what the accessibility tree exposes for a math message."""
    out_dir = WORK / "out" / target / "ax-gap"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    scenario = samples.single_math()
    write_session(scenario["messages"])
    _default_settings(False)

    app = AppProcess(executable, out_dir).launch()
    try:
        try:
            strict = probe(
                app.pid,
                expect_texts=scenario["expect_texts"],
                expect_formulas=scenario["expect_formulas"],
                timeout=40,
                screenshot=SHOT_DIR / f"DEV-672-{target}-ax-gap.png",
            )
            return {"target": target, "strict_ok": True, "texts": strict.get("texts", [])}
        except BenchError as exc:
            payload = getattr(exc, "payload", {}) or {}
            return {
                "target": target,
                "strict_ok": False,
                "texts": payload.get("texts", []),
                "formulas": payload.get("formulas", []),
                "failed_checks": [
                    check for check in payload.get("checks", []) if not check.get("ok")
                ],
                "dump": getattr(exc, "dump", None),
            }
    finally:
        app.terminate()


def run_scenario(
    target: str,
    executable: Path,
    scenario: dict,
    repeat: int,
    *,
    dark: bool = False,
    screenshot: Path | None = None,
) -> dict:
    out_dir = WORK / "out" / target / scenario["name"] / f"r{repeat}"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session(scenario["messages"])
    _default_settings(dark)

    app = AppProcess(executable, out_dir).launch()
    record = {
        "target": target,
        "scenario": scenario["name"],
        "repeat": repeat,
        "dark": dark,
        "sample": scenario["sample"],
        "pid": app.pid,
    }
    try:
        _reset_stats(out_dir)
        probe_started = time.monotonic()
        result, strict_failure = _probe_scenario(target, app, scenario, screenshot)
        offset_ms = (probe_started - app.started_at) * 1000
        timeline = result.get("timeline", {})
        record["timings_ms"] = {
            "window": round(offset_ms + (timeline.get("windowMs") or 0), 1),
            "content": round(offset_ms + (timeline.get("contentMs") or 0), 1),
            "formula": round(offset_ms + (timeline.get("formulaMs") or 0), 1)
            if timeline.get("formulaMs") is not None
            else None,
            "ready_total": round(app.elapsed_ms(), 1),
            "ax_snapshot": result.get("axSnapshotMs"),
        }
        record["ax"] = {
            "checks": result.get("checks", []),
            "formulas_visible": result.get("formulas", []),
            "window_count": result.get("windowCount"),
        }
        if strict_failure:
            record["ax"]["strict_failure"] = strict_failure
        # The container-only build exposes no answer text, so expanding it would
        # time out on every attempt and report a meaningless latency.
        if scenario.get("expanded_expect_texts") and not strict_failure and target != "baseline":
            expanded_started = time.monotonic()
            expected = scenario["expanded_expect_texts"]
            expanded = None
            attempts = 0
            while attempts < 3:
                attempts += 1
                state = probe(app.pid, timeout=15)
                joined = "\n".join(state.get("texts", []))
                if all(item in joined for item in expected):
                    expanded = state
                    break
                if "Show full answer" in joined:
                    probe(app.pid, click_text="Show full answer", timeout=15)
                    continue
                break
            if expanded is None:
                try:
                    expanded = probe(
                        app.pid,
                        expect_texts=expected,
                        timeout=30,
                        screenshot=SHOT_DIR / f"{target}-{scenario['name']}-expanded.png",
                    )
                except BenchError as exc:
                    payload = getattr(exc, "payload", {}) or {}
                    texts = payload.get("texts", [])
                    # Some rendering paths drop the answer body from the AX tree
                    # once the message is expanded. Record it instead of hiding it.
                    if not any(len(text) > 200 for text in texts):
                        record["expanded_text_exposed"] = False
                        record["expansion_note"] = (
                            "expanded message exposes no AX text in this target; "
                            "visual evidence only"
                        )
                    else:
                        raise
            record["timings_ms"]["expanded_content"] = round(
                (time.monotonic() - expanded_started) * 1000, 1
            )
            record["expansion_attempts"] = attempts
            record["expanded_text_exposed"] = expanded is not None
            record["ax"]["expanded_checks"] = (expanded or {}).get("checks", [])

        record["footprint_bytes_ready"] = footprint_bytes(app.pid)
        time.sleep(2.0)
        record["footprint_bytes_settled"] = footprint_bytes(app.pid)
        record["rss_peak_bytes"] = app.rss_peak
        record["stalls"] = _read_stats(out_dir)
        record["ok"] = True
        return record
    finally:
        app.terminate()
        record["footprint_mib_ready"] = mib(record.get("footprint_bytes_ready"))
        record["footprint_mib_settled"] = mib(record.get("footprint_bytes_settled"))
        record["rss_peak_mib"] = mib(record.get("rss_peak_bytes"))


def run_layout_checks(target: str, executable: Path) -> dict:
    """Narrow-window scroll + copy affordance on the wide display formula."""
    out_dir = WORK / "out" / target / "layout"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session(samples.wide_math()["messages"])
    _default_settings(False)

    before = SHOT_DIR / f"DEV-672-{target}-narrow-before.png"
    after = SHOT_DIR / f"DEV-672-{target}-narrow-after.png"

    app = AppProcess(executable, out_dir).launch()
    try:
        probe(app.pid, expect_formulas=[samples.WIDE_TEX], timeout=40)
        probe(
            app.pid,
            expect_formulas=[samples.WIDE_TEX],
            window_size=(460, 760),
            screenshot=before,
            timeout=20,
        )
        scrolled = probe(app.pid, screenshot=after, scroll_horizontal=-260, timeout=20)
        scroll_check = next(
            (check for check in scrolled["checks"] if check["name"] == "scroll-horizontal"),
            None,
        )
        if not scroll_check or not scroll_check["ok"]:
            raise BenchError(f"horizontal scrolling check failed: {scroll_check}")
        if not images_differ(before, after):
            raise BenchError("horizontal scrolling did not change the rendered pixels")
        return {
            "target": target,
            "scroll": scroll_check["detail"],
            "windowWidthPt": 460,
            "before": str(before.relative_to(REPO)),
            "after": str(after.relative_to(REPO)),
        }
    finally:
        app.terminate()


def images_differ(first: Path, second: Path, threshold: float = 0.5) -> bool:
    from PIL import Image, ImageChops, ImageStat

    with Image.open(first) as a, Image.open(second) as b:
        if a.size != b.size:
            return True
        diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
        mean = sum(ImageStat.Stat(diff).mean) / 3
        return mean > threshold


def mean_luminance(path: Path) -> float:
    from PIL import Image

    with Image.open(path) as image:
        grey = image.convert("L")
        histogram = grey.histogram()
    total = sum(histogram)
    weighted = sum(index * count for index, count in enumerate(histogram))
    return weighted / total / 255


def run_streaming(target: str, executable: Path) -> dict:
    out_dir = WORK / "out" / target / "streaming"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session([])
    _default_settings(False)

    mid_stream_shot = SHOT_DIR / f"DEV-672-{target}-streaming-mid.png"
    final_shot = SHOT_DIR / f"DEV-672-{target}-streaming-final.png"

    app = AppProcess(executable, out_dir).launch()
    record = {"target": target, "chunks": len(samples.STREAM_CHUNKS)}
    try:
        _reset_stats(out_dir)
        probe(app.pid, timeout=30)
        command(
            "replay",
            {
                "question": "Stream replay question marker ST-ASK.",
                "chunks": samples.STREAM_CHUNKS,
                "intervalMs": 60,
            },
            out_dir=out_dir,
            timeout=20,
        )
        partial = probe(
            app.pid,
            expect_texts=["Stream start marker ST-BEGIN"],
            absent_texts=["replayed stream complete"],
            timeout=20,
            screenshot=mid_stream_shot,
        )
        record["partial_visible_ms"] = partial.get("timeline", {}).get("contentMs")
        final = probe(
            app.pid,
            expect_texts=[
                "ST-END",
                "Stream start marker ST-BEGIN",
                "The identity " + samples.OBJECT_REPLACEMENT + " arrives while the answer is still streaming.",
            ],
            expect_formulas=[r"\sum_{k=1}^{n} k"],
            timeout=40,
            screenshot=final_shot,
        )
        record["final_ready_ms"] = (time.monotonic() - app.started_at) * 1000
        record["formulas_visible"] = final.get("formulas", [])
        record["stalls"] = _read_stats(out_dir)
        record["footprint_mib"] = mib(footprint_bytes(app.pid))
        record["rss_peak_mib"] = mib(app.rss_peak)
        record["ok"] = True
        return record
    finally:
        app.terminate()


def _stable_texts(pid: int, *, settle: float = 2.0, timeout: float = 20.0) -> tuple[str, str]:
    """Returns the visible text twice, `settle` seconds apart, to prove a terminal state."""
    first = probe(pid, timeout=timeout)
    time.sleep(settle)
    second = probe(pid, timeout=timeout)
    return (
        "\n".join(first.get("texts", [])),
        "\n".join(second.get("texts", [])),
    )


STOP_BUTTONS = ("Stop generating", "Stop", "停止生成")
RETRY_BUTTONS = ("Retry the most recent failed request", "Retry", "Regenerate answer")


def _first_present(texts, candidates) -> str | None:
    joined = "\n".join(texts)
    for candidate in candidates:
        if candidate in joined:
            return candidate
    return None


def run_cancel(target: str, executable: Path) -> dict:
    out_dir = WORK / "out" / target / "cancel"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session([])
    _default_settings(False)

    chunks = [f"Cancel chunk {index} text. " for index in range(1, 40)]
    chunks[0] = "Cancel start marker CN-BEGIN. "
    snapshot = SHOT_DIR / f"DEV-672-{target}-cancelled.png"

    app = AppProcess(executable, out_dir).launch()
    record = {"target": target}
    try:
        probe(app.pid, timeout=30)
        command(
            "replay",
            {"question": "Cancel probe question.", "chunks": chunks, "intervalMs": 140},
            out_dir=out_dir,
            timeout=20,
        )
        probe(app.pid, expect_texts=["Cancel start marker CN-BEGIN"], timeout=20)
        probe(app.pid, click_text="Stop generating", screenshot=snapshot, timeout=20)

        before, after = _stable_texts(app.pid)
        record["terminal_stable"] = before == after
        if not record["terminal_stable"]:
            raise BenchError("cancelled answer kept changing after the stop")
        if "Cancel chunk 39 text." in after:
            raise BenchError("cancelled answer still received the final chunk")
        if _first_present([after], STOP_BUTTONS):
            raise BenchError("streaming affordance is still visible after cancelling")

        if "Generation stopped" not in after and "已停止生成" not in after:
            raise BenchError("cancelled message does not report a stopped state")

        # A cancelled message exposes no retry entry by design; record that and
        # prove instead that the app still accepts a new generation.
        record["retry_entry"] = _first_present([after], RETRY_BUTTONS)
        record["regenerate_available_after_cancel"] = record["retry_entry"] is not None

        command(
            "replay",
            {
                "question": "Follow-up after cancelling.",
                "chunks": ["Follow-up marker FU-BEGIN. ", "Follow-up marker FU-END. "],
                "intervalMs": 30,
            },
            out_dir=out_dir,
            timeout=20,
        )
        follow_up = probe(
            app.pid,
            expect_texts=["Follow-up marker FU-END."],
            timeout=30,
        )
        record["follow_up_checks"] = follow_up.get("checks", [])
        record["checks"] = [
            {"name": "terminal_stable", "ok": True, "detail": "identical after 2 s"},
            {"name": "stopped_state", "ok": True, "detail": "Generation stopped"},
            {"name": "follow_up_generation", "ok": True, "detail": "second answer completed"},
        ]
        record["stalls"] = _read_stats(out_dir)
        record["ok"] = True
        return record
    finally:
        app.terminate()


def run_failure(target: str, executable: Path) -> dict:
    out_dir = WORK / "out" / target / "failure"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session([])
    _default_settings(False)

    snapshot = SHOT_DIR / f"DEV-672-{target}-failed.png"

    app = AppProcess(executable, out_dir).launch()
    record = {"target": target}
    try:
        probe(app.pid, timeout=30)
        command("fail", {"question": "Failure probe question."}, out_dir=out_dir, timeout=20)

        failed = probe(
            app.pid,
            expect_texts=[
                "Partial answer before the failure.",
                "The service returned an invalid response.",
            ],
            timeout=20,
            screenshot=snapshot,
        )
        record["checks"] = failed.get("checks", [])

        before, after = _stable_texts(app.pid)
        record["terminal_stable"] = before == after
        if not record["terminal_stable"]:
            raise BenchError("failed answer kept changing")
        if _first_present([after], STOP_BUTTONS):
            raise BenchError("streaming affordance is still visible after a failure")

        retry = _first_present([after], RETRY_BUTTONS)
        record["retry_entry"] = retry
        if not retry:
            raise BenchError("no retry entry after a failure")

        probe(app.pid, click_text=retry, timeout=20)
        retry_before, retry_after = _stable_texts(app.pid)
        record["retry_terminal_stable"] = retry_before == retry_after
        if not record["retry_terminal_stable"]:
            raise BenchError("retry never reached a terminal state")
        record["retry_error_surface"] = [
            text
            for text in retry_after.splitlines()
            if "access key" in text.lower() or "invalid response" in text.lower()
        ]
        if not record["retry_error_surface"]:
            raise BenchError("retry produced no defined error surface")
        record["stalls"] = _read_stats(out_dir)
        record["ok"] = True
        return record
    finally:
        app.terminate()


def drag_and_copy(
    app: AppProcess,
    start: str,
    end: str,
    *,
    attempts: int = 3,
    timeout: float = 25,
    screenshot: Path | None = None,
) -> dict:
    """Drags between two visible texts and copies the selection.

    Synthetic drags are timing sensitive: a press/drag pair can miss the glyph
    run it was aimed at and leave the clipboard empty. Retrying is recorded so
    the report shows how many attempts a measurement needed.
    """
    last: BenchError | None = None
    for attempt in range(1, attempts + 1):
        try:
            result = probe(
                app.pid,
                drag_from=start,
                drag_to=end,
                copy_selection=True,
                timeout=timeout,
                screenshot=screenshot,
            )
            result["attempts"] = attempt
            return result
        except BenchError as error:
            last = error
            if "clipboard is empty" not in str(error):
                raise
            log(f"[selection] drag {start!r}..{end!r} missed; retrying")
            time.sleep(0.4)
    raise last if last else BenchError("drag and copy failed")


def run_selection_evidence(target: str, executable: Path) -> dict:
    """Measures what a drag selection and the clipboard actually contain.

    Textual draws attachments into a `Canvas` and gives every `StructuredText`
    its own selection model, so a body split around a display block is expected
    to clamp a drag at the block boundary. These runs record the real content
    instead of assuming either behaviour.
    """
    out_dir = WORK / "out" / target / "selection"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    scenario = samples.selection_message()
    write_session(scenario["messages"])
    _default_settings(False)

    app = AppProcess(executable, out_dir).launch()
    record: dict = {"target": target}
    try:
        probe(app.pid, expect_formulas=[samples.SELECTION_MATH], timeout=40)

        crossing = drag_and_copy(
            app,
            "Selection start marker",
            "Selection end marker",
            screenshot=SHOT_DIR / f"DEV-672-{target}-selection-cross.png",
        )
        record["cross_block_clipboard"] = crossing.get("clipboard")
        record["cross_block_includes_after_text"] = (
            "OMEGA" in (crossing.get("clipboard") or "")
        )

        inside = drag_and_copy(app, "Selection start marker", "before the formula")
        record["single_block_clipboard"] = inside.get("clipboard")

        # A selection must survive the answer growing underneath it, which is
        # what a streaming update does to the message being read.
        drag_and_copy(app, "Selection start marker", "before the formula")
        grown = [dict(message) for message in scenario["messages"]]
        grown[-1] = dict(
            grown[-1],
            content=grown[-1]["content"] + " Appended sentence after growth.",
        )
        write_session(grown)
        command("reload", out_dir=out_dir, timeout=30)
        probe(app.pid, expect_texts=["Appended sentence after growth."], timeout=30)
        time.sleep(0.6)
        try:
            after_growth = probe(app.pid, copy_selection=True, timeout=20)
            record["clipboard_after_growth"] = after_growth.get("clipboard")
        except BenchError as error:
            if "clipboard is empty" not in str(error):
                raise
            record["clipboard_after_growth"] = ""
        # Recorded, not asserted: replacing the parsed text run while the answer
        # grows may legitimately drop a live selection, and the harness cannot
        # force Textual to keep it. The report states what was observed.
        record["selection_survived_growth"] = (
            record["clipboard_after_growth"] == inside.get("clipboard")
        )
        return record
    finally:
        app.terminate()


def run_link_evidence(target: str, executable: Path) -> dict:
    """A reference definition behind a display block must still resolve."""
    out_dir = WORK / "out" / target / "link"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session(samples.link_message()["messages"])
    _default_settings(False)

    app = AppProcess(executable, out_dir).launch()
    record: dict = {"target": target}
    try:
        probe(app.pid, expect_formulas=["x^2 + y^2 = z^2"], timeout=40)
        copied = drag_and_copy(app, "Read", samples.LINK_DRAG_END)
        record["clipboard"] = copied.get("clipboard")
        record["link_resolved"] = samples.LINK_EXPECTED in (copied.get("clipboard") or "")
        if not record["link_resolved"]:
            raise BenchError(
                f"reference link did not resolve across a display block: {record['clipboard']!r}"
            )
        return record
    finally:
        app.terminate()


def run_stall_probes(target: str, executable: Path) -> dict:
    """Measures main-thread timer drift while the app is used, not only at rest."""
    out_dir = WORK / "out" / target / "stalls"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session(samples.heavy_math()["messages"])
    _default_settings(False)

    app = AppProcess(executable, out_dir).launch()
    record: dict = {"target": target}
    try:
        probe(app.pid, expect_formulas=[samples.heavy_math()["expect_formulas"][0]], timeout=60)

        command("resetStats", out_dir=out_dir, timeout=30)
        probe(app.pid, scroll_vertical=-600, timeout=20)
        probe(app.pid, scroll_vertical=600, timeout=20)
        record["scroll_stalls"] = _read_stats(out_dir)

        command("resetStats", out_dir=out_dir, timeout=30)
        command(
            "replay",
            {
                "question": "Streaming next to fifty formulas.",
                "chunks": samples.STREAM_CHUNKS,
                "intervalMs": 40,
            },
            out_dir=out_dir,
            timeout=20,
        )
        probe(app.pid, expect_texts=["ST-END"], timeout=40)
        record["streaming_stalls"] = _read_stats(out_dir)
        record["footprint_mib"] = mib(footprint_bytes(app.pid))
        return record
    finally:
        app.terminate()


def run_lifecycle(target: str, executable: Path, cycles: int = 30) -> dict:
    out_dir = WORK / "out" / target / "lifecycle"
    shutil.rmtree(out_dir, ignore_errors=True)
    prepare_support()
    write_session([])
    _default_settings(False)

    app = AppProcess(executable, out_dir).launch()
    rows = []
    try:
        probe(app.pid, timeout=30)
        for cycle in range(1, cycles + 1):
            sample = samples.lifecycle_messages(cycle)
            write_session(sample["messages"])
            ack = command("reload", out_dir=out_dir, timeout=30)
            absent = []
            if cycle > 1:
                absent = [f"Cycle {cycle - 1} user question marker"]
            expected_texts = [
                f"Cycle {cycle} user question marker",
                f"Cycle {cycle} answer marker",
                f"Cycle {cycle} closing marker",
            ]
            expected_formulas = [sample["tex_fragment"]]
            if target == "baseline":
                # The baseline exposes neither math paragraphs nor formulas to AX.
                expected_texts = ["Copy full answer"]
                expected_formulas = []
            result = probe(
                app.pid,
                expect_texts=expected_texts,
                expect_formulas=expected_formulas,
                absent_texts=absent,
                timeout=30,
            )
            row = {
                "target": target,
                "cycle": cycle,
                "messageCount": ack.get("messageCount"),
                "sessionIdentity": ack.get("sessionIdentity"),
                "footprint_mib": mib(footprint_bytes(app.pid)),
                "timeline": result.get("timeline"),
                "checks": result.get("checks", []),
            }
            rows.append(row)
            log(f"    cycle {cycle:02d} ok footprint={row['footprint_mib']} MiB")

        cleared = command("newConversation", out_dir=out_dir, timeout=20)
        if cleared.get("messageCount") != 0:
            raise BenchError(f"new conversation left {cleared.get('messageCount')} messages")
        probe(app.pid, absent_texts=[f"Cycle {cycles} user question marker"], timeout=20)

        cleared_cache = command("clearCache", out_dir=out_dir, timeout=20)
        if not cleared_cache.get("cleared"):
            raise BenchError("cache clear was not acknowledged as complete")
        time.sleep(2.0)
        reclaimed = mib(footprint_bytes(app.pid))

        # Cache was cleared; a reload must rebuild every formula.
        sample = samples.lifecycle_messages(cycles)
        write_session(sample["messages"])
        command("reload", out_dir=out_dir, timeout=30)
        if target == "baseline":
            probe(app.pid, expect_texts=["Copy full answer"], timeout=30)
        else:
            probe(
                app.pid,
                expect_texts=[f"Cycle {cycles} answer marker"],
                expect_formulas=[sample["tex_fragment"]],
                timeout=30,
            )
        rerendered = mib(footprint_bytes(app.pid))

        return {
            "target": target,
            "cycles": rows,
            "post_reclaim_mib": reclaimed,
            "post_rerender_mib": rerendered,
            "ax_scope": "container-only (baseline rasterises math paragraphs)"
            if target == "baseline"
            else "strict",
            "stalls": _read_stats(out_dir),
            "rss_peak_mib": mib(app.rss_peak),
            "ok": True,
        }
    finally:
        app.terminate()
