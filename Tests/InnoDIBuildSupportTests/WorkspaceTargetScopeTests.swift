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
        #expect(snapshot.analysisManifest == (try manifest.validated()))
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
        #expect(snapshot.analysisManifest == nil)
        #expect(app.targetID == nil)
        #expect(app.origin == nil)
        #expect(app.sourceIdentity == app.relativePath)
        #expect(
            snapshot.sourceFile(relativePath: app.relativePath)?.filePath
                == app.filePath
        )
    }

    @Test("Manifest signatures ignore checkout roots but include topology")
    func manifestSignaturesAreCheckoutStableAndScopeAware() throws {
        let first = try ManifestFixture()
        let second = try ManifestFixture()
        defer {
            first.remove()
            second.remove()
        }
        let firstManifest = makeValidManifest(fixture: first)
        let secondManifest = makeValidManifest(fixture: second)
        let firstStateURL = first.rootURL.appendingPathComponent(
            "signature-state",
            isDirectory: true
        )
        let secondStateURL = second.rootURL.appendingPathComponent(
            "signature-state",
            isDirectory: true
        )

        let firstSignature = try collectValidationSignature(
            manifest: firstManifest,
            stateDirectoryPath: firstStateURL.path
        )
        let secondSignature = try collectValidationSignature(
            manifest: secondManifest,
            stateDirectoryPath: secondStateURL.path
        )
        #expect(firstSignature == secondSignature)

        try Data("struct OutsideScope {}\n".utf8).write(
            to: first.rootURL.appendingPathComponent("OutsideScope.swift")
        )
        let afterOutsideChange = try collectValidationSignature(
            manifest: firstManifest,
            stateDirectoryPath: firstStateURL.path
        )
        #expect(afterOutsideChange == firstSignature)

        let app = try #require(firstManifest.primaryTarget)
        let feature = try #require(
            firstManifest.target(id: first.featureID)
        )
        let support = try #require(
            firstManifest.target(id: first.supportID)
        )
        let renamedDependencies = app.dependencies.map { dependency in
            guard dependency.name == "FeatureKit" else {
                return dependency
            }
            return WorkspaceAnalysisDependency(
                kind: dependency.kind,
                name: "RenamedFeatureKit",
                packageIdentity: dependency.packageIdentity,
                targetIDs: dependency.targetIDs
            )
        }
        let topologyChanged = replacingManifest(
            firstManifest,
            targets: [
                replacingTarget(
                    app,
                    dependencies: renamedDependencies
                ),
                feature,
                support,
            ]
        )
        let topologySignature = try collectValidationSignature(
            manifest: topologyChanged,
            stateDirectoryPath: firstStateURL.path
        )
        #expect(topologySignature != firstSignature)
    }

    @Test("Manifest digest caches keep target-qualified source keys")
    func manifestDigestCacheUsesTargetQualifiedKeys() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = try manifestWithSharedLogicalPath(fixture: fixture)
            .validated()
        let stateURL = fixture.rootURL.appendingPathComponent(
            "digest-state",
            isDirectory: true
        )

        let first = try collectValidationSignatureWithMetrics(
            manifest: manifest,
            stateDirectoryPath: stateURL.path
        )
        let manifestURL = stateURL.appendingPathComponent(
            "ast-digest-cache.json"
        )
        let firstPersisted = try JSONDecoder().decode(
            ValidationDigestManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        #expect(first.metrics.scannedFileCount == 4)
        #expect(first.fileChanges.newFiles == manifest.sourceIdentities)
        #expect(firstPersisted.files.keys.sorted() == manifest.sourceIdentities)
        #expect(firstPersisted.version == 4)

        let stale = ValidationDigestManifest(
            version: 3,
            files: firstPersisted.files
        )
        try JSONEncoder().encode(stale).write(to: manifestURL, options: .atomic)
        let rebuilt = try collectValidationSignatureWithMetrics(
            manifest: manifest,
            stateDirectoryPath: stateURL.path
        )
        let rebuiltPersisted = try JSONDecoder().decode(
            ValidationDigestManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        #expect(rebuilt.reasonCodes.contains(.cacheMissManifestVersion))
        #expect(rebuilt.metrics.astReparseCount == 4)
        #expect(rebuiltPersisted.version == ValidationDigestManifest.currentVersion)
    }

    @Test("Checkout moves cannot produce false metadata cache hits")
    func physicalPathChangesInvalidateMetadataFingerprint() throws {
        let first = try ManifestFixture()
        let second = try ManifestFixture()
        defer {
            first.remove()
            second.remove()
        }
        try Data("struct Bpp {}\n".utf8).write(to: second.appSourceURL)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        for url in manifestFixtureSourceURLs(first)
            + manifestFixtureSourceURLs(second) {
            try FileManager.default.setAttributes(
                [.modificationDate: fixedDate],
                ofItemAtPath: url.path
            )
        }
        let stateURL = first.rootURL.appendingPathComponent(
            "shared-moved-state",
            isDirectory: true
        )

        let firstResult = try collectValidationSignatureWithMetrics(
            manifest: makeValidManifest(fixture: first),
            stateDirectoryPath: stateURL.path
        )
        let movedResult = try collectValidationSignatureWithMetrics(
            manifest: makeValidManifest(fixture: second),
            stateDirectoryPath: stateURL.path
        )

        #expect(movedResult.signature != firstResult.signature)
        #expect(movedResult.metrics.metadataCacheHitCount == 0)
        #expect(movedResult.metrics.contentHashReuseCount == 3)
        #expect(movedResult.metrics.astReparseCount == 1)
    }

    @Test("Target state paths are isolated and cache pruning is narrow")
    func targetStatePathsAndPruningStayScoped() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "innodi-target-state-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let featureID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "Feature"
        )
        let appState = targetScopedValidationStateDirectory(
            for: appID,
            under: rootURL
        )
        let repeatedAppState = targetScopedValidationStateDirectory(
            for: appID,
            under: rootURL
        )
        let featureState = targetScopedValidationStateDirectory(
            for: featureID,
            under: rootURL
        )

        #expect(appState == repeatedAppState)
        #expect(appState != featureState)
        #expect(appState.deletingLastPathComponent().lastPathComponent == "targets")
        #expect(appState.lastPathComponent.count == 32)

        let currentName = "shared-run-v6-" + String(repeating: "a", count: 32)
        let staleVersionName = "shared-run-v5-" + String(
            repeating: "b",
            count: 32
        )
        let legacyName = String(repeating: "c", count: 32)
        let preservedNames = ["targets", "unrelated-directory"]
        for name in [currentName, staleVersionName, legacyName]
            + preservedNames {
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }

        try pruneSharedRunDirectories(
            keepingDirectoryName: currentName,
            in: rootURL
        )

        #expect(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(currentName).path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(staleVersionName).path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(legacyName).path
        ))
        for name in preservedNames {
            #expect(FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(name).path
            ))
        }
    }

    @Test("Coordinator validates only the authoritative target snapshot")
    func coordinatorUsesManifestSnapshotEndToEnd() async throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = try makeValidManifest(fixture: fixture).validated()
        let outsideURL = fixture.rootURL.appendingPathComponent(
            "OutsideManifest.swift"
        )
        try Data(
            "@DIContainer struct OutsideContainer {}\n".utf8
        ).write(to: outsideURL)
        let stateURL = fixture.rootURL.appendingPathComponent(
            "coordinator-state",
            isDirectory: true
        )
        let outputURL = fixture.rootURL.appendingPathComponent(
            "coordinator-output",
            isDirectory: true
        )
        let runner = ManifestSnapshotRecordingRunner()

        let outcome = try await ValidationCoordinator.coordinate(
            manifest: manifest,
            stateDirectoryPath: stateURL.path,
            outputDirectoryPath: outputURL.path,
            runner: runner
        )

        #expect(outcome.result.exitCode == 0)
        #expect(runner.invocationCount == 1)
        #expect(runner.primaryTargetID == fixture.appID)
        #expect(runner.sourceIdentities == manifest.sourceIdentities)
        #expect(!runner.sourceFilePaths.contains(outsideURL.path))
        #expect(
            outcome.metricsArtifact.signatureMetrics.scannedFileCount
                == manifest.sourceIdentities.count
        )
    }

    @Test("Manifest path input is target-scoped and never falls back")
    func manifestPathCoordinatorFailsClosed() async throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = makeValidManifest(fixture: fixture)
        let manifestURL = fixture.rootURL.appendingPathComponent(
            "workspace-analysis.json"
        )
        try encodeWorkspaceAnalysisManifest(manifest).write(to: manifestURL)
        let sharedStateURL = fixture.rootURL.appendingPathComponent(
            "shared-state",
            isDirectory: true
        )
        let outputURL = fixture.rootURL.appendingPathComponent(
            "path-output",
            isDirectory: true
        )

        let outcome = try await ValidationCoordinator.coordinate(
            analysisManifestPath: manifestURL.path,
            sharedStateDirectoryPath: sharedStateURL.path,
            outputDirectoryPath: outputURL.path
        )
        let expectedStateURL = targetScopedValidationStateDirectory(
            for: fixture.appID,
            under: sharedStateURL
        )

        #expect(outcome.result.exitCode == 0)
        #expect(FileManager.default.fileExists(
            atPath: expectedStateURL.appendingPathComponent(
                "ast-digest-cache.json"
            ).path
        ))

        let malformedURL = fixture.rootURL.appendingPathComponent(
            "malformed-workspace-analysis.json"
        )
        try Data("{not-json".utf8).write(to: malformedURL)
        do {
            _ = try await ValidationCoordinator.coordinate(
                analysisManifestPath: malformedURL.path,
                sharedStateDirectoryPath: sharedStateURL.path,
                outputDirectoryPath: fixture.rootURL
                    .appendingPathComponent("malformed-output")
                    .path
            )
            Issue.record("Expected malformed manifest input to fail")
        } catch WorkspaceAnalysisManifestError.decodingFailed(_) {
            // Expected. Root scanning is intentionally not attempted.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private final class ManifestSnapshotRecordingRunner:
    ValidationCommandRunning,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var invocationCountStorage = 0
    private var primaryTargetIDStorage: WorkspaceTargetID?
    private var sourceIdentitiesStorage: [String] = []
    private var sourceFilePathsStorage: [String] = []

    var invocationCount: Int {
        lock.withLock { invocationCountStorage }
    }

    var primaryTargetID: WorkspaceTargetID? {
        lock.withLock { primaryTargetIDStorage }
    }

    var sourceIdentities: [String] {
        lock.withLock { sourceIdentitiesStorage }
    }

    var sourceFilePaths: [String] {
        lock.withLock { sourceFilePathsStorage }
    }

    func runValidationTool(
        toolPath: String?,
        rootPath: String,
        snapshot: WorkspaceSourceSnapshot
    ) throws -> ValidationCommandResult {
        lock.withLock {
            invocationCountStorage += 1
            primaryTargetIDStorage = snapshot.primaryTargetID
            sourceIdentitiesStorage = snapshot.files
                .map(\.sourceIdentity)
                .sorted()
            sourceFilePathsStorage = snapshot.files
                .map(\.filePath)
                .sorted()
        }
        return ValidationCommandResult(
            exitCode: 0,
            stdout: "DAG validation passed.\n",
            stderr: ""
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

private func manifestFixtureSourceURLs(
    _ fixture: ManifestFixture
) -> [URL] {
    [
        fixture.appSourceURL,
        fixture.zSourceURL,
        fixture.supportSourceURL,
        fixture.featureSourceURL,
    ]
}
