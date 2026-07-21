import Foundation
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

        #expect(source.contains("push:\n    branches:\n      - main"))
        #expect(source.contains("permissions:\n  contents: read"))
        #expect(
            source.components(
                separatedBy: "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
            ).count - 1 == 3
        )
        #expect(
            source.components(
                separatedBy: "persist-credentials: false"
            ).count - 1 == 3
        )
        #expect(
            source.contains(
                "swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors"
            )
        )
        #expect(source.contains("swift run --skip-build SampleApp"))
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
