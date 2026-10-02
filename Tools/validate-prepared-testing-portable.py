#!/usr/bin/env python3
"""Narrow Linux override-flow checks; not full InnoDITesting/Apple qualification.

Requires an already built real InnoDIMacros plugin and portable InnoDI runtime.
The Apple `os` import and three lock-backed mock helpers are excluded, with their
exact source boundary recorded. Every tested support declaration is a byte-for-
byte suffix of production source; tests are copied without modification. No
mock-storage substitutions or behavioral stubs are introduced.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", type=Path)
    parser.add_argument("runtime", type=Path, help="Directory containing InnoDI.swiftmodule and libInnoDI.so")
    parser.add_argument("output", type=Path, help="New isolated evidence directory")
    parser.add_argument("--swiftc", default=os.environ.get("SWIFTC", "swiftc"))
    parser.add_argument("--timeout", type=float, default=120, help="Per-command timeout in seconds (default: 120)")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    root = Path(__file__).resolve().parent.parent
    plugin = args.plugin.resolve(strict=True)
    runtime = args.runtime.resolve(strict=True)
    runtime_inputs = [runtime / "InnoDI.swiftmodule", runtime / "libInnoDI.so"]
    for path in runtime_inputs:
        if not path.is_file():
            parser.error(f"Missing runtime input: {path}")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)

    source_path = root / "Sources/InnoDITesting/InnoDITesting.swift"
    test_path = root / "Tests/InnoDITestingTests/PreparedOverrideTests.swift"
    source = source_path.read_bytes()
    marker = b"/// Stable error used to stop a test before an unstubbed operation executes.\n"
    if source.count(marker) != 1:
        raise RuntimeError("Production extraction boundary changed; review the portable scope")
    start = source.index(marker)
    prefix = b"import Foundation\n@_exported import InnoDI\n"
    if not source.startswith(prefix + b"import os\n"):
        raise RuntimeError("Production imports changed; review the portable scope")
    extracted = prefix + source[start:]
    extracted_path = output / "InnoDITestingPortableExcerpt.swift"
    extracted_path.write_bytes(extracted)
    copied_test = output / test_path.name
    shutil.copyfile(test_path, copied_test)

    runner = output / "Runner.swift"
    runner.write_text(
        "import Testing\n"
        "@main enum PreparedOverridesPortableRunner {\n"
        "    static func main() async {\n"
        "        await Testing.__swiftPMEntryPoint() as Never\n"
        "    }\n"
        "}\n"
    )
    inputs = [source_path, test_path, plugin, *runtime_inputs]
    manifest = {
        "scope": "Exact-source override/preset Linux checks only; not the full InnoDITesting product or Apple qualification",
        "excluded": ["import os", "DIConcurrentValueBox", "DIConcurrentMockState", "DIConcurrentCallRecorder"],
        "production_source": str(source_path),
        "declaration_byte_range": [start, len(source)],
        "declaration_start_line": source[:start].count(b"\n") + 1,
        "declaration_suffix_sha256": sha(source[start:]),
        "extracted_file_sha256": sha(extracted),
        "input_sha256": {str(path): sha(path.read_bytes()) for path in inputs},
        "compiler": subprocess.check_output([args.swiftc, "--version"], text=True),
        "commands": [],
        "command_timeout_seconds": args.timeout,
        "status": "running",
    }
    manifest_path = output / "manifest.json"

    def run(name, command, expected_failure=None):
        manifest["commands"].append({"name": name, "argv": list(map(str, command))})
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=args.timeout)
        except subprocess.TimeoutExpired as error:
            captured = error.stdout or ""
            if isinstance(captured, bytes):
                captured = captured.decode("utf-8", errors="replace")
            (output / f"{name}.log").write_text(captured + f"\nCommand timed out after {args.timeout} seconds.\n")
            manifest["status"] = f"failed: {name} (timeout after {args.timeout} seconds)"
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
            raise RuntimeError(f"{name} timed out; see {output / (name + '.log')}") from error
        except OSError as error:
            (output / f"{name}.log").write_text(f"Could not execute command: {error}\n")
            manifest["status"] = f"failed: {name} (could not execute command)"
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
            raise
        (output / f"{name}.log").write_text(result.stdout)
        if expected_failure is None:
            valid = result.returncode == 0
        else:
            valid = result.returncode != 0 and expected_failure in result.stdout and "Stack dump:" not in result.stdout
        if not valid:
            manifest["status"] = f"failed: {name}"
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
            print(result.stdout, file=sys.stderr)
            raise RuntimeError(f"{name} failed; see {output / (name + '.log')}")
        return result.stdout

    flags = [args.swiftc, "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
             "-module-cache-path", str(output / "module-cache")]
    load = ["-load-plugin-executable", f"{plugin}#InnoDIMacros"]
    libraries = ["-I", str(runtime), "-L", str(runtime), "-lInnoDI", "-Xlinker", "-rpath", "-Xlinker", str(runtime)]
    run("testing-excerpt-compile", [*flags, *load, *libraries, "-emit-module", "-emit-library", "-module-name", "InnoDITesting",
        "-emit-module-path", str(output / "InnoDITesting.swiftmodule"), "-o", str(output / "libInnoDITesting.so"), str(extracted_path)])
    testing_libraries = [*libraries, "-I", str(output), "-L", str(output), "-lInnoDITesting", "-Xlinker", "-rpath", "-Xlinker", str(output)]
    executable = output / "PreparedOverrideTests"
    run("prepared-tests-compile", [*flags, *load, *testing_libraries, "-parse-as-library", "-module-name", "PreparedOverridePortableTests",
        str(copied_test), str(runner), "-o", str(executable)])
    print(run("prepared-tests-run", [str(executable)]), end="")

    fixtures = root / "Tests/PreparedTestingPortableFixtures"
    for name, diagnostic in [
        ("ActorSlotIsolation", "call to main actor-isolated instance method 'set(_:to:)'"),
        ("ActorPresetIsolation", "main actor-isolated property 'service' can not be mutated from a Sendable closure"),
    ]:
        fixture = fixtures / f"{name}.swift.fixture"
        copied = output / f"{name}.swift"
        shutil.copyfile(fixture, copied)
        manifest["input_sha256"][str(fixture)] = sha(fixture.read_bytes())
        run(name, [*flags, *load, *testing_libraries, "-parse-as-library", "-c", str(copied),
                   "-o", str(output / f"{name}.o")], expected_failure=diagnostic)
        print(f"Expected isolation diagnostic passed: {name}")

    for path, digest in manifest["input_sha256"].items():
        if sha(Path(path).read_bytes()) != digest:
            raise RuntimeError(f"Input changed during validation: {path}")
    if copied_test.read_bytes() != test_path.read_bytes() or extracted_path.read_bytes() != extracted:
        raise RuntimeError("Copied test or production excerpt changed during validation")
    manifest["status"] = "passed narrow exact-source portable checks"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print("Apple os-backed mock storage and full InnoDITesting qualification were not run.")


if __name__ == "__main__":
    main()
