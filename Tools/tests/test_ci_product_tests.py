import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("product_tests", ROOT / "Tools/ci_product_tests.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class ProductConsumerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "Renamed.Checkout.git"
        self.product = "InnoDISwiftUI"
        self.target = runner.PRODUCTS[self.product]
        self.package = runner.package_path(self.root, self.product)
        self.source = self.root / "Tests" / self.target
        self.source.mkdir(parents=True)
        (self.source / "Example.swift").write_text("import Testing\n@Test func example() {}\n")
        (self.package / "Tests").mkdir(parents=True)
        (self.package / "Tests" / self.target).symlink_to(self.source, target_is_directory=True)
        for path in (self.root / "Package.swift", self.package / "Package.swift", self.root / "Tools/ci_product_tests.py",
                     self.root / "Tools/ci_product_api.py", self.root / "Tools/check-public-api.py"):
            path.write_text("fixture\n")
        baseline = {"schemaVersion": runner.api.gate.SCHEMA_VERSION, "graphs": [
            {"module": product, "file": product + ".symbols.json", "symbols": [{"fixture": product}], "relationships": []}
            for product in runner.api.gate.PUBLIC_PRODUCT_MODULES
        ]}
        (self.root / "Tools/public-api-baseline.json").write_text(json.dumps(baseline))
        pin = {"identity": "swift-syntax", "kind": "remoteSourceControl",
               "location": "https://github.com/swiftlang/swift-syntax.git",
               "state": {"revision": "a" * 40, "version": "604.0.0"}}
        for path in (self.root / "Package.resolved", self.package / "Package.resolved"):
            path.write_text(json.dumps({"version": 3, "pins": [pin]}))

    def manifests(self):
        target = {"name": self.target, "type": "test", "dependencies": [{"byName": [self.product, None]}],
                  "exclude": [], "resources": [], "settings": [], "packageAccess": True}
        full = {"name": "InnoDI", "targets": [target], "products": [{"name": self.product, "targets": [self.product]}],
                "dependencies": [], "platforms": [{"platformName": "macos", "version": "14.0"}],
                "toolsVersion": {"_version": "6.2.0"}}
        scoped = copy.deepcopy(full)
        scoped.update(name=self.product + "ProductTests", products=[],
                      dependencies=[{"fileSystem": [{"identity": "renamed.checkout", "path": str(self.root), "productFilter": None}]}])
        scoped["targets"][0]["dependencies"] = [{"product": [self.product, "renamed.checkout", None, None]}]
        full["targets"].extend([
            {"name": self.product, "type": "regular", "dependencies": [{"byName": ["InnoDI", None]}]},
            {"name": "InnoDI", "type": "regular", "dependencies": [{"byName": ["InnoDIMacros", None]}]},
            {"name": "InnoDIMacros", "type": "macro", "dependencies": [{"byName": ["InnoDICore", None]}]},
            {"name": "InnoDICore", "type": "regular", "dependencies": []},
        ])
        return full, scoped

    def descriptions(self):
        value = {"targets": [{"name": self.target, "type": "test", "path": "Tests/" + self.target,
                               "sources": ["Example.swift"]}]}
        return copy.deepcopy(value), copy.deepcopy(value)

    def inspected(self):
        full, scoped = self.manifests()
        full["targets"].append({"name": "OtherTests", "type": "test"})
        return {"root_dump": full, "consumer_dump": scoped}

    def environment(self):
        return {"schema": 1, "xcode_version": "26.6", "xcode_build": "17F64",
                "sdk_version": "26.5", "sdk_build": "25F42", "macos_version": "26.5.1",
                "architecture": "arm64"}

    def tool_output(self, command):
        values = {
            ("xcrun", "swift", "--version"): "Apple Swift version 6.3\nTarget: arm64-apple-macosx26.0",
            ("xcodebuild", "-version"): "Xcode 26.6\nBuild version 17F64\n",
            ("xcrun", "--sdk", "macosx", "--show-sdk-version"): "26.5\n",
            ("xcrun", "--sdk", "macosx", "--show-sdk-build-version"): "25F42\n",
            ("sw_vers", "-productVersion"): "26.5.1\n",
            ("uname", "-m"): "arm64\n",
        }
        return values[tuple(command)]

    def qualify(self, full_list=None, scoped_list=None, run=lambda *a, **k: None):
        full_list = full_list or self.target + ".Suite/example()\nOtherTests.Suite/other()\n"
        scoped_list = scoped_list or self.target + ".Suite/example()\n"
        def output(command, **kwargs):
            if command[:4] == ["xcrun", "swift", "test", "list"]:
                self.assertIn("--skip-build", command)
                self.assertIn("--force-resolved-versions", command)
                self.assertNotIn("--no-parallel", command)
                self.assertNotIn("--list-tests", command)
                self.assertTrue(all(flag in command for flag in runner.BUILD_FLAGS))
                return scoped_list
            return self.tool_output(command)
        with patch.object(runner, "inspect", return_value=self.inspected()), \
             patch.object(runner, "verify_build_closure", return_value=self.build_proof()), \
             patch.object(runner.api, "verify", return_value=self.api_proof()):
            return runner.qualify(self.root, self.product, full_list, output, run,
                                  full_api_contract=self.root / "full-api.json")

    def api_proof(self):
        baseline = runner.api.selected_graph(json.loads((self.root / "Tools/public-api-baseline.json").read_text()), self.product)
        return {"schema": "selected-api-v1", "product": self.product,
                "baseline_match": True, "full_current_match": True,
                "normalized_sha256": runner.api.graph_digest(baseline)}

    def build_proof(self):
        return {"schema": "swiftpm-native-v1", "fresh_scratch": True,
                "first_party_modules": runner.expected_modules(self.product, self.inspected()),
                "raw_description_sha256": {"debug/description.json": "a" * 64}}

    def build_fixture(self, module_names=None):
        scratch = self.root / "scratch"
        binary_dir = scratch / "arm64-apple-macosx" / "debug"
        modules_dir = binary_dir / "Modules"
        modules_dir.mkdir(parents=True)
        module_names = module_names or runner.expected_modules(self.product, self.inspected())
        description = {"swiftCommands": {}, "swiftFrontendCommands": {}}
        for name in module_names:
            module = modules_dir / (name + ".swiftmodule")
            module.write_bytes(b"unit-test-artifact")
            description["swiftCommands"]["C." + name] = {"moduleName": name, "moduleOutputPath": str(module)}
        description_path = binary_dir / "description.json"
        description_path.write_text(json.dumps(description))
        return scratch, description_path, modules_dir

    def test_real_repository_source_links_cover_every_existing_test(self):
        for product, target in runner.PRODUCTS.items():
            inventory = runner.source_inventory(ROOT, product)
            self.assertEqual(set(inventory), {path.name for path in (ROOT / "Tests" / target).glob("*.swift")})
            self.assertIn('.package(path: "../../..")', (runner.package_path(ROOT, product) / "Package.swift").read_text())

    def test_only_two_public_leaf_products_are_supported(self):
        for product in ("InnoDI", "InnoDI-Migrate", "InnoDI-Doctor", "InnoDI-DependencyGraph", "InnoDIDAGValidationPlugin"):
            with self.assertRaises(ValueError):
                runner.package_path(self.root, product)

    def test_renamed_checkout_identity_matches_local_package(self):
        self.assertEqual(runner.normalized_identity(self.root), "renamed.checkout")
        runner.verify_manifests(self.root, self.product, *self.manifests())

    def test_changed_target_semantics_fail_closed(self):
        for field, value in (("resources", ["fixture"]), ("settings", [{"define": "DIFFERENT"}]),
                             ("exclude", ["Example.swift"]), ("pluginUsages", ["Plugin"]),
                             ("packageAccess", False), ("futureCompilerOption", True)):
            with self.subTest(field=field):
                full, scoped = self.manifests()
                scoped["targets"][0][field] = value
                with self.assertRaisesRegex(ValueError, "resources/excludes/settings/plugins/conditions"):
                    runner.verify_manifests(self.root, self.product, full, scoped)

    def test_platform_and_language_mode_drift_fail_closed(self):
        for field in ("platforms", "swiftLanguageVersions", "futurePackageOption"):
            full, scoped = self.manifests()
            scoped[field] = ["different"]
            with self.assertRaisesRegex(ValueError, "tools/platform/language"):
                runner.verify_manifests(self.root, self.product, full, scoped)

    def test_conditional_or_aliased_dependencies_fail_closed(self):
        full, scoped = self.manifests()
        scoped["targets"][0]["dependencies"][0]["product"][-1] = {"platformNames": ["macos"]}
        with self.assertRaisesRegex(ValueError, "conditional/aliased"):
            runner.verify_manifests(self.root, self.product, full, scoped)

    def test_copied_or_different_production_package_rejected(self):
        full, scoped = self.manifests()
        scoped["dependencies"][0]["fileSystem"][0]["path"] = str(self.root / "mirror")
        with self.assertRaisesRegex(ValueError, "different production package"):
            runner.verify_manifests(self.root, self.product, full, scoped)

    def test_no_new_production_target_allowed_in_consumer(self):
        full, scoped = self.manifests()
        scoped["targets"].append({"name": self.product, "type": "regular"})
        with self.assertRaisesRegex(ValueError, "inventory"):
            runner.verify_manifests(self.root, self.product, full, scoped)

    def test_described_sources_match_original_bytes(self):
        inventory = runner.source_inventory(self.root, self.product)
        runner.verify_descriptions(self.root, self.product, *self.descriptions(), inventory)
        (self.source / "Example.swift").write_text("changed")
        with self.assertRaisesRegex(ValueError, "contents"):
            runner.verify_descriptions(self.root, self.product, *self.descriptions(), inventory)

    def test_missing_discovered_source_rejected(self):
        full, scoped = self.descriptions()
        scoped["targets"][0]["sources"] = []
        with self.assertRaisesRegex(ValueError, "source inventory"):
            runner.verify_descriptions(self.root, self.product, full, scoped, runner.source_inventory(self.root, self.product))

    def test_path_sensitive_tests_and_fixture_resources_need_new_review(self):
        (self.source / "Example.swift").write_text("let root = #filePath\n")
        with self.assertRaisesRegex(ValueError, "source-location"):
            runner.source_inventory(self.root, self.product)
        (self.source / "Example.swift").write_text("import Testing\n")
        (self.source / "fixture.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "fixture/resource"):
            runner.source_inventory(self.root, self.product)

    def test_inner_source_symlink_and_repointed_target_rejected(self):
        (self.source / "Alias.swift").symlink_to(self.source / "Example.swift")
        with self.assertRaisesRegex(ValueError, "unreviewed symlink"):
            runner.source_inventory(self.root, self.product)
        (self.source / "Alias.swift").unlink()
        linked = self.package / "Tests" / self.target
        linked.unlink()
        linked.mkdir()
        with self.assertRaisesRegex(ValueError, "exact original"):
            runner.source_inventory(self.root, self.product)

    def test_pin_revision_drift_rejected(self):
        lock_path = self.package / "Package.resolved"
        lock = json.loads(lock_path.read_text())
        lock["pins"][0]["state"]["revision"] = "b" * 40
        lock_path.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "pins differ"):
            runner.fingerprint(self.root, self.product, "Swift", self.environment())

    def test_toolchain_environment_captures_exact_versions_without_runner_paths(self):
        calls = []
        def output(command, **kwargs):
            calls.append(command)
            return self.tool_output(command)
        environment = runner.toolchain_environment(output)
        self.assertEqual(environment, self.environment())
        self.assertEqual(len(calls), 5)
        self.assertNotIn("/", json.dumps(environment))

    def test_missing_unknown_or_malformed_environment_cannot_qualify(self):
        cases = [None, {}, {**self.environment(), "schema": True}, {**self.environment(), "schema": 2},
                 {**self.environment(), "architecture": "aarch64"},
                 {**self.environment(), "sdk_build": "/Applications/Xcode.app"},
                 {**self.environment(), "macos_version": "unknown"},
                 {**self.environment(), "extra": "unreviewed"}]
        for environment in cases:
            with self.subTest(environment=environment), self.assertRaises(ValueError):
                runner.validate_toolchain_environment(environment)
        with self.assertRaisesRegex(ValueError, "xcodebuild"):
            runner.toolchain_environment(lambda *a, **k: "Xcode version unavailable")

    def test_environment_change_during_qualification_never_produces_success(self):
        changed = {**self.environment(), "sdk_build": "25F43"}
        with patch.object(runner, "toolchain_environment", side_effect=[self.environment(), changed]):
            with self.assertRaisesRegex(ValueError, "changed during qualification"):
                self.qualify()

    def test_changed_runtime_environment_requires_requalification(self):
        (self.package / "qualification.json").write_text(json.dumps(self.qualify()))
        changes = {"xcode_version": "26.7", "xcode_build": "17F65", "sdk_version": "26.6",
                   "sdk_build": "25F43", "macos_version": "26.5.2", "architecture": "x86_64"}
        def output(command, **kwargs):
            return "tracked" if command[0] == "git" else self.tool_output(command)
        for field, value in changes.items():
            with self.subTest(field=field), \
                 patch.object(runner, "toolchain_environment", return_value={**self.environment(), field: value}), \
                 patch.object(runner, "inspect") as inspected:
                with self.assertRaisesRegex(ValueError, "Xcode/SDK/macOS/architecture"):
                    runner.prepare(self.root, self.product, check_output=output)
                inspected.assert_not_called()

    def test_bootstrap_uses_list_subcommand_without_execution_options(self):
        binaries = self.root / "fake-bin"
        binaries.mkdir()
        xcrun = binaries / "xcrun"
        xcrun.write_text("#!/bin/sh\n[ \"$1 $2 $3\" = \"swift test list\" ] || exit 64\n"
                         "for arg do case \"$arg\" in --no-parallel|--list-tests) exit 64;; esac; done\n"
                         "printf 'InnoDISwiftUITests.Suite/example()\\n'\n")
        xcrun.chmod(0o755)
        python = binaries / "python3"
        python.write_text("#!/bin/sh\nexit 0\n")
        python.chmod(0o755)
        environment = {**os.environ, "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                       "RUNNER_TEMP": str(self.root)}
        subprocess.run(["bash", str(ROOT / "Tools/qualify-ci-product-tests.sh")],
                       cwd=self.root, env=environment, check=True)
        self.assertIn("InnoDISwiftUITests.Suite/example()",
                      (self.root / "ci-test-qualification/full-list.txt").read_text())

    def test_qualification_runs_real_test_command_before_discovery(self):
        calls = []
        proof = self.qualify(run=lambda command, **kwargs: calls.append((command, kwargs)))
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0][:3], ["xcrun", "swift", "test"])
        self.assertIn("--force-resolved-versions", calls[0][0])
        self.assertIn("--scratch-path", calls[0][0])
        self.assertNotIn("--filter", calls[0][0])
        self.assertTrue(calls[0][1]["check"])
        self.assertEqual(proof["execution"], {"result": "success", "flags": runner.TEST_FLAGS})

    def test_fresh_build_evidence_requires_exact_compiled_closure(self):
        scratch, description, modules = self.build_fixture()
        evidence = self.root / "evidence"
        result = runner.verify_build_closure(self.root, self.product, self.inspected(), scratch, evidence)
        self.assertEqual(result["first_party_modules"], runner.expected_modules(self.product, self.inspected()))
        self.assertEqual(len(result["compiled_module_paths"]), 5)
        inventory = json.loads((evidence / "module-inventory.json").read_text())
        self.assertEqual(inventory["actual_modules"], result["first_party_modules"])
        self.assertEqual((evidence / description.relative_to(scratch)).read_bytes(), description.read_bytes())
        (modules / (self.product + ".swiftmodule")).unlink()
        with self.assertRaisesRegex(ValueError, "actual compiled"):
            runner.verify_build_closure(self.root, self.product, self.inspected(), scratch)

    def test_available_unexecuted_commands_do_not_claim_compilation(self):
        scratch, description_path, modules = self.build_fixture()
        value = json.loads(description_path.read_text())
        value["swiftFrontendCommands"]["other"] = {"moduleName": "OtherTests"}
        description_path.write_text(json.dumps(value))
        proof = runner.verify_build_closure(self.root, self.product, self.inspected(), scratch)
        self.assertIn("OtherTests", proof["all_planned_modules"])
        self.assertNotIn("OtherTests", proof["first_party_modules"])
        (modules / "OtherTests.swiftmodule").write_bytes(b"unrelated compilation")
        with self.assertRaisesRegex(ValueError, "actual compiled"):
            runner.verify_build_closure(self.root, self.product, self.inspected(), scratch)

    def test_planned_commands_must_cover_actual_selected_modules(self):
        scratch, description_path, _ = self.build_fixture()
        value = json.loads(description_path.read_text())
        del value["swiftCommands"]["C." + self.product]
        description_path.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "planned commands omit"):
            runner.verify_build_closure(self.root, self.product, self.inspected(), scratch)

    def test_unrelated_actual_artifact_rejected_even_without_planned_command(self):
        scratch, _, modules = self.build_fixture()
        (modules / "OtherTests.swiftmodule").write_bytes(b"unrelated fixture")
        with self.assertRaisesRegex(ValueError, "actual compiled"):
            runner.verify_build_closure(self.root, self.product, self.inspected(), scratch)

    def test_unknown_build_format_retains_raw_evidence_and_rejects(self):
        scratch, description, _ = self.build_fixture()
        description.write_text('{"newBuildBackend": {}}')
        evidence = self.root / "failed-evidence"
        with self.assertRaisesRegex(ValueError, "unrecognized native"):
            runner.verify_build_closure(self.root, self.product, self.inspected(), scratch, evidence)
        self.assertEqual((evidence / description.relative_to(scratch)).read_bytes(), description.read_bytes())

    def test_external_dependency_and_test_glue_modules_allowed(self):
        names = runner.expected_modules(self.product, self.inspected()) + [
            "SwiftSyntax", self.product + "ProductTestsPackageTests"
        ]
        scratch, _, _ = self.build_fixture(names)
        result = runner.verify_build_closure(self.root, self.product, self.inspected(), scratch)
        self.assertEqual(result["first_party_modules"], runner.expected_modules(self.product, self.inspected()))
        self.assertEqual(result["all_planned_modules"], sorted(names))

    def test_failed_test_execution_never_produces_qualification(self):
        def fail(command, **kwargs):
            raise subprocess.CalledProcessError(1, command)
        with self.assertRaises(subprocess.CalledProcessError):
            self.qualify(run=fail)

    def test_empty_mismatched_or_unrelated_discovery_rejected(self):
        for scoped in ("warning: no tests\n", self.target + ".Suite/extra()\n", self.target + ".Suite/example()\nOtherTests.Suite/other()\n"):
            with self.subTest(scoped=scoped), self.assertRaises(ValueError):
                self.qualify(scoped_list=scoped)
        with self.assertRaisesRegex(ValueError, "every original test target"):
            self.qualify(full_list=self.target + ".Suite/example()\n")

    def test_missing_committed_qualification_cannot_prepare(self):
        def untracked(command, **kwargs):
            raise subprocess.CalledProcessError(1, command)
        with self.assertRaises(subprocess.CalledProcessError):
            runner.prepare(self.root, self.product, check_output=untracked)

    def test_changed_source_invalidates_qualification(self):
        original = runner.fingerprint(self.root, self.product, "Swift", self.environment())
        (self.source / "Example.swift").write_text("import Testing\n@Test func newTest() {}\n")
        self.assertNotEqual(original, runner.fingerprint(self.root, self.product, "Swift", self.environment()))

    def test_prepare_requires_current_executed_qualification_and_live_semantics(self):
        proof = self.qualify()
        qualification = self.package / "qualification.json"
        qualification.write_text(json.dumps(proof))
        calls = []
        def output(command, **kwargs):
            calls.append(command)
            return "tracked" if command[0] == "git" else self.tool_output(command)
        with patch.object(runner, "inspect", return_value=self.inspected()) as inspected:
            result = runner.prepare(self.root, self.product, check_output=output)
            inspected.assert_called_once()
        self.assertEqual(sum(command[0] == "git" for command in calls), 3)
        self.assertEqual(result["test_arguments"], ["--package-path", str(self.package), "--force-resolved-versions"])
        calls.clear()
        static_proof = runner.verify_qualification(self.root, self.product, check_output=output)
        self.assertEqual(static_proof["qualification_sha256"], runner.digest(qualification))
        self.assertTrue(all(command[0] == "git" for command in calls))
        self.assertNotIn("test_arguments", static_proof)
        for field, value in (("execution", {"result": "not-run"}), ("discovered_tests", [])):
            modified = copy.deepcopy(proof)
            modified[field] = value
            qualification.write_text(json.dumps(modified))
            with self.assertRaises(ValueError):
                runner.prepare(self.root, self.product, check_output=output)
        qualification.write_text(json.dumps(proof))
        (self.package / "Package.swift").write_text("changed consumer manifest")
        with self.assertRaisesRegex(ValueError, "stale"):
            runner.prepare(self.root, self.product, check_output=output)


if __name__ == "__main__":
    unittest.main()
