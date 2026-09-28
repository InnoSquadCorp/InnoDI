import Foundation
import Testing
import InnoDIBuildSupport
import InnoDITestSupport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("Strict concurrency build integration", .serialized, .tags(.slow))
struct StrictConcurrencyBuildTests {
    @Test("Deferred wrappers build under strict concurrency inside a non-Sendable container")
    func deferredWrappersBuildInsideRegularContainer() throws {
        let fixture = try makeStrictConcurrencyFixture(
            name: "DeferredWrappersInRegularContainer",
            dependencies: ["InnoDI"],
            source: """
            import InnoDI

            struct Config: Sendable {}
            struct Service: Sendable {}

            struct LazyHolder {
                let lazy: InnoDI.Lazy<Service>
            }

            struct ProviderHolder {
                let provider: InnoDI.Provider<Service>
            }

            @DIContainer
            struct AsyncContainer {
                @Provide(.shared, asyncFactory: { () async in Service() })
                var service: Service
            }

            @DIContainer
            struct AppContainer {
                @Input
                var config: Config

                @Provide(.transient, factory: { Service() })
                var service: Service

                @Provide(.shared, factory: { (service: InnoDI.Lazy<Service>) in
                    LazyHolder(lazy: service)
                })
                var lazyHolder: LazyHolder

                @Provide(.shared, factory: { (service: InnoDI.Provider<Service>) in
                    ProviderHolder(provider: service)
                })
                var providerHolder: ProviderHolder
            }

            @main
            struct FixtureApp {
                static func main() {
                    let container = AppContainer(config: Config())
                    let _: LazyHolder = container.lazyHolder
                    let _: ProviderHolder = container.providerHolder
                    let _: AsyncContainer = AsyncContainer()
                }
            }
            """)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try runStrictConcurrencyBuild(packageURL: fixture)

        if result.timedOut || result.exitCode != 0 {
            Issue.record("swift build failed:\n\(result.stdout)\n\(result.stderr)")
        }
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)
    }

    @Test("SwiftUI main-actor root builds under strict concurrency")
    func swiftUIMainActorRootBuildsUnderStrictConcurrency() throws {
        let fixture = try makeStrictConcurrencyFixture(
            name: "MainActorSwiftUI",
            dependencies: ["InnoDI", "InnoDISwiftUI"],
            source: """
            import SwiftUI
            import InnoDI
            import InnoDISwiftUI

            struct Greeting: Sendable {
                let value = "hello"
            }

            struct GreetingKey: EnvironmentKey {
                static let defaultValue = Greeting()
            }

            extension EnvironmentValues {
                var greeting: Greeting {
                    get { self[GreetingKey.self] }
                    set { self[GreetingKey.self] = newValue }
                }
            }

            @DIEnvironmentBridge([
                (member: "greeting", environment: \\EnvironmentValues.greeting),
            ])
            @DIContainerRole(role: ContainerRole.local, mainActor: true)
            struct AppContainer {
                @Provide(.shared, factory: Greeting())
                var greeting: Greeting
            }

            struct RootView: View {
                let container: AppContainer

                var body: some View {
                    Text("Hello")
                        .innodi(container)
                }
            }

            @MainActor
            func buildRoot() -> some View {
                RootView(container: AppContainer())
            }

            @main
            struct FixtureApp {
                @MainActor
                static func main() {
                    let _ = buildRoot()
                }
            }
            """)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try runStrictConcurrencyBuild(packageURL: fixture)

        if result.timedOut || result.exitCode != 0 {
            Issue.record("swift build failed:\n\(result.stdout)\n\(result.stderr)")
        }
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)
    }

    @Test("GenerateMock builds for top-level overloaded and generic protocol methods")
    func generateMockConsumerSurfaceBuilds() throws {
        let fixture = try makeStrictConcurrencyFixture(
            name: "GenerateMockConsumerSurface",
            dependencies: ["InnoDI"],
            source: """
            import InnoDI

            @GenerateMock
            protocol API {
                func fetch(id: String) -> String
                func fetch(page: Int) -> String
            }

            @GenerateMock
            protocol GenericAPI {
                func make<T>(_ type: T.Type) -> T
                func fail<T>(_ type: T.Type) throws -> T
                func wait<T>(_ type: T.Type) async -> T
                func load<T>(_ type: T.Type) async throws -> T
            }

            @GenerateMock
            protocol AsyncAPI {
                func fetch(id: String) async throws -> String
                func refresh() async throws
            }

            @GenerateMock
            protocol CallbackAPI {
                mutating func bump(`repeat`: Int)
                func observe(_ handler: @escaping @Sendable () -> Void)
                func reset() -> ()
            }

            @GenerateMock
            protocol GreeterAPI {
                var prefix: String { get set }
                var fallback: String? { get set }
            }

            protocol Event: Sendable {}
            struct ConcreteEvent: Event {}

            @GenerateMock
            protocol EventFactory {
                func makeEvent() -> any Event
                func makeHandler() -> @Sendable () -> Void
            }

            @GenerateMock
            private protocol PrivateAPI {
                func privateValue() -> String
            }

            @GenerateMock
            fileprivate protocol FileprivateAPI {
                func fileprivateValue() -> String
            }

            @main
            struct FixtureApp {
                static func main() async throws {
                    let api = APIMock()
                    api.fetchIdStringReturnValue = "id"
                    api.fetchPageIntReturnValue = "page"
                    _ = api.fetch(id: "42")
                    _ = api.fetch(page: 1)

                    try await exerciseGenericAPI()

                    let asyncAPI = AsyncAPIMock()
                    asyncAPI.fetchResult = .success("async")
                    _ = try await asyncAPI.fetch(id: "42")
                    try await asyncAPI.refresh()

                    let callbacks = CallbackAPIMock()
                    callbacks.bump(repeat: 1)
                    callbacks.observe {}
                    callbacks.reset()

                    let greeter = GreeterAPIMock()
                    greeter.prefix = "Hello"
                    greeter.fallback = nil
                    _ = greeter.prefix
                    _ = greeter.fallback

                    let eventFactory = EventFactoryMock()
                    eventFactory.makeEventReturnValue = ConcreteEvent()
                    eventFactory.makeHandlerReturnValue = {}
                    _ = eventFactory.makeEvent()
                    eventFactory.makeHandler()()

                    let privateAPI = PrivateAPIMock()
                    privateAPI.privateValueReturnValue = "private"
                    _ = privateAPI.privateValue()

                    let fileprivateAPI = FileprivateAPIMock()
                    fileprivateAPI.fileprivateValueReturnValue = "fileprivate"
                    _ = fileprivateAPI.fileprivateValue()
                }

                nonisolated static func exerciseGenericAPI() async throws {
                    let generic = GenericAPIMock()
                    generic.makeUnlabeledTTypeHandler = { _ in "made" }
                    generic.failUnlabeledTTypeHandler = { _ in "failed" }
                    generic.waitUnlabeledTTypeHandler = { _ in "waited" }
                    generic.loadUnlabeledTTypeHandler = { _ in "loaded" }

                    let _: String = generic.make(String.self)
                    let _: String = try generic.fail(String.self)
                    let _: String = await generic.wait(String.self)
                    let _: String = try await generic.load(String.self)
                }
            }
            """)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try runStrictConcurrencyBuild(packageURL: fixture)

        if result.timedOut || result.exitCode != 0 {
            Issue.record("swift build failed:\n\(result.stdout)\n\(result.stderr)")
        }
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)
    }

    @Test("PreviewWithContainer builds without ViewBuilder warnings")
    func previewWithContainerConsumerSurfaceBuilds() throws {
        let fixture = try makeStrictConcurrencyFixture(
            name: "PreviewWithContainerConsumerSurface",
            dependencies: ["InnoDISwiftUI"],
            source: """
            import SwiftUI
            import InnoDISwiftUI

            struct PreviewContainer {
                let title: String
            }

            struct PreviewRootView: View {
                let container: PreviewContainer

                var body: some View {
                    Text(container.title)
                }
            }

            #PreviewWithContainer(PreviewContainer(title: "Preview")) { container in
                PreviewRootView(container: container)
            }

            @main
            struct FixtureApp {
                static func main() {
                    _ = PreviewRootView(container: PreviewContainer(title: "Runtime"))
                }
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try runStrictConcurrencyBuild(packageURL: fixture)

        if result.timedOut || result.exitCode != 0 {
            Issue.record("swift build failed:\n\(result.stdout)\n\(result.stderr)")
        }
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)
    }

    @Test("DAG validation plugin state follows an explicit scratch path")
    func dagValidationPluginStateFollowsScratchPath() throws {
        let fixture = try makeStrictConcurrencyFixture(
            name: "PluginScratchPath",
            dependencies: ["InnoDI"],
            plugins: ["InnoDIDAGValidationPlugin"],
            source: """
            import InnoDI

            struct Service: Sendable {}

            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service
            }

            @main
            struct FixtureApp {
                static func main() {
                    _ = AppContainer().service
                }
            }
            """)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-PluginScratch-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: scratch)
        }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let result = try runStrictConcurrencyBuild(packageURL: fixture, scratchPath: scratch)

        if result.timedOut || result.exitCode != 0 {
            Issue.record("swift build failed:\n\(result.stdout)\n\(result.stderr)")
        }
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture
                    .appendingPathComponent(".build/innodi-dag-validation", isDirectory: true)
                    .path(percentEncoded: false)
            )
        )
        let orderingSources = try findFiles(named: "_InnoDIDAGValidation.generated.swift", under: scratch)
        #expect(!orderingSources.isEmpty)
        let warm = try runStrictConcurrencyBuild(packageURL: fixture, scratchPath: scratch)
        #expect(!warm.timedOut)
        #expect(warm.exitCode == 0, "Unchanged valid package must still build: \(warm.stdout)\n\(warm.stderr)")
    }

    @Test("DAG validation plugin isolates state across plugin-attached targets", .tags(.slow))
    func dagValidationPluginIsolatesStateAcrossTargets() throws {
        let fixture = try makeMultiTargetPluginFixture()
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-MultiTargetPlugin-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: scratch)
        }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let result = try runStrictConcurrencyBuild(packageURL: fixture, scratchPath: scratch)

        if result.timedOut || result.exitCode != 0 {
            Issue.record("swift build failed:\n\(result.stdout)\n\(result.stderr)")
        }
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)

        let stampURLs = try findFiles(named: "dag-validation-stamp.txt", under: scratch)
        let orderingSources = try findFiles(named: "_InnoDIDAGValidation.generated.swift", under: scratch)
        let metricsURLs = try findFiles(named: "dag-validation-metrics.json", under: scratch)
        let sharedStateDirectories = try findDirectories(named: "innodi-dag-validation-state", under: scratch)
        let metrics = try metricsURLs.map { url in
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ValidationMetricsArtifact.self, from: data)
        }

        #expect(stampURLs.count >= 2)
        #expect(orderingSources.count == 2)
        #expect(orderingSources.allSatisfy {
            FileManager.default.fileExists(atPath: $0.deletingLastPathComponent()
                .appendingPathComponent("dag-validation-stamp.txt").path)
        })
        #expect(metrics.count >= 2)
        #expect(sharedStateDirectories.count == 2)
        #expect(Set(metrics.map(\.signature)).count >= 2)
        var targetStateDirectoryNames: Set<String> = []
        for sharedStateDirectory in sharedStateDirectories {
            #expect(
                sharedStateDirectory.deletingLastPathComponent().lastPathComponent
                    == "InnoDIDAGValidationPlugin"
            )
            let targetStateRoot = sharedStateDirectory.appendingPathComponent(
                "targets",
                isDirectory: true
            )
            let targetStateDirectories = try FileManager.default
                .contentsOfDirectory(
                    at: targetStateRoot,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                .filter {
                    try $0.resourceValues(
                        forKeys: [.isDirectoryKey]
                    ).isDirectory == true
                }
            let sharedRunResults = try findFiles(
                named: "result.json",
                under: targetStateRoot
            )
            #expect(targetStateDirectories.count == 1)
            #expect(sharedRunResults.count == 1)
            targetStateDirectoryNames.formUnion(
                targetStateDirectories.map(\.lastPathComponent)
            )
        }
        #expect(targetStateDirectoryNames.count == 2)
    }

    @Test("Deferred wrappers remain non-Sendable even when the payload is Sendable")
    func deferredWrappersStillFailInSendableHolders() throws {
        let fixture = try makeStrictConcurrencyFixture(
            name: "SendableHolderWithDeferredWrappers",
            dependencies: ["InnoDI"],
            source: """
            import InnoDI

            struct Payload: Sendable {}

            struct Holder: Sendable {
                let lazy: InnoDI.Lazy<Payload>
                let provider: InnoDI.Provider<Payload>
            }

            let _ = Holder(
                lazy: InnoDI.Lazy { Payload() },
                provider: InnoDI.Provider { Payload() }
            )
            """)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try runStrictConcurrencyBuild(packageURL: fixture)
        let combinedOutput = result.stdout + "\n" + result.stderr

        #expect(!result.timedOut)
        #expect(result.exitCode != 0)
        #expect(
            combinedOutput.contains(
                "stored property 'lazy' of 'Sendable'-conforming struct 'Holder' has non-Sendable type 'Lazy<Payload>'"
            )
        )
        #expect(
            combinedOutput.contains(
                "stored property 'provider' of 'Sendable'-conforming struct 'Holder' has non-Sendable type 'Provider<Payload>'"
            )
        )
    }

    @Test("On-demand handles cannot hide unsafe payloads, overrides, or factory captures")
    func onDemandSendabilityBoundary() throws {
        let declarations = """
        import InnoDI

        final class MutableValue { var count = 0 }

        @DIContainer
        struct RegularContainer {
            @Provide(.shared, initialization: .onDemand, factory: { MutableValue() })
            var value: MutableValue
        }

        @DIContainerRole(role: ContainerRole.local, mainActor: true)
        struct IsolatedContainer {
            @Provide(.shared, initialization: .onDemand, factory: { MutableValue() })
            var value: MutableValue
        }

        @DIContainer
        struct EagerSendableContainer: Sendable {
            @Provide(.shared, factory: { 7 }) var value: Int
        }

        @DIContainer
        struct CheckedAsyncChain {
            @Provide(.shared, initialization: .onDemand, factory: { 7 }) var first: Int
            @Provide(.shared, initialization: .onDemand, factory: { (first: Int) in first + 1 })
            var second: Int
            @Provide(.shared, asyncFactory: { (second: Int) async in second + 1 }) var result: Int
        }
        """
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-OnDemandSendability-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        for scenario in ["control", "holders", "factory", "payload"] {
            let invalid = scenario != "control"
            let rejectionSource: String
            switch scenario {
            case "holders":
                rejectionSource = """

            @DIContainer
            struct UnsafeContainer: Sendable {
                @Provide(.shared, initialization: .onDemand, factory: { MutableValue() })
                var value: MutableValue
            }

            struct UnsafeFactoryHolder: Sendable {
                let captured: _InnoDISharedCell<Int>
                init() {
                    let value = MutableValue()
                    captured = _InnoDISharedCell(factory: { value.count += 1; return value.count })
                }
            }

            struct UnsafeOverrideHolder: Sendable {
                let overridden = _InnoDISharedCell(value: MutableValue())
            }
            """
            case "factory":
                rejectionSource = """
            func rejectUnsafeFactoryCapture(_ mutable: MutableValue) {
                _ = _InnoDISendableSharedCell<Int>(traceOwner: .disabled, providerName: "unsafe") {
                    mutable.count += 1
                    return mutable.count
                }
            }
            """
            case "payload":
                rejectionSource = """
            func rejectUnsafePayload() {
                _ = _InnoDISendableSharedCell(traceOwner: .disabled, providerName: "unsafe", value: MutableValue())
            }
            """
            default:
                rejectionSource = ""
            }
            let source = declarations + "\n" + (invalid ? rejectionSource : """

            @main struct FixtureApp {
                @MainActor static func main() async {
                    let container = RegularContainer()
                    precondition(container.value === container.value)
                    let override = MutableValue()
                    precondition(RegularContainer(value: override).value === override)
                    let isolated = IsolatedContainer()
                    precondition(isolated.value === isolated.value)
                    precondition(EagerSendableContainer().value == 7)
                    await exerciseAsyncChain()
                }

                nonisolated static func exerciseAsyncChain() async {
                    let chain = CheckedAsyncChain()
                    let result = await chain.result
                    precondition(result == 9)
                    let overriddenChain = CheckedAsyncChain(first: 20)
                    let overriddenResult = await overriddenChain.result
                    precondition(overriddenResult == 22)
                }
            }
            """)
            let fixture = try makeStrictConcurrencyFixture(
                name: "OnDemandSendability", dependencies: ["InnoDI"], source: source
            )
            defer { try? FileManager.default.removeItem(at: fixture) }
            let result = try runStrictConcurrencyBuild(packageURL: fixture, scratchPath: scratch)
            let output = result.stdout + result.stderr
            #expect(!result.timedOut)
            if invalid {
                #expect(result.exitCode != 0)
                if scenario == "holders" {
                    for name in ["UnsafeContainer", "UnsafeFactoryHolder", "UnsafeOverrideHolder"] {
                        #expect(output.contains("'Sendable'-conforming struct '\(name)'"), "\(output)")
                    }
                    #expect(output.contains("non-Sendable type"))
                    #expect(output.contains("_InnoDISharedCell"))
                } else if scenario == "factory" {
                    #expect(output.contains("capture of 'mutable'"), "\(output)")
                } else {
                    #expect(output.contains("does not conform to the 'Sendable' protocol"), "\(output)")
                }
            } else {
                #expect(result.exitCode == 0, "\(output)")
                guard result.exitCode == 0, !result.timedOut else { continue }
                let execution = try runExternalConsumerExecutable(packageURL: fixture, scratchPath: scratch)
                #expect(!execution.timedOut)
                #expect(execution.exitCode == 0)
            }
        }
    }

    @Test("Public collection metadata rejects captured non-Sendable key paths")
    func collectionMetadataSendabilityBoundary() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-MetadataSendability-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        for scenario in ["control", "ordered", "providers", "keyed", "erased"] {
            let construction: String = switch scenario {
            case "ordered": "_ = DICollectionMetadata.ordered([\\Root.[key]])"
            case "providers": "_ = DICollectionMetadata.providers([\\Root.[key]])"
            case "keyed": "_ = DIKeyedCollectionContribution(key: \"value\", contributor: \\Root.[key])"
            case "erased": "let path: AnyKeyPath = \\Root.value; _ = DICollectionMetadata.ordered([path])"
            default: """
                let ordered = DICollectionMetadata.ordered([\\Root.value])
                let keyed = DICollectionMetadata.keyed([.init(key: "value", contributor: \\Root.value)])
                precondition(ordered.contributors.count == 1 && keyed.keyedContributors.count == 1)
                """
            }
            let fixture = try makeStrictConcurrencyFixture(
                name: "MetadataSendability", dependencies: ["InnoDI"], source: """
                import InnoDI
                final class MutableKey: Hashable {
                    var count = 0
                    static func == (lhs: MutableKey, rhs: MutableKey) -> Bool { lhs === rhs }
                    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
                }
                struct Root {
                    var value: Int { 7 }
                    subscript(key: MutableKey) -> Int { key.count }
                }
                @main struct FixtureApp {
                    static func main() {
                        let key = MutableKey()
                        _ = key
                        \(construction)
                    }
                }
                """
            )
            defer { try? FileManager.default.removeItem(at: fixture) }
            let result = try runStrictConcurrencyBuild(packageURL: fixture, scratchPath: scratch)
            let output = result.stdout + result.stderr
            #expect(!result.timedOut)
            if scenario == "control" {
                #expect(result.exitCode == 0, "\(output)")
                guard result.exitCode == 0, !result.timedOut else { continue }
                let execution = try runExternalConsumerExecutable(packageURL: fixture, scratchPath: scratch)
                #expect(!execution.timedOut)
                #expect(execution.exitCode == 0)
            } else {
                #expect(result.exitCode != 0, "\(scenario) must reject unsafe erasure")
                #expect(output.contains("Sendable"), "\(output)")
                #expect(output.contains(scenario == "erased" ? "AnyKeyPath" : "MutableKey"), "\(output)")
            }
        }
    }

    @Test("Timeout path terminates descendants that keep pipes open")
    func timeoutPathTerminatesDescendants() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "trap '' TERM; sleep 30 & echo child=$!; wait"
        ]
        process.currentDirectoryURL = packageRootURL()

        let result = try runCapturedProcess(
            process,
            timeoutSeconds: 1.0,
            terminationGraceSeconds: 0.5,
            hardKillGraceSeconds: 0.5
        )

        #expect(result.timedOut)
        let childProcessID = result.stdout
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("child=") })
            .flatMap { Int32($0.dropFirst("child=".count)) }
        let capturedChildProcessID = try #require(childProcessID)
        #expect(waitForProcessExit(capturedChildProcessID))
    }
}

private func waitForProcessExit(_ processID: Int32) -> Bool {
    for _ in 0..<100 {
        if kill(processID, 0) == -1, errno == ESRCH {
            return true
        }
        usleep(10_000)
    }
    return kill(processID, 0) == -1 && errno == ESRCH
}

typealias StrictConcurrencyBuildResult = CapturedProcessResult

func runStrictConcurrencyBuild(
    packageURL: URL,
    scratchPath: URL? = nil
) throws -> StrictConcurrencyBuildResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var arguments = [
        "swift",
        "build",
        "--package-path",
        packageURL.path(percentEncoded: false),
    ]
    if let scratchPath {
        arguments.append(contentsOf: [
            "--scratch-path",
            scratchPath.path(percentEncoded: false),
        ])
    }
    arguments.append(contentsOf: [
        "-Xswiftc",
        "-strict-concurrency=complete",
        "-Xswiftc",
        "-warnings-as-errors",
    ])
    process.arguments = arguments
    process.currentDirectoryURL = packageRootURL()

    return try runCapturedProcess(
        process,
        timeoutSeconds: strictConcurrencyBuildTimeoutSeconds,
        terminationGraceSeconds: strictConcurrencyTerminationGracePeriodSeconds,
        hardKillGraceSeconds: strictConcurrencyHardKillGracePeriodSeconds
    )
}

func runExternalConsumerExecutable(
    packageURL: URL,
    scratchPath: URL? = nil,
    executable: String = "FixtureApp"
) throws -> StrictConcurrencyBuildResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var arguments = [
        "swift",
        "run",
        "--package-path",
        packageURL.path(percentEncoded: false),
    ]
    if let scratchPath {
        arguments.append(contentsOf: [
            "--scratch-path",
            scratchPath.path(percentEncoded: false),
        ])
    }
    arguments.append(contentsOf: [
        "--skip-build",
        executable,
    ])
    process.arguments = arguments
    process.currentDirectoryURL = packageRootURL()

    return try runCapturedProcess(
        process,
        timeoutSeconds: strictConcurrencyBuildTimeoutSeconds,
        terminationGraceSeconds: strictConcurrencyTerminationGracePeriodSeconds,
        hardKillGraceSeconds: strictConcurrencyHardKillGracePeriodSeconds
    )
}

func runExternalDependencyGraphExecutable(
    packageURL: URL,
    scratchPath: URL? = nil
) throws -> StrictConcurrencyBuildResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var arguments = [
        "swift",
        "run",
        "--package-path",
        packageURL.path(percentEncoded: false),
    ]
    if let scratchPath {
        arguments.append(contentsOf: [
            "--scratch-path",
            scratchPath.path(percentEncoded: false),
        ])
    }
    arguments.append(contentsOf: [
        "InnoDI-DependencyGraph",
        "--root",
        packageURL.path(percentEncoded: false),
        "--root-pruning",
        "all",
        "--format",
        "ascii",
    ])
    process.arguments = arguments
    process.currentDirectoryURL = packageRootURL()

    return try runCapturedProcess(
        process,
        timeoutSeconds: strictConcurrencyBuildTimeoutSeconds,
        terminationGraceSeconds: strictConcurrencyTerminationGracePeriodSeconds,
        hardKillGraceSeconds: strictConcurrencyHardKillGracePeriodSeconds
    )
}

private func makeStrictConcurrencyFixture(
    name: String,
    dependencies: [String],
    plugins: [String] = [],
    source: String
) throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-StrictConcurrency-\(name)-\(UUID().uuidString)", isDirectory: true)
    let sourcesURL = rootURL.appendingPathComponent("Sources/FixtureApp", isDirectory: true)

    try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)

    let packageIdentity = packageIdentityInfo(packageRootURL: packageRootURL())
    let escapedRepoPath = packageIdentity.escapedRepoPath
    let dependencyPackageIdentity = packageIdentity.dependencyPackageIdentity

    let dependencyList = dependencies
        .map { ".product(name: \"\($0)\", package: \"\(dependencyPackageIdentity)\")" }
        .joined(separator: ", ")
    let pluginList = plugins
        .map { ".plugin(name: \"\($0)\", package: \"\(dependencyPackageIdentity)\")" }
        .joined(separator: ", ")
    let pluginsClause = pluginList.isEmpty ? "" : ",\n                plugins: [\(pluginList)]"

    let manifest = """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "\(name)",
        platforms: [
            .macOS(.v14),
            .iOS(.v17)
        ],
        dependencies: [
            .package(path: "\(escapedRepoPath)")
        ],
        targets: [
            .executableTarget(
                name: "FixtureApp",
                dependencies: [\(dependencyList)]\(pluginsClause)
            )
        ]
    )
    """

    try manifest.write(
        to: rootURL.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8
    )
    try source.write(
        to: sourcesURL.appendingPathComponent("FixtureApp.swift"),
        atomically: true,
        encoding: .utf8
    )

    return rootURL
}

private func makeMultiTargetPluginFixture() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-MultiTargetPluginFixture-\(UUID().uuidString)", isDirectory: true)
    let featureAURL = rootURL.appendingPathComponent("Sources/FeatureA", isDirectory: true)
    let featureBURL = rootURL.appendingPathComponent("Sources/FeatureB", isDirectory: true)

    try FileManager.default.createDirectory(at: featureAURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBURL, withIntermediateDirectories: true)

    let packageIdentity = packageIdentityInfo(packageRootURL: packageRootURL())
    let escapedRepoPath = packageIdentity.escapedRepoPath
    let dependencyPackageIdentity = packageIdentity.dependencyPackageIdentity

    let manifest = """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "MultiTargetPluginFixture",
        platforms: [
            .macOS(.v14),
            .iOS(.v17)
        ],
        dependencies: [
            .package(path: "\(escapedRepoPath)")
        ],
        targets: [
            .executableTarget(
                name: "FeatureA",
                dependencies: [
                    .product(name: "InnoDI", package: "\(dependencyPackageIdentity)")
                ],
                plugins: [
                    .plugin(name: "InnoDIDAGValidationPlugin", package: "\(dependencyPackageIdentity)")
                ]
            ),
            .executableTarget(
                name: "FeatureB",
                dependencies: [
                    .product(name: "InnoDI", package: "\(dependencyPackageIdentity)")
                ],
                plugins: [
                    .plugin(name: "InnoDIDAGValidationPlugin", package: "\(dependencyPackageIdentity)")
                ]
            )
        ]
    )
    """

    try manifest.write(
        to: rootURL.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8
    )
    try multiTargetFeatureSource(containerName: "FeatureAContainer").write(
        to: featureAURL.appendingPathComponent("main.swift"),
        atomically: true,
        encoding: .utf8
    )
    try multiTargetFeatureSource(containerName: "FeatureBContainer").write(
        to: featureBURL.appendingPathComponent("main.swift"),
        atomically: true,
        encoding: .utf8
    )

    return rootURL
}

private func multiTargetFeatureSource(containerName: String) -> String {
    """
    import InnoDI

    struct Service: Sendable {}

    @DIContainer
    struct \(containerName) {
        @Provide(.shared, factory: Service())
        var service: Service
    }

    let container = \(containerName)()
    _ = container.service
    """
}

func packageRootURL() -> URL {
    if let override = ProcessInfo.processInfo.environment["PACKAGE_ROOT"],
       !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }

    let fileManager = FileManager.default
    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    while candidate.path != candidate.deletingLastPathComponent().path {
        let manifestURL = candidate.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }

    fatalError("Unable to locate Package.swift from \(#filePath).")
}

private func packageIdentityInfo(packageRootURL: URL) -> (escapedRepoPath: String, dependencyPackageIdentity: String) {
    let escapedRepoPath = packageRootURL
        .path(percentEncoded: false)
        .replacingOccurrences(of: "\\", with: "\\\\")
    // Mirror SwiftPM's package-identity normalization (`.git` suffix stripped +
    // lowercased) used by `normalizePackageIdentity` in InnoDIBuildSupport so
    // path-identity CI passes when the checkout directory is `InnoDI.git` or
    // any other case-mixed name.
    var identity = packageRootURL.lastPathComponent.lowercased()
    if identity.hasSuffix(".git") {
        identity.removeLast(".git".count)
    }
    return (escapedRepoPath, identity)
}

// Fresh consumer packages rebuild SwiftSyntax outside the root package's build
// directory. On GitHub's macos-26 runners that cold build can exceed three
// minutes when this suite overlaps other external-consumer suites, even though
// compiler output is still making progress. Keep the timeout below the CI job
// limit while allowing a cold, resource-contended build to finish.
private let strictConcurrencyBuildTimeoutSeconds: TimeInterval = 600
private let strictConcurrencyTerminationGracePeriodSeconds: TimeInterval = 5
private let strictConcurrencyHardKillGracePeriodSeconds: TimeInterval = 2

private func findFiles(named name: String, under rootURL: URL) throws -> [URL] {
    try findFileSystemEntries(named: name, under: rootURL, isDirectory: false)
}

private func findDirectories(named name: String, under rootURL: URL) throws -> [URL] {
    try findFileSystemEntries(named: name, under: rootURL, isDirectory: true)
}

private func findFileSystemEntries(named name: String, under rootURL: URL, isDirectory: Bool) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var matches: [URL] = []
    for case let url as URL in enumerator {
        guard url.lastPathComponent == name else { continue }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == isDirectory {
            matches.append(url)
        }
    }
    return matches.sorted { $0.path < $1.path }
}
