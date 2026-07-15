import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@testable import InnoDIBuildSupport

@Suite("Target-scoped workspace analysis")
struct WorkspaceTargetScopeTests {
    @Test("Manifest snapshots load only declared sources with target identities")
    func manifestSnapshotUsesExactTargetQualifiedSources() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }

        let unrelatedURL = fixture.rootURL.appendingPathComponent(
            "Unrelated.swift"
        )
        try Data("struct Unrelated {}\n".utf8).write(to: unrelatedURL)

        let manifest = try manifestWithSharedLogicalPath(fixture: fixture)
        let snapshot = try loadWorkspaceSourceSnapshot(manifest: manifest)
        let sharedLogicalPath = "Sources/Shared.swift"
        let appIdentity = "\(fixture.appID.rawValue)::\(sharedLogicalPath)"
        let featureIdentity =
            "\(fixture.featureID.rawValue)::\(sharedLogicalPath)"

        #expect(snapshot.rootPath == fixture.rootPath)
        #expect(snapshot.primaryTargetID == fixture.appID)
        #expect(snapshot.files.count == 4)
        #expect(!snapshot.files.contains {
            $0.filePath == unrelatedURL.path
        })
        #expect(snapshot.sourceFile(relativePath: sharedLogicalPath) == nil)
        #expect(
            snapshot.sourceFile(sourceIdentity: appIdentity)?.targetID
                == fixture.appID
        )
        #expect(
            snapshot.sourceFile(sourceIdentity: appIdentity)?.origin
                == .declared
        )
        #expect(
            snapshot.sourceFile(sourceIdentity: featureIdentity)?.targetID
                == fixture.featureID
        )
        #expect(
            snapshot.sourceFile(sourceIdentity: featureIdentity)?.origin
                == .generated
        )
    }

    @Test("Manifest module topology is authoritative and target-stable")
    func manifestModuleGraphUsesResolvedTargetEdges() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = try makeValidManifest(fixture: fixture).validated()

        let graph = try ModuleGraphProvider.snapshot(manifest: manifest)
        let app = try #require(
            graph.moduleRecord(moduleID: fixture.appID.rawValue)
        )
        let feature = try #require(
            graph.moduleRecord(moduleID: fixture.featureID.rawValue)
        )
        let support = try #require(
            graph.moduleRecord(moduleID: fixture.supportID.rawValue)
        )

        #expect(Set(graph.modules.map(\.moduleID)) == [
            fixture.appID.rawValue,
            fixture.featureID.rawValue,
            fixture.supportID.rawValue,
        ])
        #expect(app.packageIdentity == "root-package")
        #expect(app.name == "App")
        #expect(app.dependencyRefs.isEmpty)
        #expect(app.swiftPMPackageDependencies.isEmpty)
        #expect(app.directDependencyModuleIDs == [
            fixture.featureID.rawValue,
            fixture.supportID.rawValue,
        ])
        #expect(graph.declaresDependencyEdge(from: app, to: feature) == true)
        #expect(graph.declaresDependencyEdge(from: app, to: support) == true)
        #expect(
            graph.declaresDependencyEdge(from: feature, to: app) == false
        )
        #expect(feature.directDependencyModuleIDs == [])
        #expect(
            graph.moduleRecord(
                forFilePath: fixture.featureSourceURL.path
            )?.moduleID == fixture.featureID.rawValue
        )
    }

    @Test("Root snapshots retain legacy relative-path identities")
    func rootSnapshotRetainsRelativePathIdentity() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }

        let snapshot = try loadWorkspaceSourceSnapshot(
            rootPath: fixture.rootPath
        )
        let app = try #require(snapshot.files.first {
            $0.relativePath == "Sources/App/App.swift"
        })

        #expect(snapshot.primaryTargetID == nil)
        #expect(app.targetID == nil)
        #expect(app.origin == nil)
        #expect(app.sourceIdentity == app.relativePath)
        #expect(
            snapshot.sourceFile(relativePath: app.relativePath)?.filePath
                == app.filePath
        )
    }
}

private func manifestWithSharedLogicalPath(
    fixture: ManifestFixture
) throws -> WorkspaceAnalysisManifest {
    let manifest = makeValidManifest(fixture: fixture)
    let app = try #require(manifest.primaryTarget)
    let feature = try #require(manifest.target(id: fixture.featureID))
    let support = try #require(manifest.target(id: fixture.supportID))
    let appSource = try #require(app.sources.first {
        $0.filePath == fixture.appSourceURL.path
    })
    let appZSource = try #require(app.sources.first {
        $0.filePath == fixture.zSourceURL.path
    })
    let featureSource = try #require(feature.sources.first)

    return replacingManifest(
        manifest,
        targets: [
            replacingTarget(
                app,
                sources: [
                    WorkspaceAnalysisSource(
                        filePath: appSource.filePath,
                        logicalPath: "Sources/Shared.swift",
                        origin: .declared
                    ),
                    appZSource,
                ]
            ),
            replacingTarget(
                feature,
                sources: [
                    WorkspaceAnalysisSource(
                        filePath: featureSource.filePath,
                        logicalPath: "Sources/Shared.swift",
                        origin: .generated
                    )
                ]
            ),
            support,
        ]
    )
}
