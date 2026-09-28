#!/usr/bin/env python3
"""Fail closed on incomplete feature evidence; no timing budget is invented."""
import json
import math
import re
import sys

EXPECTED = {
    "assisted-factory": {"static_inputs": 8, "assisted_inputs": 8},
    "large-multibinding": {"contributors": 64, "collections": 1},
    "mock-generation": {"methods": 32, "typed_async_throwing_methods": 16},
}


def validate(report, sha):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    require(type(report) is dict and type(report.get("schema_version")) is int and report["schema_version"] == 1, "unsupported feature schema")
    require(re.fullmatch(r"[0-9a-f]{40}", sha) and report.get("candidate_sha") == sha, "candidate mismatch")
    require(type(report.get("source_tree_clean")) is bool, "missing source provenance")
    require(isinstance(report.get("swift_version"), str) and "Swift version" in report["swift_version"], "missing compiler provenance")
    require(report.get("configuration") == "debug-in-process", "configuration mismatch")
    require(report.get("enforcement") == "report-only-unbaselined", "feature timings are not a calibrated gate")
    workloads = report.get("workloads")
    require(type(workloads) is list and len(workloads) == len(EXPECTED), "incomplete workloads")
    require(all(type(item) is dict for item in workloads), "malformed workload")
    require(sorted(item.get("id", "") for item in workloads) == sorted(EXPECTED), "unknown or duplicate workloads")
    for item in workloads:
        require(type(item.get("workload_version")) is int and item["workload_version"] == 1, "workload version mismatch")
        dimensions = item.get("dimensions")
        require(type(dimensions) is dict and dimensions == EXPECTED[item["id"]]
                and all(type(value) is int for value in dimensions.values()), "workload dimensions changed")
        require(item.get("workload_verified") is True, "unverified expansion")
        count = item.get("iterations")
        require(type(count) is int and 1 <= count <= 100, "invalid iterations")
        require(type(item.get("warmup_iterations")) is int and item["warmup_iterations"] >= max(10, count), "insufficient warmup")
        samples = item.get("samples_ms")
        require(type(samples) is list and len(samples) == count, "incomplete samples")
        require(all(type(x) in (int, float) and math.isfinite(x) and x > 0 for x in samples), "invalid sample")
        for key, expected in (("min_ms", min(samples)), ("mean_ms", sum(samples) / count)):
            value = item.get(key)
            require(type(value) in (int, float) and math.isfinite(value) and math.isclose(value, expected, rel_tol=1e-9), "inconsistent statistics")


if __name__ == "__main__":
    try:
        with open(sys.argv[1], encoding="utf-8") as file:
            validate(json.load(file), sys.argv[2])
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        raise SystemExit(f"Invalid macro feature evidence: {error}")
    print("Verified three independent v1 workloads; timing budgets remain uncalibrated.")
