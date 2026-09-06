import Testing
import SwiftUI
#if os(macOS)
import AppKit
#endif

@testable import InnoDISwiftUI

protocol TestGreetingServiceProtocol: Sendable {}
protocol TestActivityServiceProtocol: Sendable {}

struct TestGreetingService: TestGreetingServiceProtocol {}
struct TestActivityService: TestActivityServiceProtocol {}

struct TestGreetingServiceKey: EnvironmentKey {
    static let defaultValue: any TestGreetingServiceProtocol = TestGreetingService()
}

struct TestActivityServiceKey: EnvironmentKey {
    static let defaultValue: any TestActivityServiceProtocol = TestActivityService()
}

extension EnvironmentValues {
    var testGreetingService: any TestGreetingServiceProtocol {
        get { self[TestGreetingServiceKey.self] }
        set { self[TestGreetingServiceKey.self] = newValue }
    }

    var testActivityService: any TestActivityServiceProtocol {
        get { self[TestActivityServiceKey.self] }
        set { self[TestActivityServiceKey.self] = newValue }
    }
}

@DIEnvironmentBridge([
    (member: "greetingService", environment: \EnvironmentValues.testGreetingService),
    (member: "activityService", environment: \EnvironmentValues.testActivityService),
])
@DIContainer
struct BridgeOnlyContainer {
    @Input var greetingService: any TestGreetingServiceProtocol
    @Input var activityService: any TestActivityServiceProtocol
}

@DIEnvironmentBridge([
    (member: "greetingService", environment: \EnvironmentValues.testGreetingService),
    (member: "activityService", environment: \EnvironmentValues.testActivityService),
])
@DIContainer
struct SharedFeatureContainer {
    @Input var username: String
    @Input var greetingService: any TestGreetingServiceProtocol
    @Input var activityService: any TestActivityServiceProtocol
    @Provide(.shared, factory: UUID())
    var token: UUID
}

@DIEnvironmentBridge([
    (member: "greetingService", environment: \EnvironmentValues.testGreetingService),
    (member: "activityService", environment: \EnvironmentValues.testActivityService),
])
@DIContainer
struct TransientFeatureContainer {
    @Input var username: String
    @Input var greetingService: any TestGreetingServiceProtocol
    @Input var activityService: any TestActivityServiceProtocol
    @Provide(.shared, factory: UUID())
    var token: UUID
}

struct SharedFeatureRootView: View {
    let container: SharedFeatureContainer

    var body: some View {
        Text(container.username)
            .innodi(container)
    }
}

struct SharedFeatureShellView: View {
    let container: SharedFeatureContainer

    var body: some View {
        SharedFeatureRootView(container: container)
    }
}

struct TransientFeatureRootView: View {
    let container: TransientFeatureContainer

    var body: some View {
        Text(container.username)
            .innodi(container)
    }
}

final class MutableUsername: @unchecked Sendable {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@DIContainer
struct MutableTransientFeatureContainer {
    @Input var username: MutableUsername
}

@DIContainer
struct MutableParentContainer {
    @Input var username: MutableUsername

    @SubContainer(
        scope: .transient,
        with: [\MutableParentContainer.username]
    )
    var transientFeature: MutableTransientFeatureContainer
}

@DIContainer
struct ParentContainer {
    @Input var username: String
    @Input var greetingService: any TestGreetingServiceProtocol
    @Input var activityService: any TestActivityServiceProtocol

    @SubContainer(
        scope: .shared,
        with: [\ParentContainer.username, \ParentContainer.greetingService, \ParentContainer.activityService],
        featureRoots: [
            FeatureRoot(SharedFeatureRootView.self),
            FeatureRoot(SharedFeatureShellView.self, as: "sharedFeatureShell")
        ]
    )
    var sharedFeature: SharedFeatureContainer

