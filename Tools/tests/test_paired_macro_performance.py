"""Exercise the paired macro-performance gate without building a package."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest

TOOLS = Path(__file__).resolve().parents[1]
SCRIPT = TOOLS / "check-paired-macro-performance.py"
spec = importlib.util.spec_from_file_location("paired_macro_performance", SCRIPT)
paired = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paired)

BENCHMARK = "Tests/InnoDIMacrosTests/MacroPerformanceBenchmark.swift"

# A stand-in for `swift` that builds nothing and reports the milliseconds
# recorded in the package it is asked to test, so the gate's process handling,
# pairing and verdict run for real.
FAKE_SWIFT = textwrap.dedent("""\
    #!/usr/bin/env python3
    import json, os, sys
    from pathlib import Path
    arguments = sys.argv[1:]
    if arguments[:1] == ["--version"]:
        print("Apple Swift version 0.0 (fake)")
        sys.exit(0)
    package = Path(arguments[arguments.index("--package-path") + 1])
    if arguments[0] == "build":
        sys.exit(1 if (package / "FAIL_BUILD").exists() else 0)
    rows = int(os.environ["INNODI_MACRO_BENCH_ITERATIONS"])
    value = float((package / "MS").read_text())
    Path(os.environ["INNODI_MACRO_BENCH_OUTPUT"]).write_text(json.dumps({
        "benchmark_version": 2, "workload_verified": True, "iterations": rows,
        "samples_ms": [value + index for index in range(rows)]}))
