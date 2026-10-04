"""Keep minimum-toolchain execution and real-plugin consumer coverage additive."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def job(source, start, end):
    return source.split("  " + start + ":\n", 1)[1].split("  " + end + ":\n", 1)[0]


class MacroFirstAppleContracts(unittest.TestCase):
    def test_minimum_toolchain_executes_package_and_both_consumers(self):
        workflow = (ROOT / ".github/workflows/macro-tests.yml").read_text()
        lane = job(workflow, "swift-62-compatibility", "xcode-27-compatibility")
        self.assertIn('version: "26.2"', lane)
        self.assertIn("Run minimum-toolchain package contracts", lane)
        package = lane.split("Run minimum-toolchain package contracts", 1)[1].split("      - name:", 1)[0]
        self.assertIn("swift test --no-parallel", package)
        self.assertIn("-strict-concurrency=complete", package)
        self.assertIn("-warnings-as-errors", package)
        self.assertEqual(package.count("--skip"), 2)
        self.assertIn("--skip 'InnoDIBuildSupportTests.PublicAPIContractTests/compilerDefaultArgumentContract'", package)
        self.assertIn("--skip 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)'", package)
        self.assertNotIn("--filter", package)
        self.assertIn("--filter StrictConcurrencyBuildTests", lane)
        self.assertIn("--filter ExternalConsumerContractTests", lane)
        self.assertIn("Tools/check-public-api.py", lane)
        self.assertNotIn("--update", lane)
        self.assertNotIn("continue-on-error", lane)

    def test_release_keeps_the_same_minimum_toolchain_execution(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        lane = job(workflow, "release-compatibility", "exact-revision-consumer")
        package = lane.split("Run minimum-toolchain package contracts", 1)[1].split("      - name:", 1)[0]
        self.assertIn("if: matrix.xcode == '26.2'", package)
        self.assertIn("swift test --no-parallel", package)
        self.assertEqual(package.count("--skip"), 1)
        self.assertIn("--filter StrictConcurrencyBuildTests", lane)
        self.assertIn("--filter ExternalConsumerContractTests", lane)

    def test_real_plugin_fixture_covers_public_override_and_deferred_surface(self):
        root = ROOT / "Tests/ExternalConsumerFixtures/pass/owned-overrides-deferred"
        manifest = (root / "Package.swift.fixture").read_text()
        library = (root / "Sources/OwnedPublicLibrary/OwnedPublicLibrary.swift.fixture").read_text()
        app = (root / "Sources/FixtureApp/FixtureApp.swift.fixture").read_text()
        self.assertIn(".macOS(.v14)", manifest)
        self.assertIn("{{INNODI_PACKAGE_PATH}}", manifest)
        self.assertIn("{{INNODI_PACKAGE_IDENTITY}}", manifest)
        self.assertIn("@DIContainer(generateOwned: true)", library)
        self.assertIn("InnoDI.Lazy<Int>", library)
        self.assertIn("InnoDI.Provider<Int>", library)
        self.assertIn("import OwnedPublicLibrary", app)
        self.assertIn("makeOwnedWithOverrides", app)
        self.assertIn("cachedHandle.value() == 40", app)
        self.assertIn("freshHandle.value() == 30", app)
        self.assertNotIn("Synchronization", library + app)
        self.assertNotIn("@available", library + app)


if __name__ == "__main__":
    unittest.main()