    @SubContainer(
        scope: .transient,
        with: [\ParentContainer.username, \ParentContainer.greetingService, \ParentContainer.activityService],
        featureRoot: TransientFeatureRootView.self
    )
    var transientFeature: TransientFeatureContainer
}

@Suite("InnoDISwiftUI integration")
struct InnoDISwiftUITests {
    @Test("innodi aliases share the same generated bridge type")
    @MainActor
    func innodiAliasesShareGeneratedBridgeType() {
        let container = BridgeOnlyContainer(
            greetingService: TestGreetingService(),
            activityService: TestActivityService()
        )

        let implicit = Text("hello").innodi(container)
        let explicit = Text("hello").innodiServices(from: container)

        #expect(String(reflecting: type(of: implicit)) == String(reflecting: type(of: explicit)))
    }

    @Test("shared feature helpers reuse the same child container")
    func sharedFeatureHelpersReuseStableChild() {
        let parent = ParentContainer(
            username: "Shared",
            greetingService: TestGreetingService(),
            activityService: TestActivityService()
        )

        let firstRoot = parent.sharedFeatureRootView()
        let secondRoot = parent.sharedFeatureRootView()
        let shellRoot = parent.sharedFeatureShellRootView()

        #expect(firstRoot.container.token == secondRoot.container.token)
        #expect(firstRoot.container.token == shellRoot.container.token)
        #expect(firstRoot.container.username == "Shared")
    }

    @Test("transient feature helpers build a fresh child container")
    func transientFeatureHelpersBuildFreshChildren() {
        let parent = ParentContainer(
            username: "Transient",
            greetingService: TestGreetingService(),
            activityService: TestActivityService()
        )

        let first = parent.transientFeatureRootView().container.token
        let second = parent.transientFeatureRootView().container.token

        #expect(first != second)
    }

    @Test("environment-bridge containers conform to DIEnvironmentBridging")
    @MainActor
    func bridgeOnlyContainerConformsToBridging() {
        let container = BridgeOnlyContainer(
            greetingService: TestGreetingService(),
            activityService: TestActivityService()
        )
        let bridging: any DIEnvironmentBridging = container
        // Compiler-checkable contract: the synthesized helper exists on the
        // protocol witness and the conformance does not require any
        // additional ceremony at the call site.
        let modifier = bridging._innoDIEnvironmentBridgeModifier()
        #expect(String(reflecting: type(of: modifier)).contains("_InnoDIEnvironmentBridgeModifier"))
    }

    @Test("innodi modifier exposes application order in its generic type shape")
    @MainActor
    func innodiModifierApplicationOrderIsVisibleInTypeShape() {
        let container = BridgeOnlyContainer(
            greetingService: TestGreetingService(),
            activityService: TestActivityService()
        )

        let leadingApply = Text("hello")
            .innodi(container)
            .padding()
        let trailingApply = Text("hello")
            .padding()
            .innodi(container)

        // SwiftUI's ModifiedContent type shape includes modifier order. The
        // contract here is that both orders compile and retain the generated
        // InnoDI bridge modifier somewhere in the resulting type signature.
        let leadingType = String(reflecting: type(of: leadingApply))
        let trailingType = String(reflecting: type(of: trailingApply))
        #expect(
            leadingType != trailingType
        )
        #expect(leadingType.contains("_InnoDIEnvironmentBridgeModifier"))
        #expect(trailingType.contains("_InnoDIEnvironmentBridgeModifier"))
    }

    @Test("shared sub-container helper preserves parent input identity across reads")
    func sharedSubContainerPreservesParentInputs() {
        let parent = ParentContainer(
            username: "Identity",
            greetingService: TestGreetingService(),
            activityService: TestActivityService()
        )

        let firstUsername = parent.sharedFeatureRootView().container.username
        let secondUsername = parent.sharedFeatureShellRootView().container.username

        #expect(firstUsername == "Identity")
        #expect(secondUsername == "Identity")
    }

