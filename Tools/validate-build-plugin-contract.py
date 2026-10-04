#!/usr/bin/env python3
"""Exercise the production plugin adapter with a small, dependency-free tool.

This proves SwiftPM command ordering, resource classification, and environment
propagation. The probe coordinator does not perform InnoDI graph validation.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CONTROLS = {
    "INNODI_LOCK_TIMEOUT": "17.5",
    "INNODI_STALE_LOCK_AGE": "23",
    "INNODI_ALLOW_UNSAFE_LOCK": "0",
    "INNODI_VALIDATION_VERBOSE": "yes",
    "INNODI_VALIDATION_DEBUG": "no",
}
REPORTS = (
    "dag-validation-stamp.txt",
    "dag-validation-metrics.json",
    "dag-validation-summary.md",
)

MANIFEST = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PluginContract", targets: [
    .target(name: "SwiftProbe", plugins: ["InnoDIDAGValidationPlugin"]),
    .target(name: "ClangProbe", plugins: ["InnoDIDAGValidationPlugin"]),
    .executableTarget(name: "InnoDI-DAGValidationCoordinator"),
    .plugin(name: "InnoDIDAGValidationPlugin", capability: .buildTool(),
            dependencies: ["InnoDI-DAGValidationCoordinator"]),
])
'''

COORDINATOR = r'''import Foundation
let arguments = CommandLine.arguments
let outputIndex = arguments.firstIndex(of: "--output-dir")!
let output = URL(fileURLWithPath: arguments[outputIndex + 1])
let metrics = output.appendingPathComponent("dag-validation-metrics.json")
let previous = (try? Data(contentsOf: metrics)).flatMap {
    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
}
let keys = ["INNODI_LOCK_TIMEOUT", "INNODI_STALE_LOCK_AGE",
            "INNODI_ALLOW_UNSAFE_LOCK", "INNODI_VALIDATION_VERBOSE",
            "INNODI_VALIDATION_DEBUG", "INNODI_PLUGIN_UNRELATED"]
let environment = ProcessInfo.processInfo.environment
if environment["INNODI_LOCK_TIMEOUT"] == "fail-fixture" {
    FileHandle.standardError.write(Data("plugin-probe-forced-failure\n".utf8))
    Foundation.exit(3)
}
let observed = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
    environment[key].map { (key, $0) }
})
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: [
    "environment": observed,
    "invocations": (previous?["invocations"] as? Int ?? 0) + 1,
], options: [.sortedKeys]).write(to: metrics)
try "stamp\n".write(to: output.appendingPathComponent("dag-validation-stamp.txt"),
                    atomically: true, encoding: .utf8)
try "# Probe report\n".write(to: output.appendingPathComponent("dag-validation-summary.md"),
                             atomically: true, encoding: .utf8)
try "enum PluginGate { static let validated = 42 }\n".write(
    to: output.appendingPathComponent("_InnoDIDAGValidation.generated.swift"),
    atomically: true, encoding: .utf8)
'''


def write(root, relative, contents):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)


def run(root, label, command, environment, should_succeed=True):
    process = subprocess.Popen(
        command, cwd=root, env=environment, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        (root / f"{label}.log").write_text(output)
        raise RuntimeError(f"{label} exceeded 180 seconds") from None
    (root / f"{label}.log").write_text(output)
    if should_succeed and process.returncode:
        raise RuntimeError(f"{label} failed ({process.returncode}):\n{output}")
    if not should_succeed and (not process.returncode or "plugin-probe-forced-failure" not in output):
        raise RuntimeError(f"{label} did not fail at the validation gate ({process.returncode}):\n{output}")
    return output


def observation(root, target):
    matches = [path for path in (root / ".build/plugins/outputs").rglob(REPORTS[1])
               if target in path.parts]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {target} report, found {matches}")
    return json.loads(matches[0].read_text())


def check(plugin, root, swift):
    write(root, "Package.swift", MANIFEST)
    write(root, "Sources/InnoDI-DAGValidationCoordinator/main.swift", COORDINATOR)
    write(root, "Sources/SwiftProbe/Probe.swift", "public let validated = PluginGate.validated\n")
    write(root, "Sources/ClangProbe/probe.c", "int validated(void) { return 42; }\n")
    write(root, "Sources/ClangProbe/include/probe.h", "int validated(void);\n")
    destination = root / "Plugins/InnoDIDAGValidationPlugin/plugin.swift"
    destination.parent.mkdir(parents=True)
    shutil.copyfile(plugin, destination)
    environment = dict(os.environ)
    for key in (*CONTROLS, "INNODI_DISABLE_BUILD_VALIDATION"):
        environment.pop(key, None)
    environment.update(CONTROLS)
    environment["INNODI_PLUGIN_UNRELATED"] = "probe-unrelated-value"
    environment["CLANG_MODULE_CACHE_PATH"] = str(root / ".build/module-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(root / ".build/module-cache")
    command = [swift, "build", "--jobs", "2", "--cache-path", str(root / ".build/cache"), "--target"]
    run(root, "swift-cold", [*command, "SwiftProbe"], environment)
    cold = observation(root, "SwiftProbe")
    run(root, "swift-warm", [*command, "SwiftProbe"], environment)
    warm = observation(root, "SwiftProbe")
    changed_environment = {**environment, "INNODI_LOCK_TIMEOUT": "19.5",
                           "INNODI_ALLOW_UNSAFE_LOCK": "yes"}
    run(root, "swift-environment-change", [*command, "SwiftProbe"], changed_environment)
    changed = observation(root, "SwiftProbe")
    run(root, "clang-cold", [*command, "ClangProbe"], environment)
    clang = observation(root, "ClangProbe")
    run(root, "clang-warm", [*command, "ClangProbe"], environment)
    clang_warm = observation(root, "ClangProbe")
    unset_environment = {key: value for key, value in environment.items() if key not in CONTROLS}
    run(root, "swift-environment-unset", [*command, "SwiftProbe"], unset_environment)
    unset = observation(root, "SwiftProbe")
    failing_environment = {**environment, "INNODI_LOCK_TIMEOUT": "fail-fixture"}
    for target in ("SwiftProbe", "ClangProbe"):
        run(root, target + "-gate-failure", [*command, target], failing_environment,
            should_succeed=False)
        run(root, target + "-gate-recovery", [*command, target], environment)
    bundled = sorted(str(path.relative_to(root)) for name in REPORTS
                     for path in (root / ".build").rglob(name)
                     if any(part.endswith((".resources", ".bundle")) for part in path.parts))
    result = {"swiftCold": cold, "swiftWarm": warm, "swiftEnvironmentChange": changed,
              "clangCold": clang, "clangWarm": clang_warm,
              "swiftEnvironmentUnset": unset, "bundledReports": bundled}
    (root / "observations.json").write_text(json.dumps(result, indent=2) + "\n")
    failures = []
    if bundled:
        failures.append("Validation reports were copied into target resource bundles")
    for target, observed in [("SwiftProbe", cold), ("ClangProbe", clang)]:
        for key, expected in CONTROLS.items():
            if observed["environment"].get(key) != expected:
                failures.append(f"{target} did not receive {key}={expected}")
        if "INNODI_PLUGIN_UNRELATED" in observed["environment"]:
            failures.append(f"{target} received an environment variable outside the allowlist")
    if warm["invocations"] != cold["invocations"]:
        failures.append("An unchanged Swift build reran the validation command")
    if changed["environment"].get("INNODI_LOCK_TIMEOUT") != "19.5":
        failures.append("Changing a documented environment control did not refresh the Swift gate")
    if changed["environment"].get("INNODI_ALLOW_UNSAFE_LOCK") != "yes":
        failures.append("An explicit unsafe-filesystem opt-in was not forwarded unchanged")
    if clang_warm["invocations"] != clang["invocations"]:
        failures.append("An unchanged Clang build reran the validation command")
    if unset["environment"]:
        failures.append("Unsetting coordinator controls retained stale environment overrides")
    print(json.dumps(result, indent=2))
    if failures:
        raise AssertionError("\n".join(failures))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin-source", type=Path,
                        default=ROOT / "Plugins/InnoDIDAGValidationPlugin/plugin.swift")
    parser.add_argument("--work-dir", type=Path, help="Keep fixtures, build logs and observations here")
    parser.add_argument("--swift", default="swift")
    args = parser.parse_args()
    if args.work_dir:
        args.work_dir.mkdir(parents=True, exist_ok=False)
        check(args.plugin_source.resolve(), args.work_dir.resolve(), args.swift)
    else:
        with tempfile.TemporaryDirectory(prefix="innodi-plugin-contract-") as directory:
            check(args.plugin_source.resolve(), Path(directory), args.swift)


if __name__ == "__main__":
    main()
