#!/usr/bin/env python3
"""Keep the authored Apple fixture in real Swift Testing discovery verbatim."""
from pathlib import Path
import difflib
import sys

root = Path(__file__).resolve().parent.parent
fixture = root / "Tests/OwnedPortablePluginFixtures/PreparedOnDemandApple.swift.fixture"
runtime = root / "Tests/InnoDIRuntimeTests/PreparedOperationRuntimeTests.swift"
prefix = "// Derived from PreparedOnDemandApple.swift.fixture; verify with Tools/validate-prepared-fixture-parity.py.\n"
wrapper = '''
@Suite("Prepared operation lifecycle")
struct PreparedOperationRuntimeTests {
    @Test("On-demand lifecycle, cancellation, readiness, retries, and isolation", .timeLimit(.minutes(1)))
    @MainActor func preparedOperationLifecycle() async throws {
        try await PreparedCheck.main()
    }
}
'''
source = fixture.read_text()
assert source.count("@main struct PreparedCheck {") == 1
expected = prefix + source.replace("import InnoDI\n", "import InnoDI\nimport Testing\n", 1).replace(
    "@main struct PreparedCheck {", "struct PreparedCheck {", 1
) + wrapper
if sys.argv[1:] == ["--write"]:
    runtime.write_text(expected)
elif sys.argv[1:]:
    raise SystemExit("Usage: validate-prepared-fixture-parity.py [--write]")
actual = runtime.read_text() if runtime.exists() else ""
if actual != expected:
    sys.stderr.writelines(difflib.unified_diff(actual.splitlines(keepends=True), expected.splitlines(keepends=True),
                                            fromfile=str(runtime), tofile="expected fixture-derived test"))
    raise SystemExit("Prepared runtime test drifted from its exact authored fixture")
print("Prepared Apple fixture/runtime test exact-source parity passed")
