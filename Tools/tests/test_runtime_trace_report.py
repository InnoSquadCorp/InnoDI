#!/usr/bin/env python3
"""Executable negative contracts for trace workload evidence (no Swift rebuild)."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GATE = Path(__file__).resolve().parents[1] / "check-runtime-trace-report.py"


def valid_report():
    observations = [
        {"round": r, "start": 1000 * r + 200, "end": 1000 * r + 600,
         "retainedEventCount": 4096,
         "writers": [{"writer": w, "start": 1000 * r + 100,
                      "end": 1000 * r + 700} for w in range(4)]}
        for r in range(64)
    ]
    sample = {"capacity": 4096, "writerCount": 4, "snapshotCount": 64,
              "prefillEventCount": 4096, "eventsPerWriter": 10000,
              "emittedEventCount": 40000, "retainedEventCount": 4096,
              "droppedEventCount": 40000, "nanosecondsPerEvent": 3.84,
              "wallNanosecondsPerEvent": 2, "observations": observations}
    return {"schemaVersion": 2, "iterations": 1000000, "enabledIterations": 20000,
            "candidateSHA": "a" * 40, "sourceTreeClean": True, "compilerVersion": "fixture compiler",
            "recordedEventCount": 40000, "disabledNetNanosecondsPerResolution": 1,
            "enabledNanosecondsPerEvent": 1,
            "saturatedMeasurements": [
                {"capacity": c, "emittedEventCount": c + 40000, "retainedEventCount": c,
                 "droppedEventCount": 40000, "nanosecondsPerEvent": 1,
                 "snapshotNanosecondsPerRetainedEvent": 1} for c in [64, 4096, 65536]],
            "contentionMeasurements": [copy.deepcopy(sample) for _ in range(5)]}


class TraceReportGateTests(unittest.TestCase):
    def check(self, report, passes=False, expected_sha=""):
        with tempfile.TemporaryDirectory(prefix="innodi-trace-contract-") as directory:
            path = Path(directory) / "report.json"
            path.write_text(json.dumps(report))
            result = subprocess.run([sys.executable, str(GATE), str(path),
                                     "210", "600", "2500", "5000", "5000", expected_sha],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, passes, result.stdout + result.stderr)

    def test_valid(self):
        self.check(valid_report(), passes=True)
        self.check(valid_report(), passes=True, expected_sha="a" * 40)

    def test_candidate_provenance(self):
        self.check(valid_report(), expected_sha="b" * 40)
        for key in ["candidateSHA", "sourceTreeClean", "compilerVersion"]:
            report = valid_report()
            del report[key]
            self.check(report, expected_sha="a" * 40)
        report = valid_report()
        report["sourceTreeClean"] = False
        self.check(report, expected_sha="a" * 40)
        self.check(report, passes=True)  # Local dirty measurements are labeled, not release evidence.

    def test_invalid_workloads(self):
        for mutation in ["empty", "tail", "unpaced", "missing", "prefill", "accounting",
                         "writer", "count", "timing", "nan", "boolean", "schema"]:
            with self.subTest(mutation=mutation):
                report = valid_report()
                sample = report["contentionMeasurements"][0]
                observations = sample["observations"]
                if mutation == "empty": observations[0]["retainedEventCount"] = 0
                if mutation == "tail":
                    for o in observations:
                        o["start"] = o["round"] * 1000 + 800
                        o["end"] = o["round"] * 1000 + 900
                if mutation == "unpaced": observations[1]["start"] = 1
                if mutation == "missing": sample["observations"] = observations[:1]
                if mutation == "prefill": sample["prefillEventCount"] = 0
                if mutation == "accounting": sample["droppedEventCount"] -= 1
                if mutation == "writer": observations[0]["writers"].pop()
                if mutation == "count": sample["eventsPerWriter"] = 0
                if mutation == "timing": sample["nanosecondsPerEvent"] = 0
                if mutation == "nan": report["enabledNanosecondsPerEvent"] = float("nan")
                if mutation == "boolean": report["disabledNetNanosecondsPerResolution"] = True
                if mutation == "schema": report["schemaVersion"] = 1
                self.check(report)

    def test_every_budget(self):
        for metric, budget in [("disabled", 210), ("enabled", 600), ("saturated", 2500),
                               ("snapshot", 5000), ("contention", 5000)]:
            with self.subTest(metric=metric):
                report = valid_report()
                if metric == "disabled": report["disabledNetNanosecondsPerResolution"] = budget + 1
                if metric == "enabled": report["enabledNanosecondsPerEvent"] = budget + 1
                if metric == "saturated": report["saturatedMeasurements"][0]["nanosecondsPerEvent"] = budget + 1
                if metric == "snapshot": report["saturatedMeasurements"][0]["snapshotNanosecondsPerRetainedEvent"] = budget + 1
                if metric == "contention":
                    # Keep raw timing evidence consistent; all five samples must fail.
                    for sample in report["contentionMeasurements"]:
                        for o in sample["observations"]:
                            o["start"] *= 10000
                            o["end"] *= 10000
                            for writer in o["writers"]:
                                writer["start"] *= 10000
                                writer["end"] *= 10000
                        sample["nanosecondsPerEvent"] *= 10000
                self.check(report)


if __name__ == "__main__":
    unittest.main()
