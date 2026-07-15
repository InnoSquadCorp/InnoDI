import Testing
import SwiftUI

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
    @Provide(.input) var greetingService: any TestGreetingServiceProtocol
    @Provide(.input) var activityService: any TestActivityServiceProtocol
}

@DIEnvironmentBridge([
    (member: "greetingService", environment: \EnvironmentValues.testGreetingService),
    (member: "activityService", environment: \EnvironmentValues.testActivityService),
])
@DIContainer
struct SharedFeatureContainer {
    @Provide(.input) var username: String
    @Provide(.input) var greetingService: any TestGreetingServiceProtocol
    @Provide(.input) var activityService: any TestActivityServiceProtocol
    @Provide(.shared, factory: UUID())
    var token: UUID
}

@DIEnvironmentBridge([
    (member: "greetingService", environment: \EnvironmentValues.testGreetingService),
    (member: "activityService", environment: \EnvironmentValues.testActivityService),
])
@DIContainer
struct TransientFeatureContainer {
    @Provide(.input) var username: String
    @Provide(.input) var greetingService: any TestGreetingServiceProtocol
    @Provide(.input) var activityService: any TestActivityServiceProtocol
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
    @Provide(.input) var username: MutableUsername
}

@DIContainer
struct MutableParentContainer {
    @Provide(.input) var username: MutableUsername

    @SubContainer(
        scope: .transient,
        with: [\MutableParentContainer.username]
    )
    var transientFeature: MutableTransientFeatureContainer
}

@DIContainer
struct ParentContainer {
    @Provide(.input) var username: String
    @Provide(.input) var greetingService: any TestGreetingServiceProtocol
    @Provide(.input) var activityService: any TestActivityServiceProtocol

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
