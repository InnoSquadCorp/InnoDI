#!/usr/bin/env python3
"""Qualify test-only product consumers without changing the production package.

Only the SwiftUI and Testing leaves have independently reusable test targets.
Every other product, mixed selection, missing lock, or missing qualification
must keep the caller's original full test command. A test filter is never a
compile-scope boundary.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

_api_spec = importlib.util.spec_from_file_location("product_api", Path(__file__).with_name("ci_product_api.py"))
api = importlib.util.module_from_spec(_api_spec)
_api_spec.loader.exec_module(api)

PRODUCTS = {"InnoDISwiftUI": "InnoDISwiftUITests", "InnoDITesting": "InnoDITestingTests"}
SWIFT = ["xcrun", "swift"]
TEST_FLAGS = ["--no-parallel", "-Xswiftc", "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors"]
PATH_SENSITIVE = re.compile(r"#(?:file|sourceLocation)|\b(?:Bundle|FileManager|CommandLine|Process)\b|\bURL\s*\(")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def package_path(root, product):
    if product not in PRODUCTS:
        raise ValueError("product has no qualified standalone test package: " + product)
    return Path(root).resolve() / "Tools/CIProductTests" / product


def source_inventory(root, product):
    root = Path(root).resolve()
    target = PRODUCTS[product]
    original = root / "Tests" / target
    linked = package_path(root, product) / "Tests" / target
    if not linked.is_symlink() or linked.resolve() != original:
        raise ValueError("consumer must link the exact original test directory")
    files = {}
    for path in sorted(original.rglob("*")):
        if path.is_symlink():
            raise ValueError("unreviewed symlink inside original test inputs")
        if path.is_file():
            if path.suffix != ".swift":
                raise ValueError("fixture/resource needs explicit standalone-package review: " + str(path))
            if PATH_SENSITIVE.search(path.read_text()):
                raise ValueError("test has unreviewed source-location or filesystem assumptions: " + str(path))
            files[path.relative_to(original).as_posix()] = digest(path)
    if not files:
        raise ValueError("empty original test target")
    return files


def normalized_identity(root):
    identity = Path(root).resolve().name.lower()
    return identity[:-4] if identity.endswith(".git") else identity


def single_dependency(target, kind, first, second=None):
    dependencies = target.get("dependencies")
    if not isinstance(dependencies, list) or len(dependencies) != 1:
        raise ValueError("test dependency inventory changed")
    item = dependencies[0]
    if set(item) != {kind} or not isinstance(item[kind], list):
        raise ValueError("test dependency representation changed")
    values = item[kind]
    prefix = [first] if second is None else [first, second]
    if values[:len(prefix)] != prefix or any(value is not None for value in values[len(prefix):]):
        raise ValueError("conditional/aliased test dependencies need explicit review")


def verify_manifests(root, product, full, scoped):
    """Compare complete SwiftPM attributes, including future unknown fields."""
    target_name = PRODUCTS[product]
    full_tests = [target for target in full["targets"] if target["name"] == target_name]
    if len(full_tests) != 1 or len(scoped["targets"]) != 1:
        raise ValueError("standalone test target inventory changed")
    original, consumer = full_tests[0], scoped["targets"][0]
    if consumer.get("name") != target_name or original.get("type") != "test":
        raise ValueError("standalone test identity changed")
    single_dependency(original, "byName", product)
    single_dependency(consumer, "product", product, normalized_identity(root))
    if {key: value for key, value in original.items() if key != "dependencies"} != {
        key: value for key, value in consumer.items() if key != "dependencies"
    }:
        raise ValueError("test resources/excludes/settings/plugins/conditions differ")
    ignored = {"name", "path", "packageKind", "products", "targets", "dependencies"}
    if {key: value for key, value in full.items() if key not in ignored} != {
        key: value for key, value in scoped.items() if key not in ignored
    }:
        raise ValueError("package tools/platform/language settings differ")
    if scoped.get("products"):
        raise ValueError("consumer must contain tests only")
    products = [entry for entry in full["products"] if entry["name"] == product]
    if len(products) != 1 or products[0]["targets"] != [product]:
        raise ValueError("production product target inventory changed")
    dependencies = scoped["dependencies"]
    if len(dependencies) != 1 or set(dependencies[0]) != {"fileSystem"}:
        raise ValueError("consumer must depend only on the unchanged local root package")
    local = dependencies[0]["fileSystem"]
    if len(local) != 1 or Path(local[0]["path"]).resolve() != Path(root).resolve():
        raise ValueError("consumer resolves a different production package")
    if local[0].get("identity") != normalized_identity(root):
        raise ValueError("consumer production package identity differs")


def verify_descriptions(root, product, full, scoped, inventory):
    target_name = PRODUCTS[product]
    originals = [target for target in full["targets"] if target["name"] == target_name]
    consumers = scoped["targets"]
    if len(originals) != 1 or len(consumers) != 1 or consumers[0]["name"] != target_name:
        raise ValueError("SwiftPM describe discovered unexpected targets")
    for base, target in ((Path(root), originals[0]), (package_path(root, product), consumers[0])):
        if target.get("type") != "test" or set(target["sources"]) != set(inventory):
            raise ValueError("SwiftPM discovery source inventory differs")
        source_root = Path(target["path"])
        if not source_root.is_absolute():
            source_root = base / source_root
        if source_root.resolve() != Path(root).resolve() / "Tests" / target_name:
            raise ValueError("SwiftPM source root differs")
        for relative, expected in inventory.items():
            if digest(source_root / relative) != expected:
                raise ValueError("SwiftPM source contents differ")


def inspect(root, product, check_output=subprocess.check_output):
    root = Path(root).resolve()
    package = package_path(root, product)
    inventory = source_inventory(root, product)
    def read(path, arguments):
        return json.loads(check_output([*SWIFT, "package", "--package-path", str(path), *arguments], text=True))
    full = read(root, ["dump-package"])
    scoped = read(package, ["dump-package"])
    full_description = read(root, ["describe", "--type", "json"])
    scoped_description = read(package, ["describe", "--type", "json"])
    verify_manifests(root, product, full, scoped)
    verify_descriptions(root, product, full_description, scoped_description, inventory)
    return {"product": product, "test_target": PRODUCTS[product], "sources": inventory,
            "root_dump": full, "consumer_dump": scoped,
            "root_description": full_description, "consumer_description": scoped_description}


def locked_pins(path):
    lock = json.loads(Path(path).read_text())
    if lock.get("version") not in (2, 3) or not isinstance(lock.get("pins"), list) or not lock["pins"]:
        raise ValueError("missing versioned dependency pins")
    pins = lock["pins"]
    identities = [pin["identity"] for pin in pins]
    if len(set(identities)) != len(pins):
        raise ValueError("duplicate dependency pins")
    for pin in pins:
        if not re.fullmatch(r"[0-9a-f]{40}", pin.get("state", {}).get("revision", "")):
            raise ValueError("dependency is not pinned to an exact revision")
    return sorted(pins, key=lambda pin: pin["identity"])


def fingerprint(root, product, toolchain):
    root = Path(root).resolve()
    package = package_path(root, product)
    if locked_pins(root / "Package.resolved") != locked_pins(package / "Package.resolved"):
        raise ValueError("root and standalone test package dependency pins differ")
    paths = [root / "Package.swift", root / "Package.resolved", package / "Package.swift",
             package / "Package.resolved", root / "Tools/ci_product_tests.py",
             root / "Tools/ci_product_api.py", root / "Tools/check-public-api.py",
             root / "Tools/public-api-baseline.json"]
    return {"product": product, "test_target": PRODUCTS[product], "platform": "macOS",
            "toolchain": toolchain.strip(), "source_inventory": source_inventory(root, product),
            "files": {path.relative_to(root).as_posix(): digest(path) for path in paths}}


def discovery(lines, targets):
    found = {target: set() for target in targets}
    for line in lines.splitlines():
        value = line.strip()
        for target in targets:
            if value.startswith(target + ".") and "/" in value:
                found[target].add(value)
    return found


def expected_modules(product, inspected):
    targets = {target["name"]: target for target in inspected["root_dump"]["targets"]}
    pending = [product, PRODUCTS[product]]
    included = set()
    while pending:
        name = pending.pop()
        if name in included:
            continue
        included.add(name)
        target = targets[name]
        if target["type"] not in ("regular", "macro", "test"):
            raise ValueError("unreviewed first-party target kind in test closure")
        for dependency in target["dependencies"]:
            if set(dependency) == {"product"}:
                continue
            kind = "byName" if "byName" in dependency else "target"
            if set(dependency) != {kind} or dependency[kind][0] not in targets or any(dependency[kind][1:]):
                raise ValueError("unreviewed conditional/unknown first-party dependency")
            pending.append(dependency[kind][0])
    return sorted(re.sub(r"[^A-Za-z0-9_]", "_", name) for name in included)


def verify_build_closure(root, product, inspected, scratch, evidence_dir=None):
    """Read native SwiftPM build descriptions and actual fresh module outputs.

    SwiftPM's SwiftCompilerTool/SwiftFrontendTool encode moduleName; the native
    BuildDescription serializes them in swiftCommands/swiftFrontendCommands.
    Other build backends or unknown formats need their own evidence adapter.
    """
    scratch = Path(scratch).resolve()
    descriptions = sorted({path.resolve() for pattern in ("description.json", "plugin-tools-description.json")
                           for path in scratch.rglob(pattern)
                           if "checkouts" not in path.relative_to(scratch).parts})
    if not descriptions:
        raise ValueError("no native SwiftPM build description; compilation scope is unverified")
    expected = set(expected_modules(product, inspected))
    all_first_party = {re.sub(r"[^A-Za-z0-9_]", "_", target["name"])
                       for target in inspected["root_dump"]["targets"]}
    package_name = inspected["consumer_dump"]["name"]
    generated = {package_name + "PackageTests", package_name + "PackageDiscoveredTests"}
    planned, raw_digests, commands = set(), {}, 0
    for path in descriptions:
        if not path.is_relative_to(scratch):
            raise ValueError("build description escapes fresh scratch")
        relative = path.relative_to(scratch).as_posix()
        raw_digests[relative] = digest(path)
        if evidence_dir is not None:
            destination = Path(evidence_dir) / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
        payload = json.loads(path.read_text())
        if not isinstance(payload, dict) or not all(isinstance(payload.get(key), dict) for key in ("swiftCommands", "swiftFrontendCommands")):
            raise ValueError("unrecognized native SwiftPM build description schema")
        for key in ("swiftCommands", "swiftFrontendCommands"):
            for command in payload[key].values():
                if not isinstance(command, dict) or not isinstance(command.get("moduleName"), str):
                    raise ValueError("unrecognized native Swift compiler command")
                module = command["moduleName"]
                if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", module):
                    raise ValueError("invalid built module identity")
                commands += 1
                planned.add(module)
    if not commands:
        raise ValueError("empty native Swift compiler command inventory")
    if planned & all_first_party != expected:
        raise ValueError("planned first-party modules differ from selected product closure: " + repr(sorted(planned & all_first_party)))
    unknown = {name for name in planned if name.startswith("InnoDI")} - all_first_party - generated
    if unknown:
        raise ValueError("unreviewed generated/aliased first-party module: " + repr(sorted(unknown)))
    built = set()
    artifacts = []
    for path in sorted(scratch.rglob("*.swiftmodule")):
        if "checkouts" in path.relative_to(scratch).parts:
            continue
        if path.stem in all_first_party:
            if not path.resolve().is_relative_to(scratch):
                raise ValueError("compiled module escapes fresh scratch")
            built.add(path.stem)
            artifacts.append(path.relative_to(scratch).as_posix())
    if built != expected:
        raise ValueError("actual compiled first-party modules differ from selected product closure: " + repr(sorted(built)))
    return {"schema": "swiftpm-native-v1", "fresh_scratch": True,
            "first_party_modules": sorted(built), "all_planned_modules": sorted(planned),
            "compiled_module_paths": artifacts, "raw_description_sha256": raw_digests}


def qualify(root, product, full_list, check_output=subprocess.check_output, run=subprocess.run,
            evidence_dir=None, full_api_contract=None):
    if full_api_contract is None:
        raise ValueError("qualification requires the successful full-package API contract")
    inspected = inspect(root, product, check_output)
    # Generate qualification only after a real compile AND successful execution.
    # Discovery on its own is insufficient evidence that this package works.
    package = package_path(root, product)
    if locked_pins(Path(root) / "Package.resolved") != locked_pins(package / "Package.resolved"):
        raise ValueError("root and consumer pins differ before qualification")
    with tempfile.TemporaryDirectory(prefix="innodi-product-qualification-") as scratch:
        common = ["--package-path", str(package), "--scratch-path", scratch, "--force-resolved-versions"]
        command = [*SWIFT, "test", *common, *TEST_FLAGS]
        run(command, cwd=Path(root).resolve(), check=True)
        build_closure = verify_build_closure(root, product, inspected, scratch, evidence_dir)
        scoped_list = check_output([*SWIFT, "test", *common, "--skip-build", "--list-tests", *TEST_FLAGS], text=True)
        public_api = api.verify(root, product, scratch, full_api_contract,
                                Path(evidence_dir) / "public-api" if evidence_dir is not None else None,
                                run=run, check_output=check_output)
    targets = {target["name"] for target in inspected["root_dump"]["targets"] if target["type"] == "test"}
    full = discovery(full_list, targets)
    scoped = discovery(scoped_list, targets)
    target = PRODUCTS[product]
    if any(not values for values in full.values()):
        raise ValueError("full-package discovery must include every original test target")
    if not scoped[target] or scoped[target] != full[target]:
        raise ValueError("full and scoped discovered test identities differ")
    if any(values for name, values in scoped.items() if name != target):
        raise ValueError("scoped discovery includes unrelated test targets")
    version = check_output([*SWIFT, "--version"], text=True)
    return {"schema": 1, "contract": fingerprint(root, product, version),
            "execution": {"result": "success", "flags": TEST_FLAGS},
            "build_closure": build_closure,
            "public_api": public_api,
            "discovered_tests": sorted(scoped[target]),
            "discovery_sha256": {"full": hashlib.sha256(full_list.encode()).hexdigest(),
                                 "scoped": hashlib.sha256(scoped_list.encode()).hexdigest()}}


def reviewed_modules(product):
    return sorted([product, PRODUCTS[product], "InnoDI", "InnoDIMacros", "InnoDICore"])


def verify_qualification(root, product, check_output=subprocess.check_output):
    """Compiler-free committed-evidence validation for CI Plan/CI Required.

    This returns identity evidence only. It does not authorize execution or a
    skip: prepare() must still verify the current real toolchain and manifests.
    """
    root = Path(root).resolve()
    package = package_path(root, product)
    qualification_path = package / "qualification.json"
    required = [root / "Package.resolved", package / "Package.resolved", qualification_path]
    for path in required:
        check_output(["git", "-C", str(root), "ls-files", "--error-unmatch", str(path.relative_to(root))], text=True)
    qualification = json.loads(qualification_path.read_text())
    version = qualification.get("contract", {}).get("toolchain")
    if not isinstance(version, str) or not version.strip():
        raise ValueError("qualification has no recorded toolchain")
    if qualification.get("schema") != 1 or qualification.get("contract") != fingerprint(root, product, version):
        raise ValueError("missing or stale real-toolchain test qualification")
    if qualification.get("execution") != {"result": "success", "flags": TEST_FLAGS}:
        raise ValueError("qualification has no successful strict test execution")
    tests = qualification.get("discovered_tests")
    if not isinstance(tests, list) or not tests or tests != sorted(set(tests)) or any(
        not isinstance(test, str) or not test.startswith(PRODUCTS[product] + ".") for test in tests
    ):
        raise ValueError("invalid test discovery qualification")
    closure = qualification.get("build_closure", {})
    raw_digests = closure.get("raw_description_sha256", {})
    if closure.get("schema") != "swiftpm-native-v1" or closure.get("fresh_scratch") is not True or \
       closure.get("first_party_modules") != reviewed_modules(product) or not raw_digests or \
       any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in raw_digests.values()):
        raise ValueError("qualification has no verified fresh compilation closure")
    public_api = qualification.get("public_api", {})
    baseline = api.selected_graph(json.loads((root / "Tools/public-api-baseline.json").read_text()), product)
    if public_api.get("schema") != "selected-api-v1" or public_api.get("product") != product or \
       public_api.get("baseline_match") is not True or public_api.get("full_current_match") is not True or \
       public_api.get("normalized_sha256") != api.graph_digest(baseline):
        raise ValueError("qualification has no equivalent selected public API verification")
    return {"product": product, "test_target": PRODUCTS[product],
            "qualification_sha256": digest(qualification_path), "toolchain": version}


def prepare(root, product, temporary=None, check_output=subprocess.check_output):
    """Return live-verified test arguments; caller handles any error as full fallback."""
    root = Path(root).resolve()
    package = package_path(root, product)
    proof = verify_qualification(root, product, check_output)
    version = check_output([*SWIFT, "--version"], text=True).strip()
    if proof["toolchain"] != version:
        raise ValueError("current Swift toolchain differs from qualified toolchain")
    inspected = inspect(root, product, check_output)
    if expected_modules(product, inspected) != reviewed_modules(product):
        raise ValueError("live product compilation closure changed")
    return {"package_path": str(package), "product": product, "test_target": PRODUCTS[product],
            "qualification_sha256": proof["qualification_sha256"], "source_inventory": source_inventory(root, product),
            "test_arguments": ["--package-path", str(package), "--force-resolved-versions"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inspect", "qualify", "prepare"))
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--product", choices=tuple(PRODUCTS))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--full-list", type=Path)
    parser.add_argument("--full-api-contract", type=Path)
    args = parser.parse_args()
    if args.action == "inspect":
        args.output.mkdir(parents=True, exist_ok=True)
        for product in [args.product] if args.product else PRODUCTS:
            result = inspect(args.root, product)
            (args.output / (product + ".json")).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        return
    if not args.product:
        parser.error("--product is required for " + args.action)
    if args.action == "qualify":
        if not args.full_list or not args.full_api_contract:
            parser.error("qualify requires original --full-list and --full-api-contract files")
        if args.output.exists():
            raise ValueError("qualification output already exists; stale evidence cannot be reused")
        result = qualify(args.root, args.product, args.full_list.read_text(),
                         evidence_dir=args.output.parent / (args.product + "-build-evidence"),
                         full_api_contract=args.full_api_contract)
    else:
        result = prepare(args.root, args.product)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
