import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@testable import InnoDIDependencyGraphCore

@Suite("Target-scoped dependency graph semantics")
struct WorkspaceTargetIdentityGraphTests {
    @Test("Same logical path and container name remain distinct per target")
    func targetQualifiedNodeIdentitiesDoNotCollapse() throws {
        let fixture = try TargetGraphFixture(
            primaryLogicalPath: "Sources/Shared.swift",
            primarySource: containerSource(named: "SharedContainer"),
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    logicalPath: "Sources/Shared.swift",
                    source: containerSource(named: "SharedContainer")
                )
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let appID = fixture.primaryTargetID
        let featureID = fixture.targetID(moduleName: "FeatureKit")
        let expectedIDs: Set<String> = [
            containerID(
                targetID: appID,
                containerName: "SharedContainer"
            ),
            containerID(
                targetID: featureID,
                containerName: "SharedContainer"
            ),
        ]

        #expect(analysis.nodes.count == 2)
        #expect(Set(analysis.nodes.map(\.id)) == expectedIDs)
        #expect(Set(analysis.nodes.map(\.semanticPath)) == ["SharedContainer"])
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Schema-v2 IDs survive checkout and source-file moves")
    func schemaV2IdentitiesIgnorePhysicalAndLogicalSourcePaths() throws {
        let primarySource = factorySource(
            imports: ["FeatureKit"],
            factoryType: "FeatureKit.FeatureContainer"
        )
        let original = try TargetGraphFixture(
            primaryLogicalPath: "Sources/App/Original.swift",
            primarySource: primarySource,
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    logicalPath: "Sources/FeatureKit/Original.swift",
                    source: containerSource(named: "FeatureContainer")
                )
            ]
        )
        defer { original.remove() }
        let moved = try TargetGraphFixture(
            primaryLogicalPath: "Sources/App/Moved.swift",
            primarySource: primarySource,
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    logicalPath: "Sources/FeatureKit/Nested/Moved.swift",
                    source: containerSource(named: "FeatureContainer")
                )
            ]
        )
        defer { moved.remove() }

        let originalGraph = try original.collectGraph()
        let movedGraph = try moved.collectGraph()

        #expect(Set(originalGraph.nodes) == Set(movedGraph.nodes))
        #expect(Set(originalGraph.edges) == Set(movedGraph.edges))
        #expect(
            Set(originalGraph.nodes.map(\.id)) == [
                "swiftpm:root-package:App::AppContainer",
                "swiftpm:feature-package:FeatureKit::FeatureContainer",
            ]
        )
    }

    @Test("Schema-v2 edge ordering survives source-order changes")
    func schemaV2EdgesUseSemanticOrdering() throws {
        let aSource = rootedFactorySource(
            rootName: "ARoot",
            childName: "AChild"
        )
        let zSource = rootedFactorySource(
            rootName: "ZRoot",
            childName: "ZChild"
        )
        let original = try TargetGraphFixture(
            primaryLogicalPath: "Sources/App/A-Z.swift",
            primarySource: zSource,
            additionalPrimarySources: [
                "Sources/App/Z-A.swift": aSource
            ],
            dependencies: []
        )
        defer { original.remove() }
        let moved = try TargetGraphFixture(
            primaryLogicalPath: "Sources/App/Z-Z.swift",
            primarySource: zSource,
            additionalPrimarySources: [
                "Sources/App/A-A.swift": aSource
            ],
            dependencies: []
        )
        defer { moved.remove() }

        let originalEdges = try original.collectGraph().edges
        let movedEdges = try moved.collectGraph().edges

        #expect(originalEdges == movedEdges)
        #expect(
            originalEdges.map(\.fromID) == [
                "swiftpm:root-package:App::ARoot",
                "swiftpm:root-package:App::ZRoot",
            ]
        )
    }

    @Test("Duplicate semantic identities in one target fail deterministically")
    func duplicateSemanticIdentityFailsWithoutCollapsingSilently() throws {
        let fixture = try TargetGraphFixture(
            primaryLogicalPath: "Sources/App/First.swift",
            primarySource: containerSource(named: "SharedContainer"),
            additionalPrimarySources: [
                "Sources/App/Second.swift": containerSource(
                    named: "SharedContainer"
                )
            ],
            dependencies: []
        )
        defer { fixture.remove() }

        let result = try fixture.validateGraph()
        let renderAnalysis = try fixture.collectRenderableGraph()

        #expect(result.exitCode == 3)
        #expect(renderAnalysis.preflightFailure?.exitCode == 3)
        #expect(
            renderAnalysis.preflightFailure?.stderr.contains(
                "[graph.duplicate-semantic-identity]"
            ) == true
        )
        #expect(
            result.stderr.contains(
                "[graph.duplicate-semantic-identity] "
                    + "swiftpm:root-package:App::SharedContainer"
            )
        )
        #expect(result.stderr.contains("Sources/App/First.swift"))
        #expect(result.stderr.contains("Sources/App/Second.swift"))
    }

    @Test("Duplicate semantic identities in one file also fail")
    func sameFileDuplicateSemanticIdentityFails() throws {
        let duplicateSource = """
        import InnoDI

        @DIContainer
        struct SharedContainer {}

        @DIContainer
        struct SharedContainer {}
        """
        let fixture = try TargetGraphFixture(
            primaryLogicalPath: "Sources/App/Duplicates.swift",
            primarySource: duplicateSource,
            dependencies: []
        )
        defer { fixture.remove() }

        let result = try fixture.validateGraph()

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("declarations: 2"))
        #expect(
            occurrenceCount(
                "swiftpm:root-package:App::Sources/App/Duplicates.swift",
                in: result.stderr
            ) == 1
        )
    }

    @Test("Current target declarations win over imported namesakes")
    func currentTargetContainerWinsOverImportedNamesake() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            import FeatureKit

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: SharedContainer())
                var shared: SharedContainer
            }

            @DIContainer
            struct SharedContainer {}
            """,
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    source: containerSource(named: "SharedContainer")
                )
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let appID = fixture.primaryTargetID
        let appContainerID = containerID(
            targetID: appID,
            containerName: "AppContainer"
        )
        let localSharedID = containerID(
            targetID: appID,
            containerName: "SharedContainer"
        )
        let importedSharedID = containerID(
            targetID: fixture.targetID(moduleName: "FeatureKit"),
            containerName: "SharedContainer"
        )
        let outgoing = analysis.edges.filter { $0.fromID == appContainerID }

        #expect(outgoing.count == 1)
        #expect(outgoing.first?.toID == localSharedID)
        #expect(!outgoing.contains { $0.toID == importedSharedID })
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Module-qualified factories resolve to the selected dependency target")
    func moduleQualifiedFactoryResolvesDependency() throws {
        let fixture = try TargetGraphFixture(
            primarySource: factorySource(
                imports: ["FeatureKit"],
                factoryType: "FeatureKit.FeatureContainer"
            ),
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(analysis.edges.only)

        #expect(edge.fromID == fixture.primaryContainerID())
        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "FeatureContainer"
            )
        )
        #expect(!edge.isOwnership)
        #expect(!edge.isProvider)
        #expect(!edge.isSoft)
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Imported direct dependencies support unqualified references")
    func importedDependencyResolvesUnqualifiedReference() throws {
        let fixture = try TargetGraphFixture(
            primarySource: factorySource(
                imports: ["FeatureKit"],
                factoryType: "FeatureContainer"
            ),
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(analysis.edges.only)

        #expect(edge.fromID == fixture.primaryContainerID())
        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "FeatureContainer"
            )
        )
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Two imported namesakes fail deterministically without an edge")
    func importedNamesakesAreDeterministicallyAmbiguous() throws {
        let fixture = try TargetGraphFixture(
            primarySource: factorySource(
                imports: ["FeatureKit", "AdminKit"],
                factoryType: "SharedContainer"
            ),
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    source: containerSource(named: "SharedContainer")
                ),
                .init(
                    packageIdentity: "admin-package",
                    moduleName: "AdminKit",
                    source: containerSource(named: "SharedContainer")
                ),
            ]
        )
        defer { fixture.remove() }

        let forwardSnapshot = try fixture.loadSnapshot(reversedInput: false)
        let reversedSnapshot = try fixture.loadSnapshot(reversedInput: true)
        let forward = collectDependencyGraph(
            snapshot: forwardSnapshot,
            validateDAG: true
        )
        let reversed = collectDependencyGraph(
            snapshot: reversedSnapshot,
            validateDAG: true
        )
        let forwardValidation = validateDependencyGraph(snapshot: forwardSnapshot)
        let reversedValidation = validateDependencyGraph(snapshot: reversedSnapshot)

        #expect(forward.edges.isEmpty)
        #expect(reversed.edges.isEmpty)
        #expect(forwardValidation.exitCode == 3)
        #expect(reversedValidation == forwardValidation)
        #expect(
            occurrenceCount(
                "[graph.ambiguous-container-reference]",
                in: forwardValidation.stderr
            ) == 1
        )
        #expect(forwardValidation.stderr.contains("SharedContainer"))
        #expect(
            forwardValidation.stderr.contains(
                fixture.dependencyContainerID(
                    moduleName: "FeatureKit",
                    containerName: "SharedContainer"
                )
            )
        )
        #expect(
            forwardValidation.stderr.contains(
                fixture.dependencyContainerID(
                    moduleName: "AdminKit",
                    containerName: "SharedContainer"
                )
            )
        )
    }

    @Test("Scoped imports expose only their selected declarations")
    func scopedImportsDoNotExposeModuleNamesakes() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            import struct FeatureKit.SharedContainer
            import struct AdminKit.AdminContainer

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: SharedContainer())
                var shared: SharedContainer
            }
            """,
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    source: containerSource(named: "SharedContainer")
                ),
                .init(
                    packageIdentity: "admin-package",
                    moduleName: "AdminKit",
                    source: """
                    import InnoDI

                    @DIContainer struct AdminContainer {}
                    @DIContainer struct SharedContainer {}
                    """
                ),
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(analysis.edges.only)

        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "SharedContainer"
            )
        )
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Conditional imports fail closed instead of merging branches")
    func conditionalImportsAreExplicitlyExcluded() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            #if FEATURE
            import FeatureKit
            #else
            import AdminKit
            #endif

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: SharedContainer())
                var shared: SharedContainer
            }
            """,
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    source: containerSource(named: "SharedContainer")
                ),
                .init(
                    packageIdentity: "admin-package",
                    moduleName: "AdminKit",
                    source: containerSource(named: "SharedContainer")
                ),
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph(validateDAG: true)
        let validation = try fixture.validateGraph()

        #expect(analysis.edges.isEmpty)
        #expect(validation.exitCode == 3)
        #expect(
            occurrenceCount(
                "[graph.excluded-container-reference]",
                in: validation.stderr
            ) == 1
        )
        #expect(validation.stderr.contains("active Swift compilation conditions"))
        #expect(!validation.stderr.contains("Ambiguous container references:"))
    }

    @Test("Conditional imports also fail closed for deferred edges")
    func conditionalImportsRejectDeferredContainerEdges() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            #if FEATURE
            import FeatureKit
            #endif

            struct Consumer {}

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: { (feature: Provider<FeatureKit.FeatureContainer>) in
                    Consumer()
                })
                var consumer: Consumer
            }
            """,
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph(validateDAG: true)
        let validation = try fixture.validateGraph()

        #expect(analysis.edges.isEmpty)
        #expect(validation.exitCode == 3)
        #expect(
            occurrenceCount(
                "[graph.excluded-container-reference]",
                in: validation.stderr
            ) == 1
        )
        #expect(validation.stderr.contains("active Swift compilation conditions"))
    }

    @Test("Conditional imports preserve validateDAG opt-outs")
    func conditionalImportsPreserveValidationOptOuts() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            #if FEATURE
            import FeatureKit
            #endif

            struct Consumer {}

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: FeatureContainer())
                var feature: FeatureContainer

                @Provide(.shared, factory: { (feature: Provider<FeatureKit.FeatureContainer>) in
                    Consumer()
                })
                var consumer: Consumer
            }
            """,
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    source: """
                    import InnoDI

                    @DIContainer(validateDAG: false)
                    struct FeatureContainer {}
                    """
                )
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph(validateDAG: true)
        let validation = try fixture.validateGraph()

        #expect(analysis.edges.isEmpty)
        #expect(validation.exitCode == 0)
        #expect(
            !validation.stderr.contains(
                "[graph.excluded-container-reference]"
            )
        )
        #expect(
            !validation.stderr.contains(
                "[graph.unresolved-container-reference]"
            )
        )
    }

    @Test("A direct dependency that is not imported remains unresolved")
    func unimportedDependencyDoesNotLeakIntoResolution() throws {
        let fixture = try TargetGraphFixture(
            primarySource: factorySource(
                imports: [],
                factoryType: "FeatureContainer"
            ),
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph(validateDAG: true)
        let validation = try fixture.validateGraph()

        #expect(analysis.edges.isEmpty)
        #expect(validation.exitCode == 3)
        #expect(
            occurrenceCount(
                "[graph.unresolved-container-reference]",
                in: validation.stderr
            ) == 1
        )
        #expect(validation.stderr.contains("FeatureContainer"))
        #expect(!validation.stderr.contains("Ambiguous container references:"))
    }

    @Test("Imported transitive targets are not promoted to direct visibility")
    func importedTransitiveDependencyDoesNotLeakIntoResolution() throws {
        let fixture = try TargetGraphFixture(
            primarySource: factorySource(
                imports: ["LeafKit"],
                factoryType: "LeafContainer"
            ),
            primaryDependencyModuleNames: ["MiddleKit"],
            dependencies: [
                .init(
                    packageIdentity: "middle-package",
                    moduleName: "MiddleKit",
                    source: "import InnoDI\n",
                    dependencyModuleNames: ["LeafKit"]
                ),
                .init(
                    packageIdentity: "middle-package",
                    moduleName: "LeafKit",
                    source: containerSource(named: "LeafContainer")
                ),
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph(validateDAG: true)
        let validation = try fixture.validateGraph()

        #expect(analysis.edges.isEmpty)
        #expect(validation.exitCode == 3)
        #expect(
            occurrenceCount(
                "[graph.unresolved-container-reference]",
                in: validation.stderr
            ) == 1
        )
    }

    @Test("Exported imports propagate transitive container visibility")
    func exportedImportsExposeTransitiveDependencies() throws {
        for directive in ["@_exported import", "public import"] {
            let fixture = try TargetGraphFixture(
                primarySource: factorySource(
                    imports: ["MiddleKit"],
                    factoryType: "LeafContainer"
                ),
                primaryDependencyModuleNames: ["MiddleKit"],
                dependencies: [
                    .init(
                        packageIdentity: "middle-package",
                        moduleName: "MiddleKit",
                        source: "\(directive) LeafKit\n",
                        dependencyModuleNames: ["LeafKit"]
                    ),
                    .init(
                        packageIdentity: "middle-package",
                        moduleName: "LeafKit",
                        source: containerSource(named: "LeafContainer")
                    ),
                ]
            )
            defer { fixture.remove() }

            let analysis = try fixture.collectGraph()
            let edge = try #require(analysis.edges.only)

            #expect(
                edge.toID == fixture.dependencyContainerID(
                    moduleName: "LeafKit",
                    containerName: "LeafContainer"
                )
            )
            #expect(try fixture.validateGraph().exitCode == 0)
        }
    }

    @Test("Module-qualified SubContainer declarations create ownership edges")
    func moduleQualifiedSubContainerResolvesDependency() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            import FeatureKit

            @DIContainer(root: true)
            struct AppContainer {
                @SubContainer(scope: .shared)
                var feature: FeatureKit.FeatureContainer
            }
            """,
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(analysis.edges.only)

        #expect(edge.fromID == fixture.primaryContainerID())
        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "FeatureContainer"
            )
        )
        #expect(edge.isOwnership)
        #expect(edge.label == "feature")
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Provider parameters retain cross-target graph identity")
    func providerEdgeResolvesAcrossTargets() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            import FeatureKit

            struct Consumer {}

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: { (feature: Provider<FeatureKit.FeatureContainer>) in
                    Consumer()
                })
                var consumer: Consumer
            }
            """,
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let providerEdges = analysis.edges.filter(\.isProvider)
        let edge = try #require(providerEdges.only)

        #expect(edge.fromID == fixture.primaryContainerID())
        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "FeatureContainer"
            )
        )
        #expect(!edge.isSoft)
        #expect(!edge.isOwnership)
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Aliases from unimported target scopes do not leak")
    func dependencyAliasesAreLimitedToImportedTargets() throws {
        let fixture = try TargetGraphFixture(
            primarySource: factorySource(
                imports: ["FeatureKit"],
                factoryType: "SelectedContainer"
            ),
            dependencies: [
                .init(
                    packageIdentity: "feature-package",
                    moduleName: "FeatureKit",
                    source: """
                    import InnoDI

                    @DIContainer
                    struct FeatureContainer {}

                    typealias SelectedContainer = FeatureContainer
                    """
                ),
                .init(
                    packageIdentity: "admin-package",
                    moduleName: "AdminKit",
                    source: """
                    import InnoDI

                    @DIContainer
                    struct AdminContainer {}

                    typealias SelectedContainer = AdminContainer
                    """
                ),
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(analysis.edges.only)

        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "FeatureContainer"
            )
        )
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Exact local nominals win over suffix-matched nested aliases")
    func localNominalWinsOverNestedAliasSuffix() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            import FeatureKit

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: SharedContainer())
                var shared: SharedContainer
            }

            @DIContainer
            struct SharedContainer {}

            enum Namespace {
                typealias SharedContainer = FeatureKit.FeatureContainer
            }
            """,
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(
            analysis.edges.filter {
                $0.fromID == fixture.primaryContainerID()
            }.only
        )

        #expect(
            edge.toID == fixture.primaryContainerID(
                named: "SharedContainer"
            )
        )
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("A current-target alias can name a qualified dependency type")
    func currentTargetAliasResolvesQualifiedDependency() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI
            import FeatureKit
            import AdminKit

            typealias SelectedContainer = FeatureKit.FeatureContainer

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: SelectedContainer())
                var feature: SelectedContainer
            }
            """,
            dependencies: [
                featureDependency(),
                .init(
                    packageIdentity: "admin-package",
                    moduleName: "AdminKit",
                    source: """
                    import InnoDI

                    @DIContainer
                    struct AdminContainer {}

                    typealias SelectedContainer = AdminContainer
                    """
                ),
            ]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(analysis.edges.only)

        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "FeatureContainer"
            )
        )
        #expect(try fixture.validateGraph().exitCode == 0)
    }

    @Test("Cross-file aliases use the imports of their declaration file")
    func crossFileAliasUsesDeclarationImports() throws {
        let fixture = try TargetGraphFixture(
            primarySource: """
            import InnoDI

            @DIContainer(root: true)
            struct AppContainer {
                @Provide(.shared, factory: SelectedContainer())
                var feature: SelectedContainer
            }
            """,
            additionalPrimarySources: [
                "Sources/App/Aliases.swift": """
                import FeatureKit

                typealias SelectedContainer = FeatureKit.FeatureContainer
                """
            ],
            dependencies: [featureDependency()]
        )
        defer { fixture.remove() }

        let analysis = try fixture.collectGraph()
        let edge = try #require(analysis.edges.only)

        #expect(
            edge.toID == fixture.dependencyContainerID(
                moduleName: "FeatureKit",
                containerName: "FeatureContainer"
            )
        )
        #expect(try fixture.validateGraph().exitCode == 0)
    }
}

private struct TargetGraphDependencySpec {
    let packageIdentity: String
    let moduleName: String
    let logicalPath: String
    let source: String
    let dependencyModuleNames: [String]

    init(
        packageIdentity: String,
        moduleName: String,
        logicalPath: String? = nil,
        source: String,
        dependencyModuleNames: [String] = []
    ) {
        self.packageIdentity = packageIdentity
        self.moduleName = moduleName
        self.logicalPath = logicalPath
            ?? "Sources/\(moduleName)/Containers.swift"
        self.source = source
        self.dependencyModuleNames = dependencyModuleNames
    }
}

private final class TargetGraphFixture {
    let rootURL: URL
    let primaryTargetID = WorkspaceTargetID.swiftPM(
        packageIdentity: "root-package",
        moduleName: "App"
    )

    private let primarySources: [WorkspaceAnalysisSource]
    private let dependencies: [TargetGraphDependencySpec]
    private let primaryDependencyModuleNames: Set<String>
    private let dependencyTargets: [WorkspaceAnalysisTarget]

    init(
        primaryLogicalPath: String = "Sources/App/App.swift",
        primarySource: String,
        additionalPrimarySources: [String: String] = [:],
        primaryDependencyModuleNames: [String]? = nil,
        dependencies: [TargetGraphDependencySpec]
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-Target-Graph-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let primarySourceURL = rootURL.appendingPathComponent(
            primaryLogicalPath
        )
        try FileManager.default.createDirectory(
            at: primarySourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try primarySource.write(
            to: primarySourceURL,
            atomically: true,
            encoding: .utf8
        )
        var primarySources = [
            WorkspaceAnalysisSource(
                filePath: primarySourceURL.path,
                logicalPath: primaryLogicalPath,
                origin: .declared
            )
        ]
        for (logicalPath, source) in additionalPrimarySources.sorted(
            by: { $0.key < $1.key }
        ) {
            let sourceURL = rootURL.appendingPathComponent(logicalPath)
            try FileManager.default.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try source.write(
                to: sourceURL,
                atomically: true,
                encoding: .utf8
            )
            primarySources.append(
                WorkspaceAnalysisSource(
                    filePath: sourceURL.path,
                    logicalPath: logicalPath,
                    origin: .declared
                )
            )
        }

        var dependencyTargets: [WorkspaceAnalysisTarget] = []
        for dependency in dependencies {
            let packageURL = rootURL
                .appendingPathComponent("Checkouts", isDirectory: true)
                .appendingPathComponent(
                    dependency.packageIdentity,
                    isDirectory: true
                )
            let sourceURL = packageURL.appendingPathComponent(
                dependency.logicalPath
            )
            try FileManager.default.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try dependency.source.write(
                to: sourceURL,
                atomically: true,
                encoding: .utf8
            )

            let targetID = WorkspaceTargetID.swiftPM(
                packageIdentity: dependency.packageIdentity,
                moduleName: dependency.moduleName
            )
            dependencyTargets.append(
                WorkspaceAnalysisTarget(
                    id: targetID,
                    packageIdentity: dependency.packageIdentity,
                    packageDisplayName:
                        "\(dependency.packageIdentity) Package",
                    packageDirectory: packageURL.path,
                    targetName: dependency.moduleName,
                    moduleName: dependency.moduleName,
                    kind: .generic,
                    role: .dependency,
                    sources: [
                        WorkspaceAnalysisSource(
                            filePath: sourceURL.path,
                            logicalPath: dependency.logicalPath,
                            origin: .declared
                        )
                    ],
                    dependencies: dependency.dependencyModuleNames.map {
                        dependencyModuleName in
                        let dependencySpec = dependencies.first {
                            $0.moduleName == dependencyModuleName
                        }
                        precondition(
                            dependencySpec != nil,
                            "Unknown dependency module "
                                + dependencyModuleName
                        )
                        return WorkspaceAnalysisDependency(
                            kind: .target,
                            name: dependencyModuleName,
                            targetIDs: [
                                .swiftPM(
                                    packageIdentity:
                                        dependencySpec!.packageIdentity,
                                    moduleName: dependencyModuleName
                                )
                            ]
                        )
                    }
                )
            )
        }

        self.rootURL = rootURL
        self.primarySources = primarySources
        self.dependencies = dependencies
        self.primaryDependencyModuleNames = Set(
            primaryDependencyModuleNames
                ?? dependencies.map(\.moduleName)
        )
        self.dependencyTargets = dependencyTargets
    }

    func manifest(reversedInput: Bool = false) -> WorkspaceAnalysisManifest {
        let targetDependencies: [WorkspaceAnalysisDependency] =
            dependencyTargets.compactMap { target in
            guard primaryDependencyModuleNames.contains(target.moduleName)
            else {
                return nil
            }
            return WorkspaceAnalysisDependency(
                kind: .product,
                name: "\(target.moduleName)Product",
                packageIdentity: target.packageIdentity,
                targetIDs: [target.id]
            )
        }
        let primaryTarget = WorkspaceAnalysisTarget(
            id: primaryTargetID,
            packageIdentity: "root-package",
            packageDisplayName: "Root Package",
            packageDirectory: rootURL.path,
            targetName: "App",
            moduleName: "App",
            kind: .generic,
            role: .primary,
            sources: primarySources,
            dependencies: reversedInput
                ? Array(targetDependencies.reversed())
                : targetDependencies
        )
        let targets = [primaryTarget] + dependencyTargets

        return WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: rootURL.path,
            primaryTargetID: primaryTargetID,
            targets: reversedInput ? Array(targets.reversed()) : targets
        )
    }

    func loadSnapshot(
        reversedInput: Bool = false
    ) throws -> WorkspaceSourceSnapshot {
        try loadWorkspaceSourceSnapshot(
            manifest: manifest(reversedInput: reversedInput)
        )
    }

    func collectGraph(
        validateDAG: Bool = false
    ) throws -> DependencyGraphAnalysis {
        collectDependencyGraph(
            snapshot: try loadSnapshot(),
            validateDAG: validateDAG
        )
    }

    func collectRenderableGraph() throws -> DependencyGraphAnalysis {
        collectRenderableDependencyGraph(
            snapshot: try loadSnapshot(),
            validateDAG: false,
            rootPruning: .all
        )
    }

    func validateGraph() throws -> DependencyGraphCommandResult {
        validateDependencyGraph(snapshot: try loadSnapshot())
    }

    func targetID(moduleName: String) -> WorkspaceTargetID {
        let dependency = dependencies.first { $0.moduleName == moduleName }
        precondition(dependency != nil, "Unknown fixture module \(moduleName)")
        return .swiftPM(
            packageIdentity: dependency!.packageIdentity,
            moduleName: moduleName
        )
    }

    func primaryContainerID(
        named containerName: String = "AppContainer"
    ) -> String {
        containerID(
            targetID: primaryTargetID,
            containerName: containerName
        )
    }

    func dependencyContainerID(
        moduleName: String,
        containerName: String
    ) -> String {
        containerID(
            targetID: targetID(moduleName: moduleName),
            containerName: containerName
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func featureDependency() -> TargetGraphDependencySpec {
    TargetGraphDependencySpec(
        packageIdentity: "feature-package",
        moduleName: "FeatureKit",
        source: containerSource(named: "FeatureContainer")
    )
}

private func containerSource(named name: String) -> String {
    """
    import InnoDI

    @DIContainer
    struct \(name) {}
    """
}

private func factorySource(
    imports: [String],
    factoryType: String
) -> String {
    let dependencyImports = imports
        .map { "import \($0)" }
        .joined(separator: "\n")
    return """
    import InnoDI
    \(dependencyImports)

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: \(factoryType)())
        var dependency: \(factoryType)
    }
    """
}

private func rootedFactorySource(
    rootName: String,
    childName: String
) -> String {
    """
    import InnoDI

    @DIContainer(root: true)
    struct \(rootName) {
        @Provide(.shared, factory: \(childName)())
        var child: \(childName)
    }

    @DIContainer
    struct \(childName) {}
    """
}

private func containerID(
    targetID: WorkspaceTargetID,
    containerName: String
) -> String {
    "\(targetID.rawValue)::\(containerName)"
}

private func occurrenceCount(_ needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
