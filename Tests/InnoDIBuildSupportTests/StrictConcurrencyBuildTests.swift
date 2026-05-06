import Foundation
import Dispatch
import Darwin
import Testing
import InnoDITestSupport

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
                @Provide(.shared, asyncFactory: { () async in Service() }, concrete: true)
                var service: Service
            }

            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, factory: { Service() }, concrete: true)
                var service: Service

                @Provide(.shared, factory: { (service: InnoDI.Lazy<Service>) in
                    LazyHolder(lazy: service)
                }, concrete: true)
                var lazyHolder: LazyHolder

                @Provide(.shared, factory: { (service: InnoDI.Provider<Service>) in
                    ProviderHolder(provider: service)
                }, concrete: true)
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
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.shared, factory: Greeting(), concrete: true)
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

            @main
            struct FixtureApp {
                static func main() async throws {
                    let api = APIMock()
                    api.fetchIdStringReturnValue = "id"
                    api.fetchPageIntReturnValue = "page"
                    _ = api.fetch(id: "42")
                    _ = api.fetch(page: 1)

                    let generic = GenericAPIMock()
                    generic.makeUnlabeledTTypeHandler = { _ in "made" }
                    generic.failUnlabeledTTypeHandler = { _ in "failed" }
                    generic.waitUnlabeledTTypeHandler = { _ in "waited" }
                    generic.loadUnlabeledTTypeHandler = { _ in "loaded" }

                    let _: String = generic.make(String.self)
                    let _: String = try generic.fail(String.self)
                    let _: String = await generic.wait(String.self)
                    let _: String = try await generic.load(String.self)

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
                @Provide(.shared, factory: Service(), concrete: true)
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

    @Test("Timeout path avoids blocking on descendants that keep pipes open")
    func timeoutPathAvoidsBlockingPipeDrain() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "trap '' TERM; sleep 5 & echo started; wait"
        ]
        process.currentDirectoryURL = packageRootURL()

        let result = try runCapturedProcess(
            process,
            timeoutSeconds: 1.0,
            terminationGraceSeconds: 0.5,
            hardKillGraceSeconds: 0.5
        )

        #expect(result.timedOut)
        #expect(result.stdout.contains("started"))
    }
}

private struct StrictConcurrencyBuildResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

private final class StrictConcurrencyDataSink: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private func runStrictConcurrencyBuild(
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

private func runCapturedProcess(
    _ process: Process,
    timeoutSeconds: TimeInterval,
    terminationGraceSeconds: TimeInterval,
    hardKillGraceSeconds: TimeInterval
) throws -> StrictConcurrencyBuildResult {

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdoutSink = StrictConcurrencyDataSink()
    let stderrSink = StrictConcurrencyDataSink()
    installStrictConcurrencyReadHandler(on: stdoutPipe.fileHandleForReading, sink: stdoutSink)
    installStrictConcurrencyReadHandler(on: stderrPipe.fileHandleForReading, sink: stderrSink)
    let terminationSemaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        terminationSemaphore.signal()
    }

    try process.run()
    let timedOut = !waitForCapturedProcessTermination(
        terminationSemaphore,
        timeoutSeconds: timeoutSeconds
    )
    if timedOut && process.isRunning {
        process.terminate()
        if !waitForCapturedProcessTermination(
            terminationSemaphore,
            timeoutSeconds: terminationGraceSeconds
        ) && process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            _ = waitForCapturedProcessTermination(
                terminationSemaphore,
                timeoutSeconds: hardKillGraceSeconds
            )
        }
    }

    let stdoutHandle = stdoutPipe.fileHandleForReading
    let stderrHandle = stderrPipe.fileHandleForReading
    stdoutHandle.readabilityHandler = nil
    stderrHandle.readabilityHandler = nil
    if !timedOut {
        stdoutSink.append(stdoutHandle.readDataToEndOfFile())
        stderrSink.append(stderrHandle.readDataToEndOfFile())
    }
    stdoutHandle.closeFile()
    stderrHandle.closeFile()

    return StrictConcurrencyBuildResult(
        exitCode: process.isRunning ? Int32(SIGKILL) : process.terminationStatus,
        stdout: String(decoding: stdoutSink.snapshot(), as: UTF8.self),
        stderr: String(decoding: stderrSink.snapshot(), as: UTF8.self),
        timedOut: timedOut
    )
}

private func waitForCapturedProcessTermination(
    _ semaphore: DispatchSemaphore,
    timeoutSeconds: TimeInterval
) -> Bool {
    semaphore.wait(timeout: .now() + timeoutSeconds) == .success
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

    let escapedRepoPath = packageRootURL()
        .path(percentEncoded: false)
        .replacingOccurrences(of: "\\", with: "\\\\")
    // Mirror SwiftPM's package-identity normalization (`.git` suffix stripped +
    // lowercased) used by `normalizePackageIdentity` in InnoDIBuildSupport so
    // path-identity CI passes when the checkout directory is `InnoDI.git` or
    // any other case-mixed name.
    let dependencyPackageIdentity: String = {
        var identity = packageRootURL().lastPathComponent.lowercased()
        if identity.hasSuffix(".git") {
            identity.removeLast(".git".count)
        }
        return identity
    }()

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

private func packageRootURL() -> URL {
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

private let strictConcurrencyBuildTimeoutSeconds: TimeInterval = 180
private let strictConcurrencyTerminationGracePeriodSeconds: TimeInterval = 5
private let strictConcurrencyHardKillGracePeriodSeconds: TimeInterval = 2

private func installStrictConcurrencyReadHandler(
    on handle: FileHandle,
    sink: StrictConcurrencyDataSink
) {
    handle.readabilityHandler = { readableHandle in
        let data = readableHandle.availableData
        if data.isEmpty {
            readableHandle.readabilityHandler = nil
            return
        }
        sink.append(data)
    }
}
