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
                separatedBy: "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5"
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

    @Test("Source and prebuilt plugins share one manifest contract")
    func sourceAndPrebuiltPluginsStayAligned() throws {
        let rootURL = packageRootURL()
        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                "Plugins/InnoDIDAGValidationPlugin/plugin.swift"
            ),
            encoding: .utf8
        )
        let prebuilt = try String(
            contentsOf: rootURL.appendingPathComponent(
                "InnoDIValidationTools/Plugins/"
                    + "InnoDIPrebuiltDAGValidationPlugin/plugin.swift"
            ),
            encoding: .utf8
        )
        let normalizedPrebuilt = prebuilt
            .replacingOccurrences(
                of: "InnoDIPrebuiltDAGValidationPlugin",
                with: "InnoDIDAGValidationPlugin"
            )
            .replacingOccurrences(
                of: "InnoDIPrebuiltDAGValidationCoordinator",
                with: "InnoDI-DAGValidationCoordinator"
            )
            .replacingOccurrences(of: " (prebuilt)", with: "")

        #expect(normalizedPrebuilt == source)
        #expect(source.contains("--analysis-manifest"))
        #expect(source.contains("--state-dir"))
        #expect(source.contains("innodi-dag-validation-state"))
        #expect(!source.contains("\"--root\""))
        #expect(source.contains("workspace-analysis.json"))
    }
}
