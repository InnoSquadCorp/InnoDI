import Foundation
import Testing

@testable import InnoDIBuildSupport
@testable import InnoDIWorkspaceAnalysis

/// The build gate validates the DAG through the same target-scoped resolver
/// as `InnoDI-DependencyGraph --analysis-manifest`. Swift makes an
/// `@_exported import` in one file visible to every file of the module, so a
/// container mounted from a sibling-exported module must resolve there too.
@Suite("Exported imports in the build gate")
struct ExportedImportBuildGateTests {
    private static let appSource = """
    import InnoDI

    @DIContainerRole(role: ContainerRole.root)
    struct AppContainer {
        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }
    """

    @Test("A sibling file's exported import resolves the mounted container")
    func siblingExportedImportPasses() async throws {
        let outcome = try await runExportedImportFixture(
            appFiles: [
                "App.swift": Self.appSource,
                "Exports.swift": "@_exported import FeatureKit\n",
            ]
        )

        #expect(outcome.exitCode == 0, Comment(rawValue: outcome.stderr))
        #expect(!outcome.stderr.contains("graph.unresolved-container-reference"))
    }

    @Test("Control: the file's own import resolves the mounted container")
    func ownImportPasses() async throws {
        let outcome = try await runExportedImportFixture(
            appFiles: [
                "App.swift": Self.appSource.replacingOccurrences(
                    of: "import InnoDI\n",
                    with: "import InnoDI\nimport FeatureKit\n"
                ),
                "Exports.swift": "@_exported import FeatureKit\n",
            ]
        )

        #expect(outcome.exitCode == 0, Comment(rawValue: outcome.stderr))
    }

    @Test("Control: a sibling file's plain import still leaves it unresolved")
    func siblingPlainImportFails() async throws {
        let outcome = try await runExportedImportFixture(
            appFiles: [
                "App.swift": Self.appSource,
                "Exports.swift": "import FeatureKit\n",
            ]
        )

        #expect(outcome.exitCode != 0)
        #expect(
            outcome.stderr.contains(
                "[graph.unresolved-container-reference] AppContainer -> FeatureContainer"
            ),
            Comment(rawValue: outcome.stderr)
        )
    }
}

private struct ExportedImportOutcome {
    let exitCode: Int32
    let stderr: String
}

/// Validates target `App` (depending on `FeatureKit`) with a manifest shaped
/// like the build plugin's.
private func runExportedImportFixture(
    appFiles: [String: String]
) async throws -> ExportedImportOutcome {
    let root = try makeTemporaryWorkspaceRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let packageDirectory = root.appendingPathComponent("app", isDirectory: true)
    func sources(
        target: String,
        files: [String: String]
    ) throws -> [WorkspaceAnalysisSource] {
        try files.sorted(by: { $0.key < $1.key }).map { fileName, contents in
            let logicalPath = "Sources/\(target)/\(fileName)"
            let fileURL = packageDirectory.appendingPathComponent(logicalPath)
            try writeSource(contents, to: fileURL)
            return WorkspaceAnalysisSource(
                filePath: fileURL.path,
                logicalPath: logicalPath,
                origin: .declared
            )
        }
    }

    let appID = WorkspaceTargetID.swiftPM(packageIdentity: "app", moduleName: "App")
    let featureID = WorkspaceTargetID.swiftPM(
        packageIdentity: "app",
        moduleName: "FeatureKit"
    )
    let manifest = WorkspaceAnalysisManifest(
        rootPackageIdentity: "app",
        rootPackageDirectory: packageDirectory.path,
        primaryTargetID: appID,
        targets: [
            WorkspaceAnalysisTarget(
                id: appID,
                packageIdentity: "app",
                packageDisplayName: "app",
                packageDirectory: packageDirectory.path,
                targetName: "App",
                moduleName: "App",
                kind: .generic,
                role: .primary,
                sources: try sources(target: "App", files: appFiles),
                dependencies: [
                    WorkspaceAnalysisDependency(
                        kind: .target,
                        name: "FeatureKit",
                        targetIDs: [featureID]
                    )
                ]
            ),
            WorkspaceAnalysisTarget(
                id: featureID,
                packageIdentity: "app",
                packageDisplayName: "app",
                packageDirectory: packageDirectory.path,
                targetName: "FeatureKit",
                moduleName: "FeatureKit",
                kind: .generic,
                role: .dependency,
                sources: try sources(
                    target: "FeatureKit",
                    files: [
                        // A child mounted across modules must be a component.
                        "Feature.swift": """
                        import InnoDI

                        @DIContainerRole(role: ContainerRole.component)
                        public struct FeatureContainer {
                            @Provide(.shared, factory: 1)
                            var value: Int
                        }
                        """
                    ]
                ),
                dependencies: []
            ),
        ]
    )

    let outcome = try await ValidationCoordinator.coordinate(
        manifest: manifest,
        stateDirectoryPath: root.appendingPathComponent("state").path,
        outputDirectoryPath: root.appendingPathComponent("out").path,
        runner: InProcessValidationCommandRunner(),
        verboseLoggingEnabled: false
    )
    return ExportedImportOutcome(
        exitCode: outcome.result.exitCode,
        stderr: outcome.result.stderr
    )
}
