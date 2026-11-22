import InnoDISwiftUI
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#endif

// Hosted feature roots on `.shared` and `.transient` children. A `.shared`
// child belongs to the parent, so its hosted overload presents that one
// instance for every identity and never hands it to a close hook. A
// `.transient` child is host-owned: one child per identity, created after
// mount and closed when the next identity replaces it.

@MainActor
private final class HostedScopeProbe {
    var creations = 0
    var appearedTokens: [Int] = []
    var closedTokens: [Int] = []

    func makeToken() -> Int {
        creations += 1
        return creations
    }
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
fileprivate struct HostedScopeChild {
    @Input var probe: HostedScopeProbe

    @Provide(.shared, factory: { (probe: HostedScopeProbe) in probe.makeToken() })
    var token: Int
}

@MainActor
private struct HostedScopeRootView: View {
    let container: HostedScopeChild

    var body: some View {
        Text("token-\(container.token)")
            .onAppear { container.probe.appearedTokens.append(container.token) }
    }
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
fileprivate struct HostedSharedScopeParent {
    @Input var probe: HostedScopeProbe

    @SubContainer(
        scope: .shared,
        with: [\Self.probe],
        featureRoots: [FeatureRoot(HostedScopeRootView.self, hosted: true)]
    )
    var child: HostedScopeChild
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
fileprivate struct HostedTransientScopeParent {
    @Input var probe: HostedScopeProbe

    @SubContainer(
        scope: .transient,
        with: [\Self.probe],
        featureRoots: [FeatureRoot(HostedScopeRootView.self, hosted: true)]
    )
    var child: HostedScopeChild
}

// The 7.0 close overload of a `.shared` child stays callable, unchanged, and
// deprecated. Swift Testing marks its own thunks deprecated, so this
// deprecated test may call it without a warning.
@available(*, deprecated, message: "Pins the deprecated close overload of a hosted .shared child.")
@MainActor
private func sharedRootWithDeprecatedClose(
    _ parent: HostedSharedScopeParent,
    identity: Int,
    close: @escaping DIContainerHostOwner<Int, HostedScopeChild>.Close
) -> some View {
    parent.childRootView(identity: identity, close: close)
}

@MainActor
private final class HostIdentityRecorder {
    var contentPairs: [String] = []
    var failurePairs: [String] = []
}

private final class IdentityContainer: Sendable {
    let identity: Int

    init(identity: Int) {
        self.identity = identity
    }
}

private enum IdentityFailure: Error {
    case expected
}

private struct EnvironmentOrderKey: EnvironmentKey {
    static let defaultValue = "default"
}

extension EnvironmentValues {
    fileprivate var hostedScopeOrderValue: String {
        get { self[EnvironmentOrderKey.self] }
        set { self[EnvironmentOrderKey.self] = newValue }
    }
}

@MainActor
private final class EnvironmentReadRecorder {
    var values: [String] = []
}

@MainActor
private struct EnvironmentOrderReader: View {
    @Environment(\.hostedScopeOrderValue) private var value
    let recorder: EnvironmentReadRecorder

    var body: some View {
        recorder.values.append(value)
        return Text(value)
    }
}

// Unlabeled mapping tuples type-check against
// `[(member: String, environment: AnyKeyPath)]`; the bridge reads them by
// position instead of silently generating nothing.
@DIEnvironmentBridge([
    ("orderValue", \EnvironmentValues.hostedScopeOrderValue),
])
@DIContainer
fileprivate struct UnlabeledBridgeContainer {
    @Input var orderValue: String
}

@Suite("Hosted feature-root scopes and host identity")
@MainActor
struct HostedFeatureRootScopeTests {
    @Test("Unlabeled bridge tuples generate the conformance")
    func unlabeledBridgeTuplesConform() {
        let container = UnlabeledBridgeContainer(orderValue: "bridged")
        let bridged: any DIEnvironmentBridging = container
        _ = Text("bridged").innodi(container)
        #expect(bridged is UnlabeledBridgeContainer)
    }

    #if os(macOS)
    @Test("A hosted .shared child is the parent's one instance for every identity and is never closed")
    func hostedSharedChildIsPresentedNotOwned() async throws {
        let probe = HostedScopeProbe()
        let parent = HostedSharedScopeParent(probe: probe)
        // Built with the parent, before any helper or mount.
        #expect(probe.creations == 1)

        let hostingView = NSHostingView(rootView: parent.childRootView(identity: 1))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens == [1] }
        for _ in 0..<20 {
            hostingView.rootView = parent.childRootView(identity: 1)
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        hostingView.rootView = parent.childRootView(identity: 2)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens.count == 2 }
        hostingView.rootView = parent.childRootView(identity: 3)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens.count == 3 }

        #expect(probe.creations == 1)
        #expect(probe.appearedTokens == [1, 1, 1])
        #expect(probe.closedTokens.isEmpty)
        #expect(parent.child.token == 1)
        _ = hostingView
    }

