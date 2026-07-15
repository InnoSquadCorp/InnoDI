import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@Suite("Workspace analysis manifest")
struct WorkspaceAnalysisManifestTests {
    @Test("Encoding is canonical, deterministic, and schema-stable")
    func contractEncodingIsCanonicalAndDeterministic() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }

        let canonical = makeValidManifest(fixture: fixture)
        let reversed = makeValidManifest(
            fixture: fixture,
            reverseInputOrder: true
        )
        let canonicalData = try encodeWorkspaceAnalysisManifest(canonical)
        let reversedData = try encodeWorkspaceAnalysisManifest(reversed)

        #expect(canonicalData == reversedData)

        let json = try #require(
            JSONSerialization.jsonObject(with: canonicalData)
                as? [String: Any]
        )
        #expect(Set(json.keys) == [
            "analysisScope",
            "buildSystem",
            "primaryTargetID",
            "rootPackageDirectory",
            "rootPackageIdentity",
            "schemaVersion",
            "targets",
        ])
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["buildSystem"] as? String == "swiftpm")
        #expect(
            json["analysisScope"] as? String
                == "primaryTargetWithVisibleDependencies"
        )
        #expect(json["primaryTargetID"] as? String == fixture.appID.rawValue)

        let targets = try #require(json["targets"] as? [[String: Any]])
        let app = try #require(targets.first {
            $0["id"] as? String == fixture.appID.rawValue
        })
        #expect(Set(app.keys) == [
            "dependencies",
            "id",
            "kind",
            "moduleName",
            "packageDirectory",
            "packageDisplayName",
            "packageIdentity",
            "role",
            "sources",
            "targetName",
        ])
        #expect(app["packageDisplayName"] as? String == "Root Package")
        #expect(app["packageDirectory"] as? String == fixture.rootPath)

        let sources = try #require(app["sources"] as? [[String: Any]])
        #expect(sources.map { $0["logicalPath"] as? String } == [
            "Sources/App/App.swift",
            "Sources/App/Z.swift",
        ])
        #expect(Set(try #require(sources.first).keys) == [
            "filePath",
            "logicalPath",
            "origin",
        ])

        let dependencies = try #require(
            app["dependencies"] as? [[String: Any]]
        )
        let feature = try #require(dependencies.first {
            $0["name"] as? String == "FeatureKit"
        })
        #expect(Set(feature.keys) == [
            "kind",
            "name",
            "packageIdentity",
            "targetIDs",
        ])
        #expect(feature["targetIDs"] as? [String] == [
            fixture.featureID.rawValue
        ])

        let manifestURL = fixture.rootURL.appendingPathComponent(
            "workspace-analysis.json"
        )
        try canonicalData.write(to: manifestURL)
        let loaded = try loadWorkspaceAnalysisManifest(at: manifestURL)
        let validated = try canonical.validated()
        #expect(loaded == validated)
    }

    @Test("Semantic identities ignore checkout roots")
    func semanticIdentitiesIgnoreCheckoutRoot() throws {
        let first = try ManifestFixture()
        let second = try ManifestFixture()
        defer {
            first.remove()
            second.remove()
        }

        let firstManifest = try makeValidManifest(fixture: first).validated()
        let secondManifest = try makeValidManifest(fixture: second).validated()

        #expect(firstManifest.primaryTargetID == secondManifest.primaryTargetID)
        #expect(
            firstManifest.targets.map(\.id)
                == secondManifest.targets.map(\.id)
        )
        #expect(firstManifest.sourceIdentities == secondManifest.sourceIdentities)
        #expect(
            try encodeWorkspaceAnalysisManifest(firstManifest)
                != encodeWorkspaceAnalysisManifest(secondManifest)
        )
    }

    @Test("Unsupported manifest envelopes fail closed")
    func rejectsUnsupportedContractEnvelope() {
        let fixture = try? ManifestFixture()
        guard let fixture else {
            Issue.record("Could not create manifest fixture")
            return
        }
        defer { fixture.remove() }
        let manifest = makeValidManifest(fixture: fixture)

        expectManifestError(
            .unsupportedSchemaVersion(99),
            from: replacingManifest(manifest, schemaVersion: 99)
        )
        expectManifestError(
            .unsupportedBuildSystem("xcode"),
            from: replacingManifest(manifest, buildSystem: "xcode")
        )
        expectManifestError(
            .unsupportedAnalysisScope("workspace"),
            from: replacingManifest(manifest, analysisScope: "workspace")
        )
    }

    @Test("Primary and target identities fail closed")
    func rejectsInvalidTargetAndPrimaryIdentity() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = makeValidManifest(fixture: fixture)
        let app = try #require(manifest.primaryTarget)
        let feature = try #require(manifest.target(id: fixture.featureID))
        let support = try #require(manifest.target(id: fixture.supportID))

        expectManifestError(
            .missingPrimaryTarget(fixture.appID),
            from: replacingManifest(manifest, targets: [])
        )
        expectManifestError(
            .duplicateTargetID(fixture.appID),
            from: replacingManifest(manifest, targets: [app, app])
        )
        expectManifestError(
            .invalidPrimaryTarget(fixture.appID),
            from: replacingManifest(
                manifest,
                targets: [
                    replacingTarget(app, role: .dependency),
                    feature,
                    support,
                ]
            )
        )
        expectManifestError(
            .primaryPackageMismatch(
                expected: "other-root",
                actual: "root-package"
            ),
            from: replacingManifest(
                manifest,
                rootPackageIdentity: "other-root"
            )
        )
        expectManifestError(
            .primaryPackageDirectoryMismatch(
                expected: fixture.featurePackagePath,
                actual: fixture.rootPath
            ),
            from: replacingManifest(
                manifest,
                rootPackageDirectory: fixture.featurePackagePath
            )
        )

        let invalidID = WorkspaceTargetID(rawValue: "swiftpm:wrong:App")
        expectManifestError(
            .nonCanonicalTargetID(
                actual: invalidID,
                expected: fixture.appID
            ),
            from: replacingManifest(
                manifest,
                primaryTargetID: invalidID,
                targets: [
                    replacingTarget(app, id: invalidID),
                    feature,
                    support,
                ]
            )
        )
        expectManifestError(
            .invalidPackageDisplayName(""),
            from: replacingManifest(
                manifest,
                targets: [
                    replacingTarget(app, packageDisplayName: ""),
                    feature,
                    support,
                ]
            )
        )
        expectManifestError(
            .invalidTargetName(" "),
            from: replacingManifest(
                manifest,
                targets: [
                    replacingTarget(app, targetName: " "),
                    feature,
                    support,
                ]
            )
        )
        expectManifestError(
            .unsupportedDependencyTargetKind(fixture.featureID, .macro),
            from: replacingManifest(
                manifest,
                targets: [
                    app,
                    replacingTarget(feature, kind: .macro),
                    support,
                ]
            )
        )
        expectManifestError(
            .inconsistentPackageMetadata("root-package"),
            from: replacingManifest(
                manifest,
                targets: [
                    app,
                    feature,
                    replacingTarget(
                        support,
                        packageDisplayName: "Different Root"
                    ),
                ]
            )
        )
    }

    @Test("Invalid source contracts fail closed")
    func rejectsInvalidSourceContracts() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = makeValidManifest(fixture: fixture)
        let app = try #require(manifest.primaryTarget)
        let feature = try #require(manifest.target(id: fixture.featureID))
        let support = try #require(manifest.target(id: fixture.supportID))
        let appSource = try #require(app.sources.first {
            $0.logicalPath.hasSuffix("/App.swift")
        })
        let zSource = try #require(app.sources.first {
            $0.logicalPath.hasSuffix("/Z.swift")
        })

        expectSourceError(
            .nonAbsolutePath("relative/App.swift"),
            source: WorkspaceAnalysisSource(
                filePath: "relative/App.swift",
                logicalPath: appSource.logicalPath,
                origin: .declared
            ),
            app: app,
            feature: feature,
            support: support,
            manifest: manifest
        )
        expectSourceError(
            .invalidLogicalPath("../App.swift"),
            source: WorkspaceAnalysisSource(
                filePath: appSource.filePath,
                logicalPath: "../App.swift",
                origin: .declared
            ),
            app: app,
            feature: feature,
            support: support,
            manifest: manifest
        )
        expectSourceError(
            .nonSwiftSource(appSource.filePath),
            source: WorkspaceAnalysisSource(
                filePath: appSource.filePath,
                logicalPath: "Sources/App/App.txt",
                origin: .declared
            ),
            app: app,
            feature: feature,
            support: support,
            manifest: manifest
        )

        let repeatedIdentity = WorkspaceAnalysisSource(
            filePath: zSource.filePath,
            logicalPath: appSource.logicalPath,
            origin: .declared
        )
        expectManifestError(
            .duplicateSourceIdentity(
                appSource.identity(in: fixture.appID)
            ),
            from: replacingManifest(
                manifest,
                targets: [
                    replacingTarget(
                        app,
                        sources: [appSource, repeatedIdentity]
                    ),
                    feature,
                    support,
                ]
            )
        )

        let repeatedPhysicalSource = WorkspaceAnalysisSource(
            filePath: fixture.appSourceURL.deletingLastPathComponent().path
                + "/./App.swift",
            logicalPath: "Sources/App/Alias.swift",
            origin: .declared
        )
        expectManifestError(
            .duplicateSourcePath(fixture.appID, appSource.filePath),
            from: replacingManifest(
                manifest,
                targets: [
                    replacingTarget(
                        app,
                        sources: [appSource, repeatedPhysicalSource]
                    ),
                    feature,
                    support,
                ]
            )
        )

        let crossOwnedSource = WorkspaceAnalysisSource(
            filePath: appSource.filePath,
            logicalPath: "Sources/Feature/Feature.swift",
            origin: .declared
        )
        expectManifestError(
            .duplicateSourceOwnership(
                filePath: appSource.filePath,
                firstTarget: fixture.featureID,
                secondTarget: fixture.appID
            ),
            from: replacingManifest(
                manifest,
                targets: [
                    app,
                    replacingTarget(feature, sources: [crossOwnedSource]),
                    support,
                ]
            )
        )

        let missingPath = fixture.rootURL
            .appendingPathComponent("Missing.swift")
            .path
        expectSourceError(
            .unavailableSource(missingPath),
            source: WorkspaceAnalysisSource(
                filePath: missingPath,
                logicalPath: "Sources/App/Missing.swift",
                origin: .declared
            ),
            app: app,
            feature: feature,
            support: support,
            manifest: manifest,
            validateSourceAvailability: true
        )
    }

    @Test("Invalid dependency closures fail closed")
    func rejectsInvalidDependencyClosure() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = makeValidManifest(fixture: fixture)
        let app = try #require(manifest.primaryTarget)
        let feature = try #require(manifest.target(id: fixture.featureID))
        let support = try #require(manifest.target(id: fixture.supportID))

        func manifestWithDependencies(
            _ dependencies: [WorkspaceAnalysisDependency]
        ) -> WorkspaceAnalysisManifest {
            replacingManifest(
                manifest,
                targets: [
                    replacingTarget(app, dependencies: dependencies),
                    feature,
                    support,
                ]
            )
        }

        expectManifestError(
            .emptyDependency(fixture.appID, "Empty"),
            from: manifestWithDependencies([
                WorkspaceAnalysisDependency(
                    kind: .product,
                    name: "Empty",
                    targetIDs: []
                )
            ])
        )
        expectManifestError(
            .invalidDependencyName(fixture.appID, " "),
            from: manifestWithDependencies([
                WorkspaceAnalysisDependency(
                    kind: .product,
                    name: " ",
                    targetIDs: [fixture.featureID]
                )
            ])
        )
        expectManifestError(
            .invalidDependencyPackageIdentity(fixture.appID, "bad:identity"),
            from: manifestWithDependencies([
                WorkspaceAnalysisDependency(
                    kind: .product,
                    name: "FeatureKit",
                    packageIdentity: "bad:identity",
                    targetIDs: [fixture.featureID]
                )
            ])
        )
        expectManifestError(
            .invalidTargetDependencyCardinality(
                fixture.appID,
                "TooMany",
                2
            ),
            from: manifestWithDependencies([
                WorkspaceAnalysisDependency(
                    kind: .target,
                    name: "TooMany",
                    targetIDs: [fixture.featureID, fixture.supportID]
                )
            ])
        )
        expectManifestError(
            .selfDependency(fixture.appID),
            from: manifestWithDependencies([
                WorkspaceAnalysisDependency(
                    kind: .target,
                    name: "App",
                    targetIDs: [fixture.appID]
                )
            ])
        )

        let missingID = WorkspaceTargetID.swiftPM(
            packageIdentity: "missing",
            moduleName: "Missing"
        )
        expectManifestError(
            .danglingDependency(fixture.appID, missingID),
            from: manifestWithDependencies([
                WorkspaceAnalysisDependency(
                    kind: .product,
                    name: "Missing",
                    targetIDs: [missingID]
                )
            ])
        )
        expectManifestError(
            .duplicateDependencyTarget(fixture.appID, fixture.featureID),
            from: manifestWithDependencies([
                WorkspaceAnalysisDependency(
                    kind: .product,
                    name: "FeatureKit",
                    targetIDs: [fixture.featureID]
                ),
                WorkspaceAnalysisDependency(
                    kind: .target,
                    name: "FeatureAgain",
                    targetIDs: [fixture.featureID]
                ),
            ])
        )

        let unusedID = WorkspaceTargetID.swiftPM(
            packageIdentity: "unused-package",
            moduleName: "Unused"
        )
        let unused = WorkspaceAnalysisTarget(
            id: unusedID,
            packageIdentity: "unused-package",
            packageDisplayName: "Unused Package",
            packageDirectory: fixture.featurePackagePath,
            targetName: "Unused",
            moduleName: "Unused",
            kind: .generic,
            role: .dependency,
            sources: [],
            dependencies: []
        )
        expectManifestError(
            .unreachableTarget(unusedID),
            from: replacingManifest(
                manifest,
                targets: manifest.targets + [unused]
            )
        )
    }

    @Test("Target dependency cycles fail closed deterministically")
    func rejectsTargetDependencyCyclesDeterministically() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = makeValidManifest(fixture: fixture)
        let app = try #require(manifest.primaryTarget)
        let feature = try #require(manifest.target(id: fixture.featureID))
        let support = try #require(manifest.target(id: fixture.supportID))
        let appToFeature = try #require(app.dependencies.first {
            $0.targetIDs.contains(fixture.featureID)
        })
        let featureToApp = WorkspaceAnalysisDependency(
            kind: .target,
            name: "App",
            targetIDs: [fixture.appID]
        )
        let cyclicFeature = replacingTarget(
            feature,
            dependencies: [featureToApp]
        )
        let expectedPath = [
            fixture.appID,
            fixture.featureID,
            fixture.appID,
        ]
        let expectedError = WorkspaceAnalysisManifestError
            .targetDependencyCycle(expectedPath)

        expectManifestError(
            expectedError,
            from: replacingManifest(
                manifest,
                targets: [app, support, cyclicFeature]
            )
        )
        expectManifestError(
            expectedError,
            from: replacingManifest(
                manifest,
                targets: [
                    cyclicFeature,
                    support,
                    replacingTarget(
                        app,
                        dependencies: Array(app.dependencies.reversed())
                    ),
                ]
            )
        )
        expectManifestError(
            expectedError,
            from: replacingManifest(
                manifest,
                targets: [
                    replacingTarget(
                        app,
                        dependencies: [appToFeature]
                    ),
                    support,
                    cyclicFeature,
                ]
            )
        )
        #expect(
            expectedError.errorDescription
                == "Workspace target dependency cycle detected: "
                + "'\(fixture.appID.rawValue)' -> "
                + "'\(fixture.featureID.rawValue)' -> "
                + "'\(fixture.appID.rawValue)'."
        )
    }

    @Test("Acyclic target dependency topology remains valid")
    func acceptsAcyclicTargetDependencyTopology() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifest = makeValidManifest(
            fixture: fixture,
            reverseInputOrder: true
        )

        let validated = try manifest.validated()

        #expect(validated.primaryTargetID == fixture.appID)
        #expect(
            validated.targets.map(\.id)
                == manifest.targets.map(\.id).sorted()
        )
    }

    @Test("Malformed JSON fails closed")
    func malformedJSONFailsClosed() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let manifestURL = fixture.rootURL.appendingPathComponent(
            "malformed.json"
        )
        try Data("{not-json".utf8).write(to: manifestURL)

        do {
            _ = try loadWorkspaceAnalysisManifest(at: manifestURL)
            Issue.record("Expected malformed JSON to fail")
        } catch WorkspaceAnalysisManifestError.decodingFailed(_) {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

struct ManifestFixture {
    let rootURL: URL
    let featurePackageURL: URL
    let appSourceURL: URL
    let zSourceURL: URL
    let supportSourceURL: URL
    let featureSourceURL: URL

    init() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "innodi-workspace-manifest-\(UUID().uuidString)",
                isDirectory: true
            )
        let appDirectory = rootURL.appendingPathComponent(
            "Sources/App",
            isDirectory: true
        )
        let supportDirectory = rootURL.appendingPathComponent(
            "Sources/LocalSupport",
            isDirectory: true
        )
        let featurePackageURL = rootURL.appendingPathComponent(
            "Dependencies/FeaturePackage",
            isDirectory: true
        )
        let featureDirectory = featurePackageURL.appendingPathComponent(
            "Sources/Feature",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: featureDirectory,
            withIntermediateDirectories: true
        )

        let appSourceURL = appDirectory.appendingPathComponent("App.swift")
        let zSourceURL = appDirectory.appendingPathComponent("Z.swift")
        let supportSourceURL = supportDirectory.appendingPathComponent(
            "Support.swift"
        )
        let featureSourceURL = featureDirectory.appendingPathComponent(
            "Feature.swift"
        )
        try Data("struct App {}\n".utf8).write(to: appSourceURL)
        try Data("struct Z {}\n".utf8).write(to: zSourceURL)
        try Data("struct Support {}\n".utf8).write(to: supportSourceURL)
        try Data("struct Feature {}\n".utf8).write(to: featureSourceURL)

        self.rootURL = rootURL
        self.featurePackageURL = featurePackageURL
        self.appSourceURL = appSourceURL
        self.zSourceURL = zSourceURL
        self.supportSourceURL = supportSourceURL
        self.featureSourceURL = featureSourceURL
    }

    var rootPath: String { rootURL.path }
    var featurePackagePath: String { featurePackageURL.path }

    var appID: WorkspaceTargetID {
        .swiftPM(packageIdentity: "root-package", moduleName: "App")
    }

    var supportID: WorkspaceTargetID {
        .swiftPM(
            packageIdentity: "root-package",
            moduleName: "LocalSupport"
        )
    }

    var featureID: WorkspaceTargetID {
        .swiftPM(
            packageIdentity: "feature-package",
            moduleName: "Feature"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

func makeValidManifest(
    fixture: ManifestFixture,
    reverseInputOrder: Bool = false
) -> WorkspaceAnalysisManifest {
    let appSources = [
        WorkspaceAnalysisSource(
            filePath: fixture.appSourceURL.path,
            logicalPath: "Sources/App/App.swift",
            origin: .declared
        ),
        WorkspaceAnalysisSource(
            filePath: fixture.zSourceURL.path,
            logicalPath: "Sources/App/Z.swift",
            origin: .declared
        ),
    ]
    let appDependencies = [
        WorkspaceAnalysisDependency(
            kind: .product,
            name: "FeatureKit",
            packageIdentity: "feature-package",
            targetIDs: [fixture.featureID]
        ),
        WorkspaceAnalysisDependency(
            kind: .target,
            name: "LocalSupport",
            targetIDs: [fixture.supportID]
        ),
    ]
    let app = WorkspaceAnalysisTarget(
        id: fixture.appID,
        packageIdentity: "root-package",
        packageDisplayName: "Root Package",
        packageDirectory: fixture.rootPath,
        targetName: "App",
        moduleName: "App",
        kind: .executable,
        role: .primary,
        sources: reverseInputOrder
            ? Array(appSources.reversed())
            : appSources,
        dependencies: reverseInputOrder
            ? Array(appDependencies.reversed())
            : appDependencies
    )
    let support = WorkspaceAnalysisTarget(
        id: fixture.supportID,
        packageIdentity: "root-package",
        packageDisplayName: "Root Package",
        packageDirectory: fixture.rootPath,
        targetName: "LocalSupport",
        moduleName: "LocalSupport",
        kind: .generic,
        role: .dependency,
        sources: [
            WorkspaceAnalysisSource(
                filePath: fixture.supportSourceURL.path,
                logicalPath: "Sources/LocalSupport/Support.swift",
                origin: .declared
            )
        ],
        dependencies: []
    )
    let feature = WorkspaceAnalysisTarget(
        id: fixture.featureID,
        packageIdentity: "feature-package",
        packageDisplayName: "Feature Package",
        packageDirectory: fixture.featurePackagePath,
        targetName: "Feature",
        moduleName: "Feature",
        kind: .generic,
        role: .dependency,
        sources: [
            WorkspaceAnalysisSource(
                filePath: fixture.featureSourceURL.path,
                logicalPath: "Sources/Feature/Feature.swift",
                origin: .declared
            )
        ],
        dependencies: []
    )
    let targets = [app, support, feature]

    return WorkspaceAnalysisManifest(
        rootPackageIdentity: "root-package",
        rootPackageDirectory: fixture.rootPath,
        primaryTargetID: fixture.appID,
        targets: reverseInputOrder
            ? Array(targets.reversed())
            : targets
    )
}

func replacingManifest(
    _ manifest: WorkspaceAnalysisManifest,
    schemaVersion: Int? = nil,
    buildSystem: String? = nil,
    analysisScope: String? = nil,
    rootPackageIdentity: String? = nil,
    rootPackageDirectory: String? = nil,
    primaryTargetID: WorkspaceTargetID? = nil,
    targets: [WorkspaceAnalysisTarget]? = nil
) -> WorkspaceAnalysisManifest {
    WorkspaceAnalysisManifest(
        schemaVersion: schemaVersion ?? manifest.schemaVersion,
        buildSystem: buildSystem ?? manifest.buildSystem,
        analysisScope: analysisScope ?? manifest.analysisScope,
        rootPackageIdentity:
            rootPackageIdentity ?? manifest.rootPackageIdentity,
        rootPackageDirectory:
            rootPackageDirectory ?? manifest.rootPackageDirectory,
        primaryTargetID: primaryTargetID ?? manifest.primaryTargetID,
        targets: targets ?? manifest.targets
    )
}

func replacingTarget(
    _ target: WorkspaceAnalysisTarget,
    id: WorkspaceTargetID? = nil,
    packageIdentity: String? = nil,
    packageDisplayName: String? = nil,
    packageDirectory: String? = nil,
    targetName: String? = nil,
    moduleName: String? = nil,
    kind: WorkspaceAnalysisTargetKind? = nil,
    role: WorkspaceAnalysisTargetRole? = nil,
    sources: [WorkspaceAnalysisSource]? = nil,
    dependencies: [WorkspaceAnalysisDependency]? = nil
) -> WorkspaceAnalysisTarget {
    WorkspaceAnalysisTarget(
        id: id ?? target.id,
        packageIdentity: packageIdentity ?? target.packageIdentity,
        packageDisplayName:
            packageDisplayName ?? target.packageDisplayName,
        packageDirectory: packageDirectory ?? target.packageDirectory,
        targetName: targetName ?? target.targetName,
        moduleName: moduleName ?? target.moduleName,
        kind: kind ?? target.kind,
        role: role ?? target.role,
        sources: sources ?? target.sources,
        dependencies: dependencies ?? target.dependencies
    )
}

private func expectSourceError(
    _ expected: WorkspaceAnalysisManifestError,
    source: WorkspaceAnalysisSource,
    app: WorkspaceAnalysisTarget,
    feature: WorkspaceAnalysisTarget,
    support: WorkspaceAnalysisTarget,
    manifest: WorkspaceAnalysisManifest,
    validateSourceAvailability: Bool = false
) {
    expectManifestError(
        expected,
        from: replacingManifest(
            manifest,
            targets: [
                replacingTarget(app, sources: [source]),
                feature,
                support,
            ]
        ),
        validateSourceAvailability: validateSourceAvailability
    )
}

private func expectManifestError(
    _ expected: WorkspaceAnalysisManifestError,
    from manifest: WorkspaceAnalysisManifest,
    validateSourceAvailability: Bool = false
) {
    do {
        _ = try manifest.validated(
            validateSourceAvailability: validateSourceAvailability
        )
        Issue.record("Expected manifest error: \(expected)")
    } catch let error as WorkspaceAnalysisManifestError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
