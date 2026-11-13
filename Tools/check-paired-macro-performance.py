#!/usr/bin/env python3
"""Compare macro expansion with a pinned baseline revision on one machine.

A stored timing is not a stable reference on hosted runners: unchanged code
has recorded lower envelopes between 116.8 and 154.1 ms. This gate builds the
pinned baseline revision beside the candidate, runs both benchmark processes
in alternating paired blocks, and gates the median of the per-block ratios of
their lower envelopes. Both sides run the candidate's benchmark source, so the
workload is identical by construction.

Insufficient evidence means the baseline revision cannot be fetched or does
not build the candidate's benchmark. It is never a measured pass.

Exit status: 0 for a measured pass, and in --report-only mode also for a
regression or insufficient evidence, both reported as warnings. 1 for a
regression or insufficient evidence when enforcing, and in either mode for an
invalid measurement or a candidate that does not build.

Every run removes an earlier report at --output before it does anything else,
so a run that fails before it writes a report leaves none behind. A command
line that is rejected with exit status 2 starts no run and removes nothing.

The report names the candidate by its commit and by whether the working tree
matched that commit when the candidate was built. A tree with uncommitted or
untracked changes is measured and recorded as dirty, never rejected.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional

ROOT = Path(__file__).resolve().parents[1]
BENCHMARK_PATH = "Tests/InnoDIMacrosTests/MacroPerformanceBenchmark.swift"
BENCHMARK_FILTER = "MacroPerformanceBenchmark"
BENCHMARK_VERSION = 2
DEFAULT_BASELINE_FILE = "Tools/macro-performance-paired-baseline.json"
DEFAULT_OUTPUT = "build/paired-macro-performance-report.json"
DEFAULT_WORK_DIR = "build/paired-macro-performance"
BOOTSTRAP_SEED = 6725
BOOTSTRAP_DRAWS = 10000
BUILD_TIMEOUT_SECONDS = 45 * 60
BLOCK_TIMEOUT_SECONDS = 10 * 60
SIDES = ("baseline", "candidate")


class PairedPerformanceError(Exception):
    """An invalid input or measurement. Never a performance verdict."""


class InsufficientEvidence(Exception):
    """The baseline revision could not be measured on this machine."""


def load_baseline(path: Path) -> dict[str, str]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PairedPerformanceError(
            f"cannot read paired baseline '{path}': {error}"
        ) from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise PairedPerformanceError(
            "paired baseline must be a JSON object with schemaVersion 1"
        )
    ref = value.get("ref")
    commit = value.get("commit")
    if not isinstance(ref, str) or not ref:
        raise PairedPerformanceError("paired baseline needs a non-empty 'ref'")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise PairedPerformanceError(
            "paired baseline 'commit' must be a full lowercase commit SHA"
        )
    return {"ref": ref, "commit": commit}


def block_order(block: int) -> tuple[str, str]:
    """Alternate which side runs first so drift cannot favor one side."""
    return SIDES if block % 2 == 0 else (SIDES[1], SIDES[0])


def validated_samples(report: Any, rows: int) -> list[float]:
    if not isinstance(report, dict):
        raise PairedPerformanceError("benchmark report must be a JSON object")
    if (
        report.get("benchmark_version") != BENCHMARK_VERSION
        or report.get("workload_verified") is not True
    ):
        raise PairedPerformanceError(
            "benchmark report must verify the version 2 successful-expansion workload"
        )
    samples = report.get("samples_ms")
    if report.get("iterations") != rows or not isinstance(samples, list):
        raise PairedPerformanceError(
            "benchmark report iterations do not match the requested rows"
        )
    if len(samples) != rows:
        raise PairedPerformanceError(
            "benchmark report sample count does not match the requested rows"
        )
    values: list[float] = []
    for sample in samples:
        if isinstance(sample, bool) or not isinstance(sample, (int, float)):
            raise PairedPerformanceError("benchmark samples must be numbers")
        value = float(sample)
        if not math.isfinite(value) or value <= 0:
            raise PairedPerformanceError(
                "benchmark samples must be finite positive numbers"
            )
        values.append(value)
    return values


def finite(value: float, name: str) -> float:
    """Reject a derived metric that JSON cannot represent."""
    if not math.isfinite(value):
        raise PairedPerformanceError(f"{name} is not a finite number")
    return value


def percentile(sorted_values: list[float], fraction: float) -> float:
    position = fraction * (len(sorted_values) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return sorted_values[lower]
    weight = position - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def summarize(
    pairs: list[dict[str, Any]],
    threshold_pct: float,
    seed: int = BOOTSTRAP_SEED,
    draws: int = BOOTSTRAP_DRAWS,
) -> dict[str, Any]:
    """Gate the median per-block ratio; the interval is descriptive only."""
    if not pairs:
        raise PairedPerformanceError("no paired blocks were measured")
    ratios: list[float] = []
    for pair in pairs:
        baseline_min = min(pair["baseline_samples_ms"])
        candidate_min = min(pair["candidate_samples_ms"])
        ratios.append(finite(candidate_min / baseline_min, "block ratio"))
    ratio = statistics.median(ratios)
    generator = random.Random(seed)
    resampled = sorted(
        statistics.median(generator.choices(ratios, k=len(ratios)))
        for _ in range(draws)
    )
    # Finite samples can still overflow here, and `json` would then write
    # `Infinity`, which a strict parser rejects.
    regression_pct = finite((ratio - 1.0) * 100.0, "regression percentage")
    for bound in (resampled[0], resampled[-1]):
        finite(bound, "ratio interval")
    return {
        "status": "regression" if regression_pct > threshold_pct else "ok",
        "ratio": round(ratio, 5),
        "regressionPct": round(regression_pct, 2),
        "ratioInterval95": [
            round(percentile(resampled, 0.025), 5),
            round(percentile(resampled, 0.975), 5),
        ],
        "blockRatios": [round(value, 5) for value in ratios],
    }


def run(command: list[str], **kwargs: Any) -> subprocess.CompletedProcess:
    return subprocess.run(command, text=True, capture_output=True, **kwargs)


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess:
    return run(["git", "-C", str(root), *arguments])


def commit_is_available(root: Path, commit: str) -> bool:
    return git(root, "cat-file", "-e", commit + "^{commit}").returncode == 0


def ensure_commit(root: Path, commit: str) -> None:
    if commit_is_available(root, commit):
        return
    git(root, "fetch", "--no-tags", "--depth", "1", "origin", commit)
    if not commit_is_available(root, commit):
        raise InsufficientEvidence(
            f"baseline commit {commit} is not available and could not be fetched"
        )


def candidate_identity(root: Path) -> dict[str, Any]:
    """Name the candidate source: its commit, and whether the tree matches it.

    A tree with staged, modified or untracked files builds something other
    than its commit, so the commit alone would give two sources one name.
    Untracked files are requested explicitly because a user's
    `status.showUntrackedFiles=no` would otherwise hide a new source file.
    Files that `.gitignore` excludes are not examined. A value is None when
    git cannot report it.
    """
    commit = git(root, "rev-parse", "HEAD")
    status = git(root, "status", "--porcelain", "--untracked-files=all")
    return {
        "commit": (commit.stdout.strip() or None) if commit.returncode == 0 else None,
        "dirty": bool(status.stdout.strip()) if status.returncode == 0 else None,
    }


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def materialize_baseline(
    root: Path, candidate_root: Path, commit: str, work_dir: Path
) -> tuple[Path, str]:
    """Export the baseline revision and give it the candidate's benchmark."""
    benchmark = candidate_root / BENCHMARK_PATH
    if not benchmark.is_file():
        raise PairedPerformanceError(f"candidate benchmark missing: {benchmark}")
    benchmark_hash = sha256(benchmark)
    source = work_dir / "baseline"
    marker = work_dir / "baseline.json"
    identity = {"commit": commit, "benchmarkSha256": benchmark_hash}
    if marker.is_file() and source.is_dir():
        try:
            if json.loads(marker.read_text(encoding="utf-8")) == identity:
                return source, benchmark_hash
        except json.JSONDecodeError:
            pass
    if source.exists():
        shutil.rmtree(source)
    marker.unlink(missing_ok=True)
    source.mkdir(parents=True)
    archive = subprocess.Popen(
        ["git", "-C", str(root), "archive", commit], stdout=subprocess.PIPE
    )
    extract = subprocess.run(["tar", "-x", "-C", str(source)], stdin=archive.stdout)
    if archive.stdout is not None:
        archive.stdout.close()
    if archive.wait() != 0 or extract.returncode != 0:
        raise PairedPerformanceError(f"cannot export baseline commit {commit}")
    target = source / BENCHMARK_PATH
    if not target.parent.is_dir():
        raise InsufficientEvidence(
            "baseline revision has no macro test target for the benchmark"
        )
    shutil.copyfile(benchmark, target)
    marker.write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    return source, benchmark_hash