    @Test("transient sub-container helper forwards the latest parent inputs each read")
    func transientSubContainerForwardsLiveParentInputs() {
        let username = MutableUsername("First")
        let parent = MutableParentContainer(username: username)

        // The transient builder closure captures the parent storage by
        // reference; each fresh build sees the parent member values that
        // exist at read time. This regression test pins down the same-name
        // forwarding contract that with: [\\.username, ...] expands to.
        let snapshotA = parent.transientFeature.username.value
        username.value = "Second"
        let snapshotB = parent.transientFeature.username.value

        #expect(snapshotA == "First")
        #expect(snapshotB == "Second")
    }

    @Test("shared sub-container token survives a child override closure on unrelated child storage")
    func sharedSubContainerSurvivesChildOverrideClosure() {
        let parent = ParentContainer(
            username: "Stable",
            greetingService: TestGreetingService(),
            activityService: TestActivityService()
        ) { overrides in
            // The child override closure runs against the child's nested
            // Overrides builder. We do not mutate the cached child slot
            // itself, so the same shared instance must surface from both
            // helper paths.
            overrides.sharedFeatureOverrides = { _ in }
        }

        let firstToken = parent.sharedFeatureRootView().container.token
        let secondToken = parent.sharedFeatureShellRootView().container.token
        #expect(firstToken == secondToken)
    }
}

private actor HostLifecycleProbe {
    private var creations: [Int: Int] = [:]
    private var closures: [Int: Int] = [:]
    private var cancellations = 0

    func created(_ identity: Int) {
        creations[identity, default: 0] += 1
    }

    func closed(_ identity: Int) {
        closures[identity, default: 0] += 1
    }

    func cancelled() {
        cancellations += 1
    }

    func snapshot() -> (creations: [Int: Int], closures: [Int: Int], cancellations: Int) {
        (creations, closures, cancellations)
    }
}

private final class HostedContainer: @unchecked Sendable {
    let identity: Int

    init(identity: Int) {
        self.identity = identity
    }
}

private enum HostFailure: Error {
    case expected
}

