import Foundation
import InnoDIDependencyGraphCore
import InnoDIWorkspaceAnalysis
import Testing

@testable import InnoDIDependencyGraphCLI

struct CLIAnalysisManifestFixture {
    let url: URL
    let targetID: WorkspaceTargetID
}

func writeCLIAnalysisManifest(
    for rootURL: URL,
    includingSourcePaths: [String]? = nil
) throws -> CLIAnalysisManifestFixture {
    let packageIdentity = "cli-fixture"
    let moduleName = "FixtureApp"
    let targetID = WorkspaceTargetID.swiftPM(
        packageIdentity: packageIdentity,
        moduleName: moduleName
    )
    let rootPath = rootURL.path(percentEncoded: false)
    let discoveredSourcePaths = try discoverWorkspaceSourceFiles(
        rootPath: rootPath
    )
    let selectedSourcePaths = includingSourcePaths ?? discoveredSourcePaths
    let sources = selectedSourcePaths.sorted().map {
        logicalPath in
        WorkspaceAnalysisSource(
            filePath: rootURL.appendingPathComponent(logicalPath).path(
                percentEncoded: false
            ),
            logicalPath: logicalPath,
            origin: .declared
        )
    }
    let target = WorkspaceAnalysisTarget(
        id: targetID,
        packageIdentity: packageIdentity,
        packageDisplayName: "CLI Fixture",
        packageDirectory: rootPath,
        targetName: moduleName,
        moduleName: moduleName,
        kind: .generic,
        role: .primary,
        sources: sources,
        dependencies: []
    )
    let manifest = WorkspaceAnalysisManifest(
        rootPackageIdentity: packageIdentity,
        rootPackageDirectory: rootPath,
        primaryTargetID: targetID,
        targets: [target]
    )
    let manifestURL = rootURL.appendingPathComponent(
        "workspace-analysis.json"
    )
    try encodeWorkspaceAnalysisManifest(manifest).write(to: manifestURL)
    return CLIAnalysisManifestFixture(url: manifestURL, targetID: targetID)
}

// CLI process helpers (runCLI, CLIRunResult, DataSink, ExecutableNotFound,
// dependencyGraphExecutableURL, packageRootURL) live in `CLIRunner.swift` as
// internal declarations so the snapshot tests can share the same invocation
// pipeline.

func makeFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Fixture-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let appContainerSource = """
    import InnoDI

    protocol APIClientProtocol {}
    struct APIClient: APIClientProtocol {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var baseURL: String

        @Provide(.shared, factory: APIClient())
        var apiClient: any APIClientProtocol
    }
    """

    let featureContainerSource = """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var apiClient: any APIClientProtocol
    }

    func buildFeature(apiClient: any APIClientProtocol) {
        _ = FeatureContainer(apiClient: apiClient)
    }
    """

    try appContainerSource.write(
        to: fixtureURL.appendingPathComponent("AppContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    try featureContainerSource.write(
        to: fixtureURL.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeUnsupportedDeclarationFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "InnoDI-CLI-Unsupported-Declarations-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: fixtureURL,
        withIntermediateDirectories: true
    )

    let source = """
    import InnoDI

    @DIContainer
    final class ClassContainer {
        init() {}
    }

    @DIContainer
    struct GenericContainer<Value> {}

    @DIContainer
    private struct PrivateContainer {}

    struct ExtensionOuter {}
    extension ExtensionOuter {
        @DIContainer
        struct ExtensionNestedContainer {}
    }

    func declareLocalContainer() {
        @DIContainer
        struct LocalContainer {}
    }

    struct AccessorHost {
        var value: Int {
            @DIContainer
            struct AccessorContainer {}
            return 0
        }
    }

    @DIContainer(root: true)
    struct ValidContainer {}
    """
    try source.write(
        to: fixtureURL.appendingPathComponent("Containers.swift"),
        atomically: true,
        encoding: .utf8
    )
    return fixtureURL
}

func makeUnsupportedNestedContainerFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "InnoDI-CLI-Unsupported-Nested-Usage-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: fixtureURL,
        withIntermediateDirectories: true
    )

    let source = """
    @DIContainer
    struct Parent {
        @DIContainer
        struct Unsupported<Value> {
            @Provide(.shared, factory: Child())
            var child: Child
        }

        @DIContainer
        protocol UnsupportedProtocol {
            @Provide(.shared, factory: Child())
            var child: Child { get }
        }
    }

    @DIContainer
    struct Child {}

    func first() {
        @DIContainer
        struct LocalContainer {
            @Provide(.input) var config: String
        }
    }

    func second() {
        @DIContainer
        struct LocalContainer {
            @Provide(.input) var count: Int
        }
    }

    let closure = {
        @DIContainer
        struct ClosureContainer {
            @Provide(.input) var flag: Bool
        }
    }

    struct AccessorHost {
        var value: Int {
            @DIContainer
            struct AccessorContainer {
                @Provide(.input) var token: String
            }
            return 0
        }
    }
    """
    try source.write(
        to: fixtureURL.appendingPathComponent("Containers.swift"),
        atomically: true,
        encoding: .utf8
    )
    return fixtureURL
}

func makeDeferredEdgeFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Deferred-Edges-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    struct LazyConsumer {
        let admin: Lazy<AdminContainer>
        init(admin: Lazy<AdminContainer>) { self.admin = admin }
    }

    func buildFeatureContainer() -> FeatureContainer { fatalError() }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: buildFeatureContainer())
        var feature: FeatureContainer

        @Provide(.input)
        var admin: AdminContainer

        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        })
        var providerConsumer: ProviderConsumer

        @Provide(.shared, factory: { (admin: Lazy<AdminContainer>) in
            LazyConsumer(admin: admin)
        })
        var lazyConsumer: LazyConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var seed: Int
    }

    @DIContainer
    struct AdminContainer {
        @Provide(.input)
        var seed: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("DeferredEdges.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeQualifiedDeferredEdgeFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Qualified-Deferred-Edges-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: InnoDI.Provider<FeatureContainer>
        init(feature: InnoDI.Provider<FeatureContainer>) { self.feature = feature }
    }

    struct LazyConsumer {
        let admin: InnoDI.Lazy<AdminContainer>
        init(admin: InnoDI.Lazy<AdminContainer>) { self.admin = admin }
    }

    func buildFeatureContainer() -> FeatureContainer { fatalError() }

    @InnoDI.DIContainer(root: true)
    struct AppContainer {
        @InnoDI.Provide(.transient, factory: buildFeatureContainer())
        var feature: FeatureContainer

        @InnoDI.Provide(.input)
        var admin: AdminContainer

        @InnoDI.Provide(.shared, factory: { (feature: InnoDI.Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        })
        var providerConsumer: ProviderConsumer

        @InnoDI.Provide(.shared, factory: { (admin: InnoDI.Lazy<AdminContainer>) in
            LazyConsumer(admin: admin)
        })
        var lazyConsumer: LazyConsumer
    }

    @InnoDI.DIContainer
    struct FeatureContainer {
        @InnoDI.Provide(.input)
        var seed: Int
    }

    @InnoDI.DIContainer
    struct AdminContainer {
        @InnoDI.Provide(.input)
        var seed: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("QualifiedDeferredEdges.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeProvideConstructionFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Provide-Construction-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    protocol GreetingService {}
    struct LiveGreetingService: GreetingService {}
    struct APIClient {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: APIClient())
        var apiClient: APIClient

        @Provide(.shared, factory: LiveGreetingService())
        var greetingService: any GreetingService
    }
    """.write(
        to: fixtureURL.appendingPathComponent("AppContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeRootedOwnershipRenderFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Rooted-Ownership-Render-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    struct AppConfig {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: AppConfig

        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct OrphanContainer {
        @Provide(.input)
        var config: AppConfig
    }
    """.write(
        to: fixtureURL.appendingPathComponent("RootedOwnership.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeMultipleRootRenderFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Multiple-Root-Render-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    struct AppConfig {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: AppConfig

        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }

    @DIContainer(root: true)
    struct AdminContainer {
        @Provide(.input)
        var config: AppConfig

        @SubContainer(scope: .shared)
        var adminFeature: AdminFeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct AdminFeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct OrphanContainer {
        @Provide(.input)
        var config: AppConfig
    }
    """.write(
        to: fixtureURL.appendingPathComponent("MultipleRoots.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeRootlessRenderFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Rootless-Render-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    struct AppConfig {}

    @DIContainer
    struct AppContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct OrphanContainer {
        @Provide(.input)
        var config: AppConfig
    }
    """.write(
        to: fixtureURL.appendingPathComponent("Rootless.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeTypeAliasReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-TypeAlias-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: String
    }

    typealias ActiveContainer = AppContainer

    func buildFeature(config: String) {
        _ = ActiveContainer(config: config)
    }
    """.write(
        to: fixtureURL.appendingPathComponent("TypeAliasFeature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeNestedTypeAliasReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Nested-TypeAlias-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    enum Feature {
        @DIContainer
        struct LiveContainer {
            @Provide(.input)
            var config: String
        }

        typealias ActiveContainer = LiveContainer
    }

    typealias RootAlias = Feature.ActiveContainer

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: String
    }

    func buildFeature(config: String) {
        _ = RootAlias(config: config)
    }
    """.write(
        to: fixtureURL.appendingPathComponent("NestedTypeAliasFeature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeSubContainerTypeAliasCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-SubContainer-TypeAlias-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    typealias FeatureAlias = FeatureContainer

    @DIContainer(root: true)
    struct AppContainer {
        @SubContainer(scope: .shared)
        var feature: FeatureAlias
    }
    """.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )

    try """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer())
        var app: AppContainer
    }
    """.write(
        to: fixtureURL.appendingPathComponent("Feature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeUnresolvedReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Unresolved-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: String

        @Provide(.shared, factory: { (config: String) in
            MissingFeatureContainer(config: config)
        })
        var feature: MissingFeatureContainer
    }
    """.write(
        to: fixtureURL.appendingPathComponent("UnresolvedFeature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeProviderDeferredCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Provider-Deferred-Cycle-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    func buildFeatureContainer() -> FeatureContainer { fatalError() }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: buildFeatureContainer())
        var feature: FeatureContainer

        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        })
        var providerConsumer: ProviderConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer())
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("ProviderDeferredCycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeLazyDeferredCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Lazy-Deferred-Cycle-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct LazyConsumer {
        let feature: Lazy<FeatureContainer>
        init(feature: Lazy<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var feature: FeatureContainer

        @Provide(.shared, factory: { (feature: Lazy<FeatureContainer>) in
            LazyConsumer(feature: feature)
        })
        var lazyConsumer: LazyConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer())
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("LazyDeferredCycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeDeferredServiceWrapperFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Deferred-Service-Wrapper-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    final class Request {}
    final class RequestLogger {
        let requests: Provider<Request>
        init(requests: Provider<Request>) { self.requests = requests }
    }

    final class TransientService {}
    final class ServiceHolder {
        let service: Lazy<TransientService>
        init(service: Lazy<TransientService>) { self.service = service }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: { Request() })
        var request: Request

        @Provide(.shared, factory: { (request: Provider<Request>) in
            RequestLogger(requests: request)
        })
        var logger: RequestLogger

        @Provide(.transient, factory: { TransientService() })
        var service: TransientService

        @Provide(.shared, factory: { (service: Lazy<TransientService>) in
            ServiceHolder(service: service)
        })
        var holder: ServiceHolder
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("DeferredServiceWrappers.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeAmbiguousDeferredReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-Deferred-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        })
        var providerConsumer: ProviderConsumer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: Int
        }
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeExcludedDeferredReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Excluded-Deferred-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct LazyConsumer {
        let feature: Lazy<FeatureContainer>
        init(feature: Lazy<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: { (feature: Lazy<FeatureContainer>) in
            LazyConsumer(feature: feature)
        })
        var consumer: LazyConsumer
    }

    @DIContainer(validateDAG: false)
    struct FeatureContainer {
        @Provide(.input)
        var value: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("ExcludedDeferred.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeDeferredUnresolvedReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Unresolved-Deferred-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct LazyConsumer {
        let feature: Lazy<MissingFeatureContainer>
        init(feature: Lazy<MissingFeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: { (feature: Lazy<MissingFeatureContainer>) in
            LazyConsumer(feature: feature)
        })
        var consumer: LazyConsumer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("UnresolvedDeferred.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeNoContainerFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-NoContainer-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    struct PlainType {
        let value: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("Plain.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeMixedHardAndProviderCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Mixed-Hard-Provider-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: FeatureContainer())
        var feature: FeatureContainer

        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        })
        var providerConsumer: ProviderConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer())
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("MixedHardProviderCycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Cycle-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer())
        var feature: FeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer())
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("Cycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeRootSkippedDirectoryFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Root-Skips-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var baseURL: String
    }
    """

    let skippedSource = """
    import InnoDI

    @DIContainer(root: true)
    struct SkippedA {
        @Provide(.shared, factory: SkippedB())
        var b: SkippedB
    }

    @DIContainer
    struct SkippedB {
        @Provide(.shared, factory: SkippedA())
        var a: SkippedA
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )

    for directoryName in ["Pods", "Derived", "Carthage"] {
        let directoryURL = fixtureURL.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try skippedSource.write(
            to: directoryURL.appendingPathComponent("Poison.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    return fixtureURL
}

func makeValidateDAGOptOutFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Cycle-OptOut-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer())
        var feature: FeatureContainer
    }

    @DIContainer(validateDAG: false)
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer())
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("CycleOptOut.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeAmbiguousReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer())
        var feature: FeatureContainer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: Int
        }
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeAmbiguousSubContainerReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-SubContainer-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer
        struct FeatureContainer {}
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer
        struct FeatureContainer {}
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeAmbiguousOptedOutReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-OptedOut-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer())
        var feature: FeatureContainer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer(validateDAG: false)
        struct FeatureContainer {
            @Provide(.input)
            var value: Int
        }
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer(validateDAG: false)
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

func makeMixedEligibilityDuplicateNameCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-MixedEligibility-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureDirectory = fixtureURL.appendingPathComponent("Feature", isDirectory: true)
    let namespaceDirectory = fixtureURL.appendingPathComponent("Namespace", isDirectory: true)
    try FileManager.default.createDirectory(at: featureDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: namespaceDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer())
        var feature: FeatureContainer
    }
    """

    let eligibleFeatureSource = """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer())
        var app: AppContainer
    }
    """

    let optedOutDuplicateSource = """
    import InnoDI

    enum Namespace {
        @DIContainer(validateDAG: false)
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try eligibleFeatureSource.write(
        to: featureDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try optedOutDuplicateSource.write(
        to: namespaceDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}