def swift_package_arguments(package: Path, scratch: Optional[Path]) -> list[str]:
    arguments = ["--package-path", str(package)]
    if scratch is not None:
        arguments += ["--scratch-path", str(scratch)]
    return arguments


def build_tests(package: Path, scratch: Optional[Path], log: Path) -> bool:
    command = ["swift", "build", "--build-tests", *swift_package_arguments(package, scratch)]
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(
            command, stdout=output, stderr=subprocess.STDOUT,
            timeout=BUILD_TIMEOUT_SECONDS,
        )
    return result.returncode == 0


def measure_process(
    package: Path, scratch: Optional[Path], rows: int, report: Path, log: Path
) -> list[float]:
    report.unlink(missing_ok=True)
    environment = dict(os.environ)
    environment["INNODI_MACRO_BENCH_ITERATIONS"] = str(rows)
    environment["INNODI_MACRO_BENCH_OUTPUT"] = str(report)
    command = [
        "swift", "test", "--skip-build", *swift_package_arguments(package, scratch),
        "--filter", BENCHMARK_FILTER,
    ]
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(
            command, env=environment, stdout=output, stderr=subprocess.STDOUT,
            timeout=BLOCK_TIMEOUT_SECONDS,
        )
    if result.returncode != 0 or not report.is_file():
        raise PairedPerformanceError(
            f"benchmark process failed; no valid measurement (log: {log})"
        )
    try:
        payload = json.loads(report.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise PairedPerformanceError(
            f"benchmark report is not valid JSON: {report}"
        ) from error
    return validated_samples(payload, rows)


def log_tail(path: Path, lines: int = 25) -> str:
    try:
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])
    except OSError:
        return ""


