import Testing

@testable import SwiftUIExample

@Suite("SwiftUIExample behavior")
struct SwiftUIExampleTests {
    @Test("Dashboard model loads success state")
    @MainActor
    func dashboardModelLoadsSuccessState() async throws {
        let model = DashboardFeatureModel()

        model.load(
            username: "Tester",
            greetingService: MockGreetingService(
                headline: "Hello, Tester",
                status: "Feature root loaded."
            ),
            activityService: MockActivityService(
                highlights: [
                    ActivityHighlight(id: "one", title: "Loaded", detail: "Async state completed.")
                ]
            )
        )

        try await waitUntilDashboardLoaded(model)

        guard case let .loaded(content) = model.state else {
            Issue.record("Expected loaded state.")
            return
        }
        #expect(content.summary.headline == "Hello, Tester")
        #expect(content.highlights.count == 1)
    }

    @Test("Dashboard model enters failure state and retries")
    @MainActor
    func dashboardModelFailsAndRetries() async throws {
        let model = DashboardFeatureModel()

        model.load(
            username: "Tester",
            greetingService: FailingGreetingService(),
            activityService: MockActivityService(highlights: [])
        )
        try await waitUntilDashboardFailed(model)

        guard case let .failed(message) = model.state else {
            Issue.record("Expected failure state.")
            return
        }
        #expect(message.contains("offline"))

        model.retry(
            username: "Tester",
            greetingService: MockGreetingService(
                headline: "Recovered",
                status: "Retry uses the same root composition."
            ),
            activityService: MockActivityService(
                highlights: [ActivityHighlight(id: "retry", title: "Retry", detail: "Recovered after retry.")]
            )
        )
        try await waitUntilDashboardLoaded(model)

        guard case let .loaded(content) = model.state else {
            Issue.record("Expected loaded state after retry.")
            return
        }
        #expect(content.summary.headline == "Recovered")
    }

    @Test("Dashboard model cancellation prevents terminal state writes")
    @MainActor
    func dashboardModelCancelPreventsTerminalStateWrites() async throws {
        let model = DashboardFeatureModel()

        model.load(
            username: "Tester",
            greetingService: LiveGreetingService(),
            activityService: LiveActivityService()
        )
        model.cancel()
        try await Task.sleep(for: .milliseconds(250))

        guard case .loading = model.state else {
            Issue.record("Expected loading state to remain after cancellation.")
            return
        }
    }

    @Test("Dashboard root scenarios expose live preview and failure compositions")
    func dashboardRootScenariosExposeCompositionVariants() {
        let live = DashboardRootScenario.live(username: "Live")
        let preview = DashboardRootScenario.preview(username: "Preview")
        let failure = DashboardRootScenario.failure(username: "Failure")

        #expect(live.title == "Live")
        #expect(String(describing: type(of: live.container.greetingService)) == "LiveGreetingService")
        #expect(String(describing: type(of: preview.container.greetingService)) == "MockGreetingService")
        #expect(String(describing: type(of: failure.container.greetingService)) == "FailingGreetingService")
        #expect(String(describing: type(of: live.container.activityService)) == "LiveActivityService")
        #expect(String(describing: type(of: live.container.dashboardRootView())) == "DashboardFeatureRootView")
        #expect(String(describing: type(of: live.container.dashboardShellRootView())) == "DashboardShellView")
    }
}

@MainActor
private func waitUntilDashboardLoaded(_ model: DashboardFeatureModel) async throws {
    for _ in 0..<20 {
        if case .loaded = model.state {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Timed out waiting for loaded state.")
}

@MainActor
private func waitUntilDashboardFailed(_ model: DashboardFeatureModel) async throws {
    for _ in 0..<20 {
        if case .failed = model.state {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Timed out waiting for failed state.")
}