    @Test("A hosted .transient child is created after mount, once per identity, and each is closed once")
    func hostedTransientChildIsHostOwned() async throws {
        let probe = HostedScopeProbe()
        let parent = HostedTransientScopeParent(probe: probe)
        let close: DIContainerHostOwner<Int, HostedScopeChild>.Close = { container in
            container.probe.closedTokens.append(container.token)
        }
        let first = parent.childRootView(identity: 1, close: close)
        #expect(probe.creations == 0)

        let hostingView = NSHostingView(rootView: first)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens == [1] }
        for _ in 0..<20 {
            hostingView.rootView = parent.childRootView(identity: 1, close: close)
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        #expect(probe.creations == 1)

        hostingView.rootView = parent.childRootView(identity: 2, close: close)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens == [1, 2] && probe.closedTokens == [1] }
        hostingView.rootView = parent.childRootView(identity: 3, close: close)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens == [1, 2, 3] && probe.closedTokens == [1, 2] }

        #expect(probe.creations == 3)
        _ = hostingView
    }

    @available(*, deprecated, message: "Calls the deprecated close overload of a hosted .shared child.")
    @Test("The deprecated .shared close overload keeps its 7.0 behavior")
    func deprecatedSharedCloseOverloadIsUnchanged() async throws {
        let probe = HostedScopeProbe()
        let parent = HostedSharedScopeParent(probe: probe)
        let close: DIContainerHostOwner<Int, HostedScopeChild>.Close = { container in
            container.probe.closedTokens.append(container.token)
        }
        let hostingView = NSHostingView(
            rootView: AnyView(sharedRootWithDeprecatedClose(parent, identity: 1, close: close))
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens == [1] }

        hostingView.rootView = AnyView(sharedRootWithDeprecatedClose(parent, identity: 2, close: close))
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { probe.appearedTokens == [1, 1] && probe.closedTokens == [1] }

        // The hook received the parent's instance, which the parent still
        // serves: the reason this overload is deprecated.
        #expect(probe.creations == 1)
        #expect(parent.child.token == 1)
        _ = hostingView
    }

    @Test("Content and failure never receive the previous identity's container or error")
    func hostBodyMatchesPhaseIdentity() async throws {
        let recorder = HostIdentityRecorder()
        func makeHost(_ identity: Int) -> some View {
            DIContainerHost(
                identity: identity,
                factory: { identity in
                    if identity == 3 { throw IdentityFailure.expected }
                    return IdentityContainer(identity: identity)
                },
                content: { container, _ in
                    recorder.contentPairs.append("host=\(identity)/container=\(container.identity)")
                    return Text("ready-\(container.identity)")
                },
                loading: { Text("loading") },
                failure: { _, _ in
                    recorder.failurePairs.append("host=\(identity)")
                    return Text("failed")
                }
            )
        }

        let hostingView = NSHostingView(rootView: AnyView(makeHost(1)))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { recorder.contentPairs.contains("host=1/container=1") }

        hostingView.rootView = AnyView(makeHost(3))
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { recorder.failurePairs.contains("host=3") }

        hostingView.rootView = AnyView(makeHost(2))
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { recorder.contentPairs.contains("host=2/container=2") }

        // Control: each identity reached its own ready or failed phase.
        #expect(Set(recorder.contentPairs) == ["host=1/container=1", "host=2/container=2"])
        #expect(Set(recorder.failurePairs) == ["host=3"])
        _ = hostingView
    }

    @Test("The first of two chained environment values for one key is the one views read")
    func chainedEnvironmentValuesKeepTheInnermost() async throws {
        // `@DIEnvironmentBridge` applies mappings in declaration order, as
        // `content.environment(k, first).environment(k, second)`. This pins
        // the SwiftUI rule that `environment-bridge-duplicate-environment`
        // states: views under the bridge read `first`.
        let recorder = EnvironmentReadRecorder()
        let hostingView = NSHostingView(
            rootView: EnvironmentOrderReader(recorder: recorder)
                .environment(\.hostedScopeOrderValue, "first")
                .environment(\.hostedScopeOrderValue, "second")
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { !recorder.values.isEmpty }
        #expect(Set(recorder.values) == ["first"])
        _ = hostingView
    }

    @Test("Unlabeled bridge tuples forward the mapped member into the environment")
    func unlabeledBridgeTuplesForwardValues() async throws {
        let recorder = EnvironmentReadRecorder()
        let container = UnlabeledBridgeContainer(orderValue: "bridged")
        let hostingView = NSHostingView(
            rootView: EnvironmentOrderReader(recorder: recorder).innodi(container)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        try await waitUntil { !recorder.values.isEmpty }
        #expect(Set(recorder.values) == ["bridged"])
        _ = hostingView
    }
    #endif

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw IdentityFailure.expected
    }
}
