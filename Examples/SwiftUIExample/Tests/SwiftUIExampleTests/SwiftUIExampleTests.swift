import Testing

@testable import SwiftUIExample

@Suite("SwiftUIExample behavior")
struct SwiftUIExampleTests {
    @Test("Dashboard model loads success state")
    @MainActor
    func dashboardModelLoadsSuccessState() async throws {
        let model = DashboardFeatureModel()

        await model.load(
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

        await model.load(
            username: "Tester",
            greetingService: FailingGreetingService(),
            activityService: MockActivityService(highlights: [])
        )

        guard case let .failed(message) = model.state else {
            Issue.record("Expected failure state.")
            return
        }
        #expect(message.contains("offline"))

        await model.load(
            username: "Tester",
            greetingService: MockGreetingService(
                headline: "Recovered",
                status: "Retry uses the same root composition."
            ),
            activityService: MockActivityService(
                highlights: [ActivityHighlight(id: "retry", title: "Retry", detail: "Recovered after retry.")]
            )
        )

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

        let task = Task {
            await model.load(
                username: "Tester",
                greetingService: LiveGreetingService(),
                activityService: LiveActivityService()
            )
        }
        await Task.yield()
        task.cancel()
        _ = await task.result
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
        let dashboardRootView: Any = live.container.dashboardRootView()
        let dashboardShellView: Any = live.container.dashboardShellRootView()

        #expect(live.title == "Live")
        #expect(live.container.greetingService is LiveGreetingService)
        #expect(preview.container.greetingService is MockGreetingService)
        #expect(failure.container.greetingService is FailingGreetingService)
        #expect(live.container.activityService is LiveActivityService)
        #expect(dashboardRootView is DashboardFeatureRootView)
        #expect(dashboardShellView is DashboardShellView)
    }
}