private actor HostFactoryGate {
    private var released: Set<Int> = []
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func wait(for identity: Int) async {
        if released.contains(identity) { return }
        await withCheckedContinuation { continuation in
            waiters[identity, default: []].append(continuation)
        }
    }

    func release(_ identity: Int) {
        released.insert(identity)
        let continuations = waiters.removeValue(forKey: identity) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor HostCloseGate {
    private var started: Set<Int> = []
    private var released: Set<Int> = []
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func close(_ identity: Int) async {
        started.insert(identity)
        if released.contains(identity) { return }
        await withCheckedContinuation { continuation in
            waiters[identity, default: []].append(continuation)
        }
    }

    func hasStarted(_ identity: Int) -> Bool {
        started.contains(identity)
    }

    func release(_ identity: Int) {
        released.insert(identity)
        let continuations = waiters.removeValue(forKey: identity) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

@MainActor
private final class HostViewProbe {
    var failureHandle: DIContainerHostHandle?
    var readyHandle: DIContainerHostHandle?
}

@Suite("DIContainerHost lifecycle")
@MainActor
struct DIContainerHostLifecycleTests {
    @Test("lifecycle handle forwards explicit close and retry operations")
    func lifecycleHandleForwardsOperations() async {
        var closeCount = 0
        var retryCount = 0
        let handle = DIContainerHostHandle(
            close: { closeCount += 1 },
            retry: { retryCount += 1 }
        )

        await handle.close()
        handle.retry()

        #expect(closeCount == 1)
        #expect(retryCount == 1)
    }

    @Test("retry outside a failed phase is a no-op")
    func retryOutsideFailureIsNoOp() {
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        owner.retry()

        if case .idle = owner.phase {
            // Expected.
        } else {
            Issue.record("retry must preserve idle state")
        }
    }

    @Test("owner construction and repeated redraw starts stay lazy and single generation")
    func lazyConstructionAndRedrawReuse() async throws {
        let probe = HostLifecycleProbe()
        let owner = DIContainerHostOwner<Int, HostedContainer>()

        #expect(await probe.snapshot().creations.isEmpty)

        for _ in 0..<100 {
            owner.start(identity: 1) { identity in
                await probe.created(identity)
                return HostedContainer(identity: identity)
            }
        }

        try await waitUntilReady(owner, identity: 1)
        #expect(await probe.snapshot().creations == [1: 1])
    }

    @Test("identity replacement closes the old generation before publishing the new one")
    func identityReplacementClosesOldGeneration() async throws {
        let probe = HostLifecycleProbe()
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        let factory: DIContainerHostOwner<Int, HostedContainer>.Factory = { identity in
            await probe.created(identity)
            return HostedContainer(identity: identity)
        }
        let close: DIContainerHostOwner<Int, HostedContainer>.Close = { container in
            await probe.closed(container.identity)
        }

        owner.start(identity: 1, factory: factory, close: close)
        try await waitUntilReady(owner, identity: 1)
        owner.start(identity: 2, factory: factory, close: close)
        try await waitUntilReady(owner, identity: 2)

        let snapshot = await probe.snapshot()
        #expect(snapshot.creations == [1: 1, 2: 1])
        #expect(snapshot.closures == [1: 1])
    }

    @Test("A→B→C replacement shares the cleanup barrier and preserves A's callback")
    func rapidReplacementWaitsForOriginalGenerationCleanup() async throws {
        let probe = HostLifecycleProbe()
        let gate = HostCloseGate()
        let owner = DIContainerHostOwner<Int, HostedContainer>()

        owner.start(
            identity: 1,
            factory: { identity in
                await probe.created(identity)
                return HostedContainer(identity: identity)
            },
            close: { container in
                await probe.closed(100 + container.identity)
                await gate.close(container.identity)
            }
        )
        try await waitUntilReady(owner, identity: 1)

        owner.start(
            identity: 2,
            factory: { identity in
                await probe.created(identity)
                return HostedContainer(identity: identity)
            },
            close: { container in
                await probe.closed(200 + container.identity)
            }
        )
        try await waitUntil { await gate.hasStarted(1) }
        owner.start(
            identity: 3,
            factory: { identity in
                await probe.created(identity)
                return HostedContainer(identity: identity)
            },
            close: { container in
                await probe.closed(300 + container.identity)
            }
        )

        for _ in 0..<100 { await Task.yield() }
        if case let .loading(identity) = owner.phase {
            #expect(identity == 3)
        } else {
            Issue.record("The newest generation must remain loading while A cleanup is blocked")
        }
        #expect(await probe.snapshot().creations == [1: 1])

        await gate.release(1)
        try await waitUntilReady(owner, identity: 3)
        let snapshot = await probe.snapshot()
        #expect(snapshot.creations == [1: 1, 3: 1])
        #expect(snapshot.closures == [101: 1])
    }

    @Test("same payload can back independent window owners")
    func independentSamePayloadWindows() async throws {
        let probe = HostLifecycleProbe()
        let first = DIContainerHostOwner<Int, HostedContainer>()
        let second = DIContainerHostOwner<Int, HostedContainer>()
        let factory: DIContainerHostOwner<Int, HostedContainer>.Factory = { identity in
            await probe.created(identity)
            return HostedContainer(identity: identity)
        }

        first.start(identity: 7, factory: factory)
        second.start(identity: 7, factory: factory)
        try await waitUntilReady(first, identity: 7)
        try await waitUntilReady(second, identity: 7)

        #expect(await probe.snapshot().creations == [7: 2])
    }

    @Test("explicit close is idempotent and permits reentry")
    func closeAndReentry() async throws {
        let probe = HostLifecycleProbe()
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        let factory: DIContainerHostOwner<Int, HostedContainer>.Factory = { identity in
            await probe.created(identity)
            return HostedContainer(identity: identity)
        }
        let close: DIContainerHostOwner<Int, HostedContainer>.Close = { container in
            await probe.closed(container.identity)
        }

        owner.start(identity: 3, factory: factory, close: close)
        try await waitUntilReady(owner, identity: 3)
        await owner.close()
        await owner.close()
        owner.start(identity: 3, factory: factory, close: close)
        try await waitUntilReady(owner, identity: 3)

        let snapshot = await probe.snapshot()
        #expect(snapshot.creations == [3: 2])
        #expect(snapshot.closures == [3: 1])
    }

    @Test("explicit close releases the owned container")
    func closeReleasesContainer() async throws {
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        owner.start(identity: 5) { HostedContainer(identity: $0) }
        try await waitUntilReady(owner, identity: 5)

        weak var weakContainer: HostedContainer?
        if case let .ready(_, container) = owner.phase {
            weakContainer = container
        }
        #expect(weakContainer != nil)

        await owner.close()
        #expect(weakContainer == nil)
    }

    @Test("failure can retry in a clean generation")
    func failureRetry() async throws {
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        var attempts = 0

        owner.start(identity: 9) { identity in
            attempts += 1
            if attempts == 1 { throw HostFailure.expected }
            return HostedContainer(identity: identity)
        }
        try await waitUntilFailed(owner, identity: 9)
        owner.retry()
        try await waitUntilReady(owner, identity: 9)
        #expect(attempts == 2)
    }

    @Test("identity transition cancels an in-flight generation")
    func transitionCancellation() async throws {
        let probe = HostLifecycleProbe()
        let owner = DIContainerHostOwner<Int, HostedContainer>()

        owner.start(identity: 1) { identity in
            do {
                try await Task.sleep(for: .seconds(30))
                return HostedContainer(identity: identity)
            } catch is CancellationError {
                await probe.cancelled()
                throw CancellationError()
            }
        }
        await Task.yield()
        owner.start(identity: 2) { identity in
            await probe.created(identity)
            return HostedContainer(identity: identity)
        }
        try await waitUntilReady(owner, identity: 2)

        let snapshot = await probe.snapshot()
        #expect(snapshot.cancellations == 1)
        #expect(snapshot.creations == [2: 1])
    }

    @Test("a current generation cancellation returns the owner to idle")
    func currentGenerationCancellationReturnsToIdle() async throws {
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        owner.start(identity: 11) { _ in throw CancellationError() }

        try await waitUntil {
            if case .idle = owner.phase { return true }
            return false
        }
    }

    @Test("a cancelled factory candidate is closed instead of being published")
    func cancelledCandidateIsClosed() async throws {
        let gate = HostFactoryGate()
        let probe = HostLifecycleProbe()
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        let close: DIContainerHostOwner<Int, HostedContainer>.Close = { container in
            await probe.closed(container.identity)
        }

        owner.start(
            identity: 12,
            factory: { identity in
                await gate.wait(for: identity)
                return HostedContainer(identity: identity)
            },
            close: close
        )
        await Task.yield()
        owner.start(
            identity: 13,
            factory: { HostedContainer(identity: $0) },
            close: close
        )
        await gate.release(12)
        try await waitUntilReady(owner, identity: 13)
        try await waitUntil { await probe.snapshot().closures[12] == 1 }

        #expect(await probe.snapshot().closures == [12: 1])
    }

    @Test("A late cancelled candidate uses the callback captured by its own generation")
    func cancelledCandidateUsesGenerationCloseCallback() async throws {
        let gate = HostFactoryGate()
        let probe = HostLifecycleProbe()
        let owner = DIContainerHostOwner<Int, HostedContainer>()

        owner.start(
            identity: 21,
            factory: { identity in
                await gate.wait(for: identity)
                return HostedContainer(identity: identity)
            },
            close: { container in
                await probe.closed(100 + container.identity)
            }
        )
        await Task.yield()
        owner.start(
            identity: 22,
            factory: { HostedContainer(identity: $0) },
            close: { container in
                await probe.closed(200 + container.identity)
            }
        )

        await gate.release(21)
        try await waitUntilReady(owner, identity: 22)
        try await waitUntil { await probe.snapshot().closures[121] == 1 }
        #expect(await probe.snapshot().closures == [121: 1])
    }

    @Test("Concurrent explicit close calls share one cleanup and close exactly once")
    func concurrentCloseIsExactlyOnce() async throws {
        let probe = HostLifecycleProbe()
        let gate = HostCloseGate()
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        owner.start(
            identity: 31,
            factory: { HostedContainer(identity: $0) },
            close: { container in
                await probe.closed(container.identity)
                await gate.close(container.identity)
            }
        )
        try await waitUntilReady(owner, identity: 31)

        let first = Task { @MainActor in await owner.close() }
        try await waitUntil { await gate.hasStarted(31) }
        let second = Task { @MainActor in await owner.close() }
        await gate.release(31)
        await first.value
        await second.value

        #expect(await probe.snapshot().closures == [31: 1])
        if case .idle = owner.phase {
            // Expected.
        } else {
            Issue.record("Concurrent close must leave the owner idle")
        }
    }

    @Test("starting the same failed identity creates a fresh generation")
    func sameFailedIdentityCanRestart() async throws {
        let owner = DIContainerHostOwner<Int, HostedContainer>()
        var attempts = 0
        let factory: DIContainerHostOwner<Int, HostedContainer>.Factory = { identity in
            attempts += 1
            if attempts == 1 { throw HostFailure.expected }
            return HostedContainer(identity: identity)
        }

        owner.start(identity: 14, factory: factory)
        try await waitUntilFailed(owner, identity: 14)
        owner.start(identity: 14, factory: factory)
        try await waitUntilReady(owner, identity: 14)

        #expect(attempts == 2)
    }

    #if os(macOS)
    @Test("mounted failure UI can retry and explicitly close the recovered container")
    func mountedFailureRetryAndClose() async throws {
        let probe = HostViewProbe()
        var attempts = 0
        let view = DIContainerHost(
            identity: 15,
            factory: { identity in
                attempts += 1
                if attempts == 1 { throw HostFailure.expected }
                return HostedContainer(identity: identity)
            },
            content: { container, handle in
                probe.readyHandle = handle
                return Text("ready-\(container.identity)")
            },
            loading: { ProgressView() },
            failure: { _, handle in
                probe.failureHandle = handle
                return Text("failed")
            }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        hostingView.layoutSubtreeIfNeeded()

        try await waitUntil { probe.failureHandle != nil }
        probe.failureHandle?.retry()
        try await waitUntil { probe.readyHandle != nil }
        await probe.readyHandle?.close()

        #expect(attempts == 2)
        _ = hostingView
    }

    @Test("a mounted SwiftUI host survives one hundred root redraws without recreating")
    func mountedHostRedrawStress() async throws {
        let probe = HostLifecycleProbe()
        let view = DIContainerHost(
            identity: 42,
            factory: { identity in
                await probe.created(identity)
                return HostedContainer(identity: identity)
            },
            content: { container, _ in Text("ready-\(container.identity)") },
            loading: { ProgressView() },
            failure: { _, _ in Text("failed") }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)

        for _ in 0..<100 {
            hostingView.rootView = view
            hostingView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(1))
        }

        try await waitUntil { await probe.snapshot().creations[42] == 1 }
        #expect(await probe.snapshot().creations == [42: 1])
        _ = hostingView
    }
    #endif

    private func waitUntilReady(
        _ owner: DIContainerHostOwner<Int, HostedContainer>,
        identity: Int
    ) async throws {
        try await waitUntil {
            if case let .ready(actualIdentity, _) = owner.phase {
                return actualIdentity == identity
            }
            return false
        }
    }

    private func waitUntilFailed(
        _ owner: DIContainerHostOwner<Int, HostedContainer>,
        identity: Int
    ) async throws {
        try await waitUntil {
            if case let .failed(actualIdentity, _) = owner.phase {
                return actualIdentity == identity
            }
            return false
        }
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            guard clock.now < deadline else { throw HostFailure.expected }
            await Task.yield()
        }
    }
}