def positive_integer(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--baseline-file", default=DEFAULT_BASELINE_FILE)
    parser.add_argument(
        "--baseline-commit",
        help="measure against this commit instead of the pinned one (experiments only)",
    )
    parser.add_argument("--candidate-root", default=str(ROOT))
    parser.add_argument("--candidate-scratch-path")
    parser.add_argument("--work-dir", default=DEFAULT_WORK_DIR)
    parser.add_argument("--blocks", type=positive_integer, default=15)
    parser.add_argument("--rows", type=positive_integer, default=10)
    parser.add_argument("--threshold", type=float, default=20.0)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--report-only", action="store_true")
    arguments = parser.parse_args(argv)
    if not math.isfinite(arguments.threshold) or arguments.threshold < 0:
        parser.error("--threshold must be a finite non-negative number")
    return arguments


def resolve(path: str) -> Path:
    candidate = Path(path)
    return candidate if candidate.is_absolute() else ROOT / candidate


def remove_previous_report(path: Path) -> None:
    """Keep a run that fails before `write_report` from leaving an old verdict."""
    try:
        path.unlink(missing_ok=True)
    except OSError as error:
        raise PairedPerformanceError(
            f"cannot remove the previous report '{path}': {error}"
        ) from error


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        text = json.dumps(report, indent=2, allow_nan=False)
    except ValueError as error:
        raise PairedPerformanceError(
            f"report contains a value JSON cannot represent: {error}"
        ) from error
    path.write_text(text + "\n", encoding="utf-8")
    print(f"[paired-perf] report saved to {path}")


def main(argv: list[str]) -> int:
    arguments = parse_arguments(argv)
    output = resolve(arguments.output)
    remove_previous_report(output)
    work_dir = resolve(arguments.work_dir)
    candidate_root = Path(arguments.candidate_root).resolve()
    candidate_scratch = (
        Path(arguments.candidate_scratch_path).resolve()
        if arguments.candidate_scratch_path
        else None
    )
    work_dir.mkdir(parents=True, exist_ok=True)

    baseline = load_baseline(resolve(arguments.baseline_file))
    pinned = arguments.baseline_commit is None
    if not pinned:
        resolved = git(ROOT, "rev-parse", "--verify", arguments.baseline_commit + "^{commit}")
        if resolved.returncode != 0:
            raise PairedPerformanceError(
                f"cannot resolve --baseline-commit '{arguments.baseline_commit}'"
            )
        baseline = {"ref": arguments.baseline_commit, "commit": resolved.stdout.strip()}

    swift_version = run(["swift", "--version"]).stdout.splitlines()
    report: dict[str, Any] = {
        "schemaVersion": 1,
        "metric": "median of per-block candidate_min_ms / baseline_min_ms",
        "thresholdPct": arguments.threshold,
        "blocks": arguments.blocks,
        "rowsPerProcess": arguments.rows,
        "baseline": {**baseline, "pinned": pinned},
        "candidate": candidate_identity(candidate_root),
        "benchmark": {
            "path": BENCHMARK_PATH,
            "filter": BENCHMARK_FILTER,
            "benchmarkVersion": BENCHMARK_VERSION,
        },
        "swiftVersion": swift_version[0] if swift_version else None,
        "reportOnly": arguments.report_only,
    }

    try:
        ensure_commit(ROOT, baseline["commit"])
        baseline_source, benchmark_hash = materialize_baseline(
            ROOT, candidate_root, baseline["commit"], work_dir
        )
        report["benchmark"]["sha256"] = benchmark_hash
        print(f"[paired-perf] building baseline {baseline['ref']} ({baseline['commit'][:12]})")
        baseline_scratch = work_dir / "baseline-build"
        baseline_log = work_dir / "baseline-build.log"
        if not build_tests(baseline_source, baseline_scratch, baseline_log):
            raise InsufficientEvidence(
                "baseline revision does not build the candidate benchmark on this "
                f"toolchain (log: {baseline_log})\n{log_tail(baseline_log)}"
            )
    except InsufficientEvidence as error:
        report["status"] = "insufficient-evidence"
        report["note"] = str(error).splitlines()[0]
        write_report(output, report)
        print(f"[paired-perf] insufficient evidence: {error}")
        message = (
            "paired macro-performance comparison has insufficient evidence; "
            "this is not a measured pass"
        )
        if arguments.report_only:
            print(f"::warning::{message} (report-only)")
            return 0
        # An enforcing run that measured nothing must not look like a pass.
        print(f"::error::{message}")
        return 1

    print("[paired-perf] building candidate")
    candidate_log = work_dir / "candidate-build.log"
    if not build_tests(candidate_root, candidate_scratch, candidate_log):
        raise PairedPerformanceError(
            f"candidate does not build (log: {candidate_log})\n{log_tail(candidate_log)}"
        )
    # The blocks run this build without rebuilding it, so name the source it
    # compiled: the tree may have changed while the baseline was building.
    report["candidate"] = candidate_identity(candidate_root)
    if report["candidate"]["dirty"]:
        print(
            "[paired-perf] candidate tree has uncommitted or untracked changes; "
            "the report records it as dirty"
        )

    packages = {
        "baseline": (baseline_source, baseline_scratch),
        "candidate": (candidate_root, candidate_scratch),
    }
    pairs: list[dict[str, Any]] = []
    for block in range(arguments.blocks):
        order = block_order(block)
        pair: dict[str, Any] = {"block": block, "order": list(order)}
        for side in order:
            package, scratch = packages[side]
            samples = measure_process(
                package, scratch, arguments.rows,
                work_dir / f"{side}-block{block}.json",
                work_dir / f"{side}-block{block}.log",
            )
            pair[f"{side}_samples_ms"] = samples
            pair[f"{side}_min_ms"] = min(samples)
        pair["ratio"] = round(
            finite(pair["candidate_min_ms"] / pair["baseline_min_ms"], "block ratio"), 5
        )
        pairs.append(pair)
        print(
            f"[paired-perf] block {block + 1}/{arguments.blocks}: "
            f"baseline min={pair['baseline_min_ms']:.3f}ms "
            f"candidate min={pair['candidate_min_ms']:.3f}ms ratio={pair['ratio']:.4f}"
        )

    summary = summarize(pairs, arguments.threshold)
    report.update(summary)
    report["pairs"] = pairs
    write_report(output, report)
    low, high = summary["ratioInterval95"]
    print(
        f"[paired-perf] baseline {baseline['ref']} vs candidate: ratio={summary['ratio']:.4f} "
        f"(descriptive 95% interval {low:.4f}-{high:.4f}) "
        f"delta={summary['regressionPct']:+.2f}% threshold={arguments.threshold:.2f}%"
    )
    if summary["status"] != "regression":
        return 0
    message = (
        f"paired macro-perf regression: {summary['regressionPct']:+.2f}% against "
        f"baseline {baseline['ref']} ({arguments.threshold:.2f}% threshold)"
    )
    if arguments.report_only:
        print(f"::warning::{message} (report-only)")
        return 0
    print(f"::error::{message}")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except PairedPerformanceError as error:
        print(f"[paired-perf] {error}", file=sys.stderr)
        sys.exit(1)
    except subprocess.TimeoutExpired as error:
        print(f"[paired-perf] timed out: {error}", file=sys.stderr)
        sys.exit(1)
