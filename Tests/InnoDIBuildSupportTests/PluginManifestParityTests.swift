import Foundation
import Testing

@Suite("Build plugin manifest parity")
struct PluginManifestParityTests {
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
        #expect(!source.contains("\"--root\""))
        #expect(source.contains("workspace-analysis.json"))
    }
}
