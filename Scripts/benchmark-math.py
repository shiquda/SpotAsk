#!/usr/bin/env python3
"""Math rendering benchmark for SpotAsk.

Drives isolated benchmark builds of the app (bundle id ``com.spotask.benchmark``
with its own Application Support directory and defaults domain), verifies every
scenario through the accessibility tree, aborts on any failed check, and records
binary provenance next to the raw measurements.

Examples:
    python3 Scripts/benchmark-math.py --build --targets integrated baseline
    python3 Scripts/benchmark-math.py --targets integrated --skip-lifecycle
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import statistics
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from benchmarking import scenarios as samples
from benchmarking.app import warm_up
from benchmarking.common import (
    LOG_DIR,
    OUT_DIR,
    REPO,
    SHOT_DIR,
    WORK,
    BenchError,
    clean_support,
    cleanup_work,
    ensure_dirs,
    log,
    mib,
    sha256_file,
    stats,
    write_jsonl,
)
from benchmarking.measure import (
    build_target,
    installed_binary,
    mean_luminance,
    prepare_source,
    run_ax_gap_probe,
    run_cancel,
    run_failure,
    run_lifecycle,
    run_layout_checks,
    run_link_evidence,
    run_scenario,
    run_selection_evidence,
    run_stall_probes,
    run_streaming,
)
from benchmarking.report import write_report


def parse_args():
    parser = argparse.ArgumentParser(description="SpotAsk math benchmark")
    parser.add_argument("--targets", nargs="+", default=["integrated"], choices=["integrated", "baseline"])
    parser.add_argument("--scenarios", nargs="+", default=list(samples.MEASURED_SCENARIOS))
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--cycles", type=int, default=30)
    parser.add_argument("--build", action="store_true", help="rebuild even when the scratch path exists")
    parser.add_argument("--skip-build", action="store_true", help="reuse an existing build")
    parser.add_argument("--skip-lifecycle", action="store_true")
    parser.add_argument("--skip-evidence", action="store_true")
    parser.add_argument("--keep-work", action="store_true")
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="rebuild the markdown from the logs already on disk, without measuring",
    )
    parser.add_argument("--report", default=str(OUT_DIR / "benchmark-report.md"))
    return parser.parse_args()


def screenshot_metadata(paths) -> list:
    from PIL import Image

    rows = []
    for path in paths:
        if not path.exists():
            continue
        with Image.open(path) as image:
            width, height = image.size
        rows.append(
            {
                "path": str(path.relative_to(REPO)),
                "width": width,
                "height": height,
                "mean_luminance": mean_luminance(path),
                "sha256": sha256_file(path),
            }
        )
    return rows


def read_logs(scenario_names):
    """Rebuilds the report payload from the logs a completed run left behind."""
    provenance = json.loads((LOG_DIR / "provenance.json").read_text(encoding="utf-8"))
    scenarios = {}
    for name in scenario_names:
        path = LOG_DIR / f"scenarios-{name}.jsonl"
        if not path.exists():
            continue
        scenarios[name] = [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    lifecycle = {}
    summary = LOG_DIR / "lifecycle-summary.json"
    if summary.exists():
        lifecycle = json.loads(summary.read_text(encoding="utf-8"))
    path = LOG_DIR / "lifecycle.jsonl"
    if path.exists():
        cycles = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            cycles.setdefault(row["target"], []).append(row)
        for target, rows in cycles.items():
            lifecycle.setdefault(target, {})["cycles"] = rows
    evidence = {}
    path = LOG_DIR / "evidence.jsonl"
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            kind = row.pop("kind")
            evidence[kind] = row
    return provenance, scenarios, lifecycle, evidence


def build_payload(scenario_results, lifecycle, evidence, provenance, screenshots, args, gaps):
    costs = []
    for scenario_name, entries in scenario_results.items():
        integrated = [row for row in entries if row["target"] == "integrated"]
        baseline = [row for row in entries if row["target"] == "baseline"]
        if not integrated or not baseline:
            continue
        integrated_median = statistics.median(
            row["footprint_mib_settled"] for row in integrated
        )
        baseline_median = statistics.median(row["footprint_mib_settled"] for row in baseline)
        costs.append(
            {
                "scenario": scenario_name,
                "baseline_mib": baseline_median,
                "integrated_mib": integrated_median,
                "delta_mib": integrated_median - baseline_median,
                "delta_percent": (integrated_median - baseline_median) / baseline_median * 100
                if baseline_median
                else None,
            }
        )

    stall_contexts = {}
    stall_evidence = evidence.get("integrated/stalls") or {}
    stall_contexts["fifty formulas: vertical scrolling"] = stall_evidence.get("scroll_stalls")
    stall_contexts["fifty formulas: streaming"] = stall_evidence.get("streaming_stalls")
    for scenario_name, entries in scenario_results.items():
        records = [row for row in entries if row["target"] == "integrated"]
        drifts = [
            (row.get("stalls") or {}).get("maxDriftMs")
            for row in records
            if (row.get("stalls") or {}).get("maxDriftMs") is not None
        ]
        if drifts:
            stall_contexts[f"{scenario_name}: content ready"] = {
                "maxDriftMs": max(drifts),
                "over50ms": sum(
                    (row.get("stalls") or {}).get("over50ms", 0) for row in records
                ),
                "samples": sum((row.get("stalls") or {}).get("samples", 0) for row in records),
            }

    return {
        "provenance": provenance,
        "scenarios": scenario_results,
        "samples": {name: samples.SCENARIOS[name]()["sample"] for name in scenario_results},
        "lifecycle": lifecycle,
        "evidence": evidence,
        "screenshots": screenshots,
        "costs": costs,
        "stall_contexts": stall_contexts,
        "selection": evidence.get("integrated/selection"),
        "gaps": gaps,
    }


def main() -> int:
    args = parse_args()
    ensure_dirs()
    if args.report_only:
        provenance, scenario_results, lifecycle, evidence = read_logs(args.scenarios)
        payload = build_payload(
            scenario_results,
            lifecycle,
            evidence,
            provenance,
            screenshot_metadata(sorted(SHOT_DIR.glob("DEV-672-*.png"))),
            args,
            ["report rebuilt from the logs on disk; the caveats of the measured run apply"],
        )
        write_report(Path(args.report), payload)
        log(f"[done] report: {args.report}")
        return 0
    clean_support()
    for target in args.targets:
        shutil.rmtree(WORK / "out" / target, ignore_errors=True)
    for stale in SHOT_DIR.glob("DEV-672-*.png"):
        stale.unlink()

    provenance = {}
    scenario_results = {name: [] for name in args.scenarios}
    lifecycle = {}
    evidence = {}
    screenshots = []

    try:
        for target in args.targets:
            source = prepare_source(target)
            build = build_target(target, source)
            executable, installed_sha = installed_binary(Path(build["product"]))
            build["installed_sha256"] = installed_sha
            if installed_sha != build["product_sha256"]:
                raise BenchError("installed binary hash does not match the built product")
            provenance[target] = build
            log(f"[provenance] {target}: HEAD {build['head'][:12]} product {installed_sha[:16]}…")

            log(f"[warmup] {target}: first launch before measurements")
            warm_up(executable, WORK / "out" / target / "warmup")

            log(f"[evidence] {target}: accessibility exposure of a math message")
            evidence[f"{target}/ax_gap"] = run_ax_gap_probe(target, executable)

            for name in args.scenarios:
                scenario = samples.SCENARIOS[name]()
                for repeat in range(1, args.repeats + 1):
                    shot = None
                    if target == "integrated" and name == "single_math_1" and repeat == 1:
                        shot = SHOT_DIR / "DEV-672-integrated-math-light.png"
                    if target == "baseline" and name == "single_math_1" and repeat == 1:
                        shot = SHOT_DIR / "DEV-672-baseline-math-light.png"
                    if target == "integrated" and name in ("mixed_math_20", "heavy_math_50") and repeat == 1:
                        shot = SHOT_DIR / f"DEV-672-integrated-{name}.png"
                    if target == "baseline" and name == "normal_long_text" and repeat == 1:
                        shot = SHOT_DIR / "DEV-672-baseline-normal_long_text.png"

                    log(f"[scenario] {target} {name} repeat {repeat}/{args.repeats}")
                    record = run_scenario(target, executable, scenario, f"{repeat}", screenshot=shot)
                    scenario_results[name].append(record)
                    log(
                        f"    footprint ready {record['footprint_mib_ready']} MiB "
                        f"settled {record['footprint_mib_settled']} MiB "
                        f"ready in {record['timings_ms']['ready_total']:.0f} ms"
                    )

            if target == "integrated" and not args.skip_evidence:
                log("[evidence] dark mode")
                record = run_scenario(
                    target,
                    executable,
                    samples.single_math(),
                    "dark",
                    dark=True,
                    screenshot=SHOT_DIR / "DEV-672-integrated-math-dark.png",
                )
                scenario_results["single_math_1"].append(record)

                log("[evidence] narrow window scrolling")
                evidence["integrated/narrow_scroll"] = run_layout_checks(target, executable)

                log("[evidence] streaming replay")
                evidence["integrated/streaming"] = run_streaming(target, executable)

                log("[evidence] cancel")
                evidence["integrated/cancel"] = run_cancel(target, executable)

                log("[evidence] failure state and retry")
                evidence["integrated/failure"] = run_failure(target, executable)

                log("[evidence] reference links across a display block")
                evidence["integrated/link"] = run_link_evidence(target, executable)

                log("[evidence] selection across and within blocks")
                evidence["integrated/selection"] = run_selection_evidence(target, executable)

                log("[evidence] main-thread drift while scrolling and streaming")
                evidence["integrated/stalls"] = run_stall_probes(target, executable)

            if not args.skip_lifecycle:
                log(f"[lifecycle] {target}: {args.cycles} cycles in one process")
                lifecycle[target] = run_lifecycle(target, executable, cycles=args.cycles)
    finally:
        clean_support()
        if not args.keep_work:
            cleanup_work()

    shot_paths = sorted(SHOT_DIR.glob("DEV-672-*.png"))
    screenshots = screenshot_metadata(shot_paths)

    light = SHOT_DIR / "DEV-672-integrated-math-light.png"
    dark = SHOT_DIR / "DEV-672-integrated-math-dark.png"
    if light.exists() and dark.exists():
        light_luminance = mean_luminance(light)
        dark_luminance = mean_luminance(dark)
        if light_luminance <= 0.5:
            raise BenchError(f"light screenshot is not light (luminance {light_luminance:.3f})")
        if dark_luminance >= 0.5:
            raise BenchError(f"dark screenshot is not dark (luminance {dark_luminance:.3f})")
        if sha256_file(light) == sha256_file(dark):
            raise BenchError("light and dark screenshots are identical")

    for name, records in scenario_results.items():
        write_jsonl(LOG_DIR / f"scenarios-{name}.jsonl", records)
    if lifecycle:
        write_jsonl(LOG_DIR / "lifecycle.jsonl", [row for data in lifecycle.values() for row in data["cycles"]])
        (LOG_DIR / "lifecycle-summary.json").write_text(
            json.dumps(
                {
                    target: {
                        key: value for key, value in data.items() if key != "cycles"
                    }
                    for target, data in lifecycle.items()
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
    write_jsonl(LOG_DIR / "evidence.jsonl", [{"kind": key, **value} for key, value in evidence.items()])
    (LOG_DIR / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2), encoding="utf-8")

    gaps = [
        "No human performance budget exists for footprint or latency; every number above is an "
        "observation from this machine on this sample set, not a bound or a leak-free proof.",
        "Streaming is replayed through the production update chain (view model append + throttled "
        "flush + view), not against a real provider; network latency is excluded by design.",
        "Scrolling was verified with single scroll events (one horizontal, two vertical) rather "
        "than a long trackpad session.",
        "Appearance beyond light/dark defaults, font sizes beyond the default, and windows "
        "narrower than 460 pt were not measured.",
        "Memory behaviour beyond 30 in-process session switches and the short idle window "
        "measured here (seconds, not hours) is not covered.",
        "Timer drift is not a located paint stall; no Instruments trace was captured to attribute "
        "the drift to a specific drawing path.",
        "Footprint is sensitive to process history: the baseline normal_long_text settled value "
        "moved 35.3-56.0 MiB between two otherwise identical runs of this harness. Numbers are "
        "comparable within one run (same session, both builds alternating), not across runs.",
        "A drag that crosses a display block stops at the block boundary by design: each markdown "
        "run around the block is its own Textual selection model.",
        "A live selection is not guaranteed across a re-render of the same answer; only the "
        "observed clipboard values above are reported.",
    ]

    payload = build_payload(
        scenario_results, lifecycle, evidence, provenance, screenshots, args, gaps
    )
    report_path = Path(args.report)
    write_report(report_path, payload)
    log(f"[done] report: {report_path}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BenchError as error:
        print(f"BENCHMARK FAILED: {error}", file=sys.stderr)
        sys.exit(1)
    except Exception:
        traceback.print_exc()
        sys.exit(1)
