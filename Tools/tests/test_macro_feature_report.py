import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("feature_report", Path(__file__).parents[1] / "validate-macro-feature-report.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class FeatureReportTests(unittest.TestCase):
    def report(self):
        return {"schema_version": 2, "scope": "in-process-expansion-driver",
                "candidate_sha": "a" * 40, "source_tree_clean": True,
                "swift_version": "Apple Swift version 6.3.3", "configuration": "debug-in-process",
                "enforcement": "report-only-unbaselined", "workloads": [
                    {"id": name, "workload_version": 1, "dimensions": dimensions,
                     "workload_verified": True, "iterations": 2, "warmup_iterations": 10,
                     "driver_expanded_utf8_bytes": 1024,
                     "samples_ms": [1.0, 3.0], "min_ms": 1.0, "mean_ms": 2.0}
                    for name, dimensions in validator.EXPECTED.items()]}

    def test_complete_report(self):
        validator.validate(self.report(), "a" * 40)

    def test_rejects_incomplete_or_misleading_evidence(self):
        mutations = [
            lambda r: r.update(candidate_sha="b" * 40),
            lambda r: r.update(schema_version=1),
            lambda r: r.update(scope="full-consumer-build"),
            lambda r: r.update(enforcement="passed"),
            lambda r: r.update(swift_version="unknown"),
            lambda r: r["workloads"].pop(),
            lambda r: r["workloads"].__setitem__(1, copy.deepcopy(r["workloads"][0])),
            lambda r: r["workloads"][0].update(workload_version=2),
            lambda r: r["workloads"][0].update(dimensions={}),
            lambda r: r["workloads"][0].update(workload_verified=False),
            lambda r: r["workloads"][0].update(driver_expanded_utf8_bytes=0),
            lambda r: r["workloads"][0].update(driver_expanded_utf8_bytes=True),
            lambda r: r["workloads"][0].update(warmup_iterations=1),
            lambda r: r["workloads"][0].update(samples_ms=[float("nan"), 3]),
            lambda r: r["workloads"][0].update(samples_ms=[True, 3]),
            lambda r: r["workloads"][0].update(min_ms=0.5),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                report = self.report()
                mutate(report)
                with self.assertRaises(ValueError):
                    validator.validate(report, "a" * 40)


if __name__ == "__main__":
    unittest.main()
