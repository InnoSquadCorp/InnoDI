#!/usr/bin/env python3
"""Exercise the production Xcode plugin and output router with a small tool.

The coordinator probe makes compile ordering, SDK isolation, incremental
invalidation, report classification and failing build gates observable. Actual
graph semantics remain covered by the coordinator and consumer test suites.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
FIXTURE = REPO / "Tests/Fixtures/NativePluginConsumer"
REPORT = "dag-validation-metrics.json"
COORDINATOR = r'''import Foundation
let arguments = try parseValidationCoordinatorArguments()
let output = URL(fileURLWithPath: arguments.outputDirectoryPath, isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
if ProcessInfo.processInfo.environment["INNODI_LOCK_TIMEOUT"] == "probe-failure" {
    fputs("native-plugin-probe-forced-failure\n", stderr)
    exit(42)
}
let report = output.appending(path: "dag-validation-metrics.json")
let previous = (try? Data(contentsOf: report)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Int] }
try JSONSerialization.data(withJSONObject: ["invocations": (previous?["invocations"] ?? 0) + 1]).write(to: report)
let requestedInput = arguments.xcodeSourceKind == .clang
    ? ("_InnoDIDAGValidation.generated.h", "// validated\n")
    : ("_InnoDIDAGValidation.generated.swift", "public enum PluginGate { public static let validated = 42 }\n")
for (name, content) in [requestedInput] {
    let file = output.appending(path: name)
    if (try? String(contentsOf: file, encoding: .utf8)) != content {
        try content.write(to: file, atomically: true, encoding: .utf8)
    }
}
'''


def write(root, name, text):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def build(root, label, scheme="ProbeApp", succeeds=True):
    command = ["xcodebuild", "-project", "Probe.xcodeproj", "-scheme", scheme,
               "-destination", "generic/platform=iOS", "-derivedDataPath", "DerivedData",
               "-skipPackagePluginValidation", "build"]
    environment = dict(os.environ)
    environment.pop("INNODI_DISABLE_BUILD_VALIDATION", None)
    environment.pop("INNODI_LOCK_TIMEOUT", None)
    if not succeeds:
        environment["INNODI_LOCK_TIMEOUT"] = "probe-failure"
    result = subprocess.run(command, cwd=root, env=environment, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (root / f"{label}.log").write_text(result.stdout)
    if succeeds and result.returncode:
        raise RuntimeError(f"{label} failed:\n{result.stdout[-8000:]}")
    if not succeeds and (not result.returncode or "native-plugin-probe-forced-failure" not in result.stdout):
        raise RuntimeError(f"{label} did not stop at the validation gate:\n{result.stdout[-8000:]}")
    if "will be run during every build because it does not specify any outputs" in result.stdout:
        raise RuntimeError(f"{label} retained the missing-output warning")
    if "Multiple commands produce" in result.stdout:
        raise RuntimeError(f"{label} retained an output collision")


def reports(root):
    return {str(p.relative_to(root)): json.loads(p.read_text())["invocations"]
            for p in (root / "DerivedData/Build/Intermediates.noindex/BuildToolPluginIntermediates").rglob(REPORT)}


def check(root):
    project = root / "Probe.xcodeproj"
    schemes = project / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True)
    # Xcode accepts XML property lists as well as OpenStep project files.
    (project / "project.pbxproj").write_text((FIXTURE / "project.json").read_text())
    subprocess.run(["plutil", "-convert", "xml1", str(project / "project.pbxproj")], check=True)
    for name in ["ProbeApp.xcscheme", "Shared.xcscheme"]:
        shutil.copyfile(FIXTURE / name, schemes / name)
    for name in ["ProbeApp-Info.plist", "ProbeWatch-Info.plist"]:
        dest = root / "Derived/InfoPlists" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(FIXTURE / name, dest)
    write(root, "Shared/Shared.swift", "public enum Shared { public static let value = String(PluginGate.validated) }\n")
    app = "import SwiftUI\nimport Shared\n@main struct ProbeApp: App { var body: some Scene { WindowGroup { Text(Shared.value) } } }\n"
    write(root, "App/App.swift", app)
    write(root, "Watch/App.swift", app)
    write(root, "ProbePlugin/Package.swift", '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ProbePlugin", platforms: [.macOS(.v15)], products: [.plugin(name: "InnoDIDAGValidationPlugin", targets: ["InnoDIDAGValidationPlugin"])], targets: [.executableTarget(name: "InnoDI-DAGValidationCoordinator"), .plugin(name: "InnoDIDAGValidationPlugin", capability: .buildTool(), dependencies: ["InnoDI-DAGValidationCoordinator"])])
''')
    write(root, "ProbePlugin/Plugins/InnoDIDAGValidationPlugin/plugin.swift",
          (REPO / "Plugins/InnoDIDAGValidationPlugin/plugin.swift").read_text())
    tool = "ProbePlugin/Sources/InnoDI-DAGValidationCoordinator/"
    write(root, tool + "main.swift", COORDINATOR)
    for name in ["ValidationCoordinatorArguments.swift", "XcodePluginOutputDirectory.swift"]:
        write(root, tool + name, (REPO / "Sources/InnoDIBuildSupport" / name).read_text())
    build(root, "swift-cold")
    cold = reports(root)
    if len(cold) != 2 or not any("iphoneos" in p for p in cold) or not any("watchos" in p for p in cold):
        raise RuntimeError(f"Expected distinct iOS/watchOS reports, got {cold}")
    markers = {p: p.stat().st_mtime_ns for p in (root / "DerivedData").rglob("_InnoDIDAGValidation.generated.swift")}
    build(root, "swift-warm")
    warm = reports(root)
    # Xcode may recreate the native script identity and invoke it on a warm
    # build. Stable outputs must survive either scheduling policy unchanged.
    if set(warm) != set(cold) or any(p.stat().st_mtime_ns != time for p, time in markers.items()):
        raise RuntimeError("Warm native build changed output identity or touched an unchanged compile input")
    source = root / "Shared/Shared.swift"
    source.write_text(source.read_text() + "// changed input\n")
    build(root, "swift-changed")
    changed = reports(root)
    if changed != {p: count + 1 for p, count in warm.items()}:
        raise RuntimeError(f"Source change did not invalidate both SDK variants: {changed}")
    source.write_text(source.read_text() + "// failing input\n")
    build(root, "swift-failure", succeeds=False)
    bundled = [str(p) for p in (root / "DerivedData/Build/Products").rglob(REPORT)]
    if bundled:
        raise RuntimeError(f"Validation reports were bundled: {bundled}")
    # A Clang-only native target must not receive a generated Swift input.
    doc = json.loads((FIXTURE / "project.json").read_text())
    for obj in doc["objects"].values():
        if obj.get("isa") == "PBXFileReference" and obj.get("path") == "Shared.swift":
            obj["path"] = "Shared.c"
            obj["lastKnownFileType"] = "sourcecode.c.c"
    (project / "project.pbxproj").write_text(json.dumps(doc))
    subprocess.run(["plutil", "-convert", "xml1", str(project / "project.pbxproj")], check=True)
    write(root, "Shared/Shared.c", "int shared_value(void) { return 42; }\n")
    build(root, "clang-cold", scheme="Shared")
    print(json.dumps({"root": str(root), "swiftCold": cold, "swiftWarm": warm,
                      "swiftChanged": changed, "failureGate": "passed", "clang": "passed",
                      "bundledReports": bundled}, indent=2))


if __name__ == "__main__":
    # Keep evidence on failure for diagnosis; successful probes may be removed.
    root = Path(tempfile.mkdtemp(prefix="innodi-native-plugin-"))
    print(f"Native plugin evidence: {root}", flush=True)
    check(root)
