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
    @Provide(.shared, factory: UUID(), concrete: true)
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
    @Provide(.shared, factory: UUID(), concrete: true)
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

@DIContainer
struct ParentContainer {
    @Provide(.input) var username: String
    @Provide(.input) var greetingService: any TestGreetingServiceProtocol
    @Provide(.input) var activityService: any TestActivityServiceProtocol

    // Intentionally uses `withNames:` to keep runtime coverage of that
    // codegen path through 4.x. Phase 3.B (4.2.0) will migrate this
    // fixture as part of the explicit deprecation rollout — see
    // `docs/internal/fatalerror-inventory.md` siblings (Item 3 of the
    // P1 work plan).
    @SubContainer(scope: .shared, withNames: ["username", "greetingService", "activityService"])
    @DIFeatureRoot(SharedFeatureRootView.self)
    @DIFeatureRoot(SharedFeatureShellView.self, as: "sharedFeatureShell")
    var sharedFeature: SharedFeatureContainer

    @SubContainer(scope: .transient, withNames: ["username", "greetingService", "activityService"])
    @DIFeatureRoot(TransientFeatureRootView.self)
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
}
