import Foundation
import InnoDITestSupport
import Testing

@Suite("Build plugin manifest parity")
struct PluginManifestParityTests {
    @Test("Example CI validates main with read-only checkouts")
    func exampleCIValidatesMainWithReadOnlyCheckouts() throws {
        let source = try String(
            contentsOf: packageRootURL().appendingPathComponent(
                ".github/workflows/examples.yml"
            ),
            encoding: .utf8
        )

        #expect(source.contains("  workflow_call:"))
        let ci = try String(contentsOf: packageRootURL().appendingPathComponent(".github/workflows/macro-tests.yml"), encoding: .utf8)
        #expect(ci.contains("push:\n    branches:\n      - main"))
        #expect(ci.contains("uses: ./.github/workflows/examples.yml"))
        #expect(source.contains("permissions:\n  contents: read"))
        #expect(try hasFourMatchingCheckoutPins(source))
        #expect(
            source.components(
                separatedBy: "persist-credentials: false"
            ).count - 1 == 4
        )
        // Commands now live in the admitted adapter recipe. Check both the
        // workflow wiring and the actual full-mode argv, not stale YAML text.
        let flags = ["-Xswiftc", "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors"]
        let recipes = try fullExampleRecipes()
        for unit in ["SampleApp", "SwiftUIExample", "PreviewInjectionExample"] {
            #expect(source.contains("ci_product_execution.py build --kind di-example --units \(unit)"))
            #expect(source.contains("ci_product_execution.py verify --kind di-example --units \(unit)"))
            var expected = [["swift", "build"] + flags, ["swift", "test"] + flags]
            if unit == "SampleApp" {
                expected.append(["swift", "run", "--skip-build", "SampleApp"])
            }
            #expect(recipes[unit] == expected)
        }
    }

    @Test("Checkout parity rejects floating, missing and divergent pins")
    func checkoutPinNegativeControls() throws {
        let pin = String(repeating: "a", count: 40)
        let other = String(repeating: "b", count: 40)
        let line = "        uses: actions/checkout@\(pin) # reviewed version\n"
        let good = String(repeating: line, count: 4)
        #expect(try hasFourMatchingCheckoutPins(good))
        #expect(try !hasFourMatchingCheckoutPins(String(repeating: line, count: 3)))
        #expect(try !hasFourMatchingCheckoutPins(String(repeating: line, count: 3) + line.replacingOccurrences(of: pin, with: other)))
        #expect(try !hasFourMatchingCheckoutPins(good.replacingOccurrences(of: pin, with: "v7")))
        #expect(try !hasFourMatchingCheckoutPins(good.replacingOccurrences(of: pin, with: String(pin.dropLast()))))
    }

    @Test("Runnable examples enable DAG validation")
    func runnableExamplesEnableDAGValidation() throws {
        let rootURL = packageRootURL()
        let manifests = [
            "Examples/SampleApp/Package.swift",
            "Examples/SwiftUIExample/Package.swift",
            "Examples/PreviewInjectionExample/Package.swift",
        ]

        for manifest in manifests {
            let source = try String(
                contentsOf: rootURL.appendingPathComponent(manifest),
                encoding: .utf8
            )

            #expect(
                source.contains("InnoDIDAGValidationPlugin"),
                "\(manifest) must enable target-scoped DAG validation"
            )
            #expect(
                source.contains("package: innoDIPackageIdentity"),
                "\(manifest) must resolve dependencies in renamed checkouts"
            )
            #expect(!source.contains("package: \"InnoDI\""))
        }
    }

    @Test("Source plugin uses the workspace-analysis manifest contract")
    func sourcePluginUsesWorkspaceManifest() throws {
        let rootURL = packageRootURL()
        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                "Plugins/InnoDIDAGValidationPlugin/plugin.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains("--analysis-manifest"))
        #expect(source.contains("--state-dir"))
        #expect(source.contains("innodi-dag-validation-state"))
        #expect(!source.contains("\"--root\""))
        #expect(source.contains("workspace-analysis.json"))
        #expect(source.contains("import XcodeProjectPlugin"))
        #expect(source.contains("XcodeBuildToolPlugin"))
        #expect(source.contains("buildSystem: \"xcode\""))
        #expect(source.contains("findTuistWorkspaceRoot"))
        #expect(source.contains("tuistWorkspaceSources"))
        #expect(source.contains("dependencies: []"))
        #expect(source.contains("declaresOutputs: false"))
        #expect(source.contains("ordersSwiftCompilation: primaryTarget is SwiftSourceModuleTarget"))
        #expect(source.contains("outputDirectory.appending(path: \"_InnoDIDAGValidation.generated.swift\")"))
        #expect(source.contains("module-edge hierarchy validation"))
        #expect(
            !FileManager.default.fileExists(
                atPath: rootURL
                    .appendingPathComponent("InnoDIValidationTools")
                    .path
            ),
            "5.1 must not ship an unusable companion-package placeholder"
        )
    }
}

private func hasFourMatchingCheckoutPins(_ source: String) throws -> Bool {
    let regex = try NSRegularExpression(
        pattern: #"(?m)^\s*uses: actions/checkout@([0-9a-f]{40})(?:\s+#.*)?$"#
    )
    let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
    let pins = matches.compactMap { match in
        Range(match.range(at: 1), in: source).map { String(source[$0]) }
    }
    return matches.count == 4 && Set(pins).count == 1
}

private func fullExampleRecipes() throws -> [String: [[String]]] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.currentDirectoryURL = packageRootURL()
    process.arguments = ["python3", "-B", "-c", """
    import importlib.util, json
    from pathlib import Path
    root = Path.cwd()
    spec = importlib.util.spec_from_file_location("ci_product_execution", root / "Tools/ci_product_execution.py")
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    units = ("SampleApp", "SwiftUIExample", "PreviewInjectionExample")
    print(json.dumps({unit: adapter.recipe(root, {"mode": "full"}, "di-example", unit, "macOS", root / ".build/recipe-contract")["commands"] for unit in units}))
    """]
    let result = try runCapturedProcess(process, timeoutSeconds: 30)
    try #require(!result.timedOut && result.exitCode == 0, "\(result.stderr)")
    return try JSONDecoder().decode([String: [[String]]].self, from: Data(result.stdout.utf8))
}