""")


def pairs(ratios, baseline=100.0):
    return [{"baseline_samples_ms": [baseline, baseline + 9],
             "candidate_samples_ms": [baseline * ratio + 7, baseline * ratio]}
            for ratio in ratios]


class PairedSummaryTests(unittest.TestCase):
    def test_gate_uses_the_median_ratio_of_block_lower_envelopes(self):
        summary = paired.summarize(pairs([1.0, 1.02, 0.98, 1.01, 5.0]), 20.0)
        self.assertEqual(summary["status"], "ok")
        self.assertEqual(summary["ratio"], 1.01)
        self.assertEqual(summary["regressionPct"], 1.0)
        self.assertEqual(summary["blockRatios"], [1.0, 1.02, 0.98, 1.01, 5.0])

    def test_budget_is_exclusive_and_a_speedup_never_fails(self):
        self.assertEqual(paired.summarize(pairs([1.2] * 5), 20.0)["status"], "ok")
        self.assertEqual(paired.summarize(pairs([1.2001] * 5), 20.0)["status"], "regression")
        self.assertEqual(paired.summarize(pairs([0.5] * 5), 20.0)["status"], "ok")

    def test_runner_speed_cancels_out_of_the_ratio(self):
        slow_runner = paired.summarize(pairs([1.05] * 7, baseline=300.0), 20.0)
        fast_runner = paired.summarize(pairs([1.05] * 7, baseline=110.0), 20.0)
        self.assertEqual(slow_runner["ratio"], fast_runner["ratio"])

    def test_interval_is_deterministic_and_brackets_the_ratio(self):
        ratios = [0.97, 1.0, 1.01, 1.03, 1.04, 1.06, 1.1]
        first = paired.summarize(pairs(ratios), 20.0)
        second = paired.summarize(pairs(ratios), 20.0)
        self.assertEqual(first, second)
        low, high = first["ratioInterval95"]
        self.assertLessEqual(low, first["ratio"])
        self.assertLessEqual(first["ratio"], high)

    def test_no_blocks_is_an_error_not_a_pass(self):
        with self.assertRaises(paired.PairedPerformanceError):
            paired.summarize([], 20.0)

    def test_blocks_alternate_the_first_side(self):
        self.assertEqual([paired.block_order(block)[0] for block in range(4)],
                         ["baseline", "candidate", "baseline", "candidate"])


class PairedInputTests(unittest.TestCase):
    def test_checked_in_baseline_pins_a_full_commit(self):
        baseline = paired.load_baseline(TOOLS / "macro-performance-paired-baseline.json")
        self.assertRegex(baseline["commit"], r"^[0-9a-f]{40}$")
        self.assertTrue(baseline["ref"])

    def test_baseline_file_rejects_floating_or_malformed_revisions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            for payload in ["not json", "[]", '{"schemaVersion": 2, "ref": "7.0.2", "commit": "%s"}' % ("a" * 40),
                            '{"schemaVersion": 1, "ref": "", "commit": "%s"}' % ("a" * 40),
                            '{"schemaVersion": 1, "ref": "main", "commit": "main"}',
                            '{"schemaVersion": 1, "ref": "7.0.2", "commit": "%s"}' % ("A" * 40),
                            '{"schemaVersion": 1, "ref": "7.0.2", "commit": "%s"}' % ("a" * 39)]:
                path.write_text(payload)
                with self.assertRaises(paired.PairedPerformanceError, msg=payload):
                    paired.load_baseline(path)

    def test_samples_must_verify_the_requested_version_2_workload(self):
        valid = {"benchmark_version": 2, "workload_verified": True, "iterations": 2,
                 "samples_ms": [120.5, 118.0]}
        self.assertEqual(paired.validated_samples(valid, 2), [120.5, 118.0])
        for change in [{"benchmark_version": 1}, {"workload_verified": False}, {"iterations": 3},
                       {"samples_ms": [120.5]}, {"samples_ms": [120.5, 0]},
                       {"samples_ms": [120.5, True]}, {"samples_ms": [120.5, float("nan")]},
                       {"samples_ms": "118.0"}]:
            with self.assertRaises(paired.PairedPerformanceError, msg=change):
                paired.validated_samples({**valid, **change}, 2)
        with self.assertRaises(paired.PairedPerformanceError):
            paired.validated_samples([], 2)


class PairedGateProcessTests(unittest.TestCase):
    def run_gate(self, candidate_ms, baseline_ms=100.0, extra=(), fail_baseline_build=False,
                 fail_candidate_build=False, unreachable_baseline=False):
        directory = tempfile.TemporaryDirectory(prefix="innodi-paired-perf-")
        self.addCleanup(directory.cleanup)
        base = Path(directory.name)
        repository = base / "repository"
        (repository / "Tools").mkdir(parents=True)
        (repository / BENCHMARK).parent.mkdir(parents=True)
        (repository / "Tools" / SCRIPT.name).write_bytes(SCRIPT.read_bytes())
        (repository / BENCHMARK).write_text("// baseline benchmark\n")
        (repository / "MS").write_text(str(baseline_ms))
        if fail_baseline_build:
            (repository / "FAIL_BUILD").write_text("")
        git = ["git", "-C", str(repository), "-c", "user.name=t", "-c", "user.email=t@example.invalid",
               "-c", "commit.gpgsign=false"]
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-q", "-m", "baseline"], check=True)
        commit = subprocess.run(git + ["rev-parse", "HEAD"], check=True, capture_output=True,
                                text=True).stdout.strip()
        if unreachable_baseline:
            commit = "0" * 40
        (repository / "Tools/macro-performance-paired-baseline.json").write_text(
            json.dumps({"schemaVersion": 1, "ref": "1.0.0", "commit": commit}))
        # The working tree is the candidate: a different benchmark source and timing.
        (repository / BENCHMARK).write_text("// candidate benchmark\n")
        (repository / "MS").write_text(str(candidate_ms))
        (repository / "FAIL_BUILD").unlink(missing_ok=True)
        if fail_candidate_build:
            (repository / "FAIL_BUILD").write_text("")
        binaries = base / "bin"
        binaries.mkdir()
        swift = binaries / "swift"
        swift.write_text(FAKE_SWIFT)
        swift.chmod(swift.stat().st_mode | stat.S_IXUSR)
        result = subprocess.run(
            [sys.executable, "-B", str(repository / "Tools" / SCRIPT.name), "--blocks", "4",
             "--rows", "2", *extra],
            env={**os.environ, "PATH": f"{binaries}{os.pathsep}{os.environ['PATH']}"},
            capture_output=True, text=True)
        report_path = repository / "build/paired-macro-performance-report.json"
        report = json.loads(report_path.read_text()) if report_path.is_file() else None
        return result, report, repository

    def test_unchanged_candidate_is_a_measured_pass(self):
        result, report, repository = self.run_gate(candidate_ms=101.0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["ratio"], 1.01)
        self.assertEqual([pair["order"][0] for pair in report["pairs"]],
                         ["baseline", "candidate", "baseline", "candidate"])
        self.assertEqual(report["baseline"]["ref"], "1.0.0")
        self.assertTrue(report["baseline"]["pinned"])
        # Both sides ran the candidate's benchmark source.
        exported = repository / "build/paired-macro-performance/baseline" / BENCHMARK
        self.assertEqual(exported.read_text(), "// candidate benchmark\n")
        self.assertEqual(report["benchmark"]["sha256"], paired.sha256(exported))

    def test_regression_fails_unless_report_only(self):
        result, report, _ = self.run_gate(candidate_ms=125.0)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["status"], "regression")
        self.assertIn("::error::paired macro-perf regression: +25.00%", result.stdout)
        result, report, _ = self.run_gate(candidate_ms=125.0, extra=["--report-only"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["status"], "regression")
        self.assertIn("::warning::paired macro-perf regression: +25.00%", result.stdout)
        self.assertNotIn("::error::", result.stdout)

    def test_unmeasurable_baseline_is_insufficient_evidence_not_a_pass(self):
        for options in [{"fail_baseline_build": True}, {"unreachable_baseline": True}]:
            result, report, _ = self.run_gate(candidate_ms=500.0, **options)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(report["status"], "insufficient-evidence")
            self.assertNotIn("ratio", report)
            self.assertIn("::warning::paired macro-performance comparison has insufficient evidence",
                          result.stdout)
            self.assertIn("not a measured pass", result.stdout)

    def test_candidate_that_does_not_build_fails_even_in_report_only_mode(self):
        result, report, _ = self.run_gate(candidate_ms=100.0, fail_candidate_build=True,
                                          extra=["--report-only"])
        self.assertEqual(result.returncode, 1)
        self.assertIsNone(report)
        self.assertIn("candidate does not build", result.stderr)


if __name__ == "__main__":
    unittest.main()
