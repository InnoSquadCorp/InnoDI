import InnoDISwiftUI
import Observation
import SwiftUI

struct DashboardSummary: Sendable {
    let headline: String
    let status: String
}

struct ActivityHighlight: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
}

protocol GreetingServiceProtocol: Sendable {
    func loadSummary(for username: String) async throws -> DashboardSummary
}

protocol ActivityServiceProtocol: Sendable {
    func loadHighlights(for username: String) async throws -> [ActivityHighlight]
}

enum ExampleServiceError: Error, LocalizedError, Sendable {
    case offline

    var errorDescription: String? {
        switch self {
        case .offline:
            return "The live feature root is offline. Retry with a different environment override."
        }
    }
}

struct LiveGreetingService: GreetingServiceProtocol {
    func loadSummary(for username: String) async throws -> DashboardSummary {
        try await Task.sleep(for: .milliseconds(160))
        return DashboardSummary(
            headline: "Hello, \(username)! Your feature root is live.",
            status: "Two environment services are composed before the first screen appears."
        )
    }
}

struct LiveActivityService: ActivityServiceProtocol {
    func loadHighlights(for username: String) async throws -> [ActivityHighlight] {
        try await Task.sleep(for: .milliseconds(120))
        return [
            ActivityHighlight(id: "inject", title: "Inject services", detail: "Both services are provided at the root boundary for \(username)."),
            ActivityHighlight(id: "load", title: "Load asynchronously", detail: "The view-level .task(id:) starts the async load and cancels it when the id changes or the view disappears."),
            ActivityHighlight(id: "navigate", title: "Navigate deeper", detail: "NavigationStack and destination views stay independent of the container.")
        ]
    }
}

struct MockGreetingService: GreetingServiceProtocol {
    let headline: String
    let status: String

    func loadSummary(for username: String) async throws -> DashboardSummary {
        DashboardSummary(headline: headline, status: status)
    }
}

struct MockActivityService: ActivityServiceProtocol {
    let highlights: [ActivityHighlight]

    func loadHighlights(for username: String) async throws -> [ActivityHighlight] {
        highlights
    }
}

struct FailingGreetingService: GreetingServiceProtocol {
    func loadSummary(for username: String) async throws -> DashboardSummary {
        try await Task.sleep(for: .milliseconds(90))
        throw ExampleServiceError.offline
    }
}

private struct GreetingServiceKey: EnvironmentKey {
    static let defaultValue: any GreetingServiceProtocol = MockGreetingService(
        headline: "Missing greeting service",
        status: "Inject a root service through EnvironmentValues.greetingService."
    )
}

private struct ActivityServiceKey: EnvironmentKey {
    static let defaultValue: any ActivityServiceProtocol = MockActivityService(
        highlights: [
            ActivityHighlight(
                id: "missing",
                title: "Missing activity service",
                detail: "Inject a root service through EnvironmentValues.activityService."
            )
        ]
    )
}

extension EnvironmentValues {
    var greetingService: any GreetingServiceProtocol {
        get { self[GreetingServiceKey.self] }
        set { self[GreetingServiceKey.self] = newValue }
    }

    var activityService: any ActivityServiceProtocol {
        get { self[ActivityServiceKey.self] }
        set { self[ActivityServiceKey.self] = newValue }
    }
}

struct DashboardContent: Sendable {
    let summary: DashboardSummary
    let highlights: [ActivityHighlight]
}

enum DashboardLoadState: Sendable {
    case idle
    case loading
    case loaded(DashboardContent)
    case failed(String)
}

@MainActor
@Observable
final class DashboardFeatureModel {
    var navigationTitle = "InnoDI Feature Root"
    var state: DashboardLoadState = .idle

    func load(
        username: String,
        greetingService: any GreetingServiceProtocol,
        activityService: any ActivityServiceProtocol
    ) async {
        state = .loading

        do {
            let content = try await loadContent(
                username: username,
                greetingService: greetingService,
                activityService: activityService
            )
            guard !Task.isCancelled else { return }
            state = .loaded(content)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? "An unknown feature-root error occurred."
            state = .failed(message)
        }
    }

    private func loadContent(
        username: String,
        greetingService: any GreetingServiceProtocol,
        activityService: any ActivityServiceProtocol
    ) async throws -> DashboardContent {
        async let summary = greetingService.loadSummary(for: username)
        async let highlights = activityService.loadHighlights(for: username)
        return DashboardContent(summary: try await summary, highlights: try await highlights)
    }
}

@DIEnvironmentBridge([
    (member: "greetingService", environment: \EnvironmentValues.greetingService),
    (member: "activityService", environment: \EnvironmentValues.activityService),
])
@DIContainer
struct DashboardFeatureContainer {
    @Provide(.input)
    var username: String

    @Provide(.input)
    var greetingService: any GreetingServiceProtocol

    @Provide(.input)
    var activityService: any ActivityServiceProtocol
}

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var username: String

    @Provide(.shared, factory: { LiveGreetingService() })
    var greetingService: any GreetingServiceProtocol

    @Provide(.shared, factory: { LiveActivityService() })
    var activityService: any ActivityServiceProtocol

    @SubContainer(
        scope: .shared,
        withNames: ["username", "greetingService", "activityService"]
    )
    @DIFeatureRoot(DashboardFeatureRootView.self)
    @DIFeatureRoot(DashboardShellView.self, as: "dashboardShell")
    var dashboard: DashboardFeatureContainer
}

struct DashboardSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.quaternary)
                .frame(height: 90)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.7))
                    .frame(height: 58)
            }
        }
        .redacted(reason: .placeholder)
    }
}

struct DashboardErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recoverable error")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct DashboardLoadedView: View {
    let content: DashboardContent

    var body: some View {
        List {
            Section("Summary") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(content.summary.headline)
                        .font(.headline)
                    Text(content.summary.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Highlights") {
                ForEach(content.highlights) { highlight in
                    NavigationLink(value: highlight) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(highlight.title)
                                .font(.body.weight(.semibold))
                            Text(highlight.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.automatic)
    }
}

struct HighlightDetailView: View {
    let highlight: ActivityHighlight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(highlight.title)
                .font(.largeTitle.bold())
            Text(highlight.detail)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Detail")
    }
}

struct DashboardFeatureScreen: View {
    let username: String

    @Environment(\.greetingService) private var greetingService
    @Environment(\.activityService) private var activityService
    @State private var model = DashboardFeatureModel()
    @State private var reloadID: Int = 0

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .idle, .loading:
                    DashboardSkeletonView()
                        .padding(24)
                case let .loaded(content):
                    DashboardLoadedView(content: content)
                case let .failed(message):
                    DashboardErrorView(message: message) {
                        reloadID += 1
                    }
                    .padding(24)
                }
            }
            .navigationTitle(model.navigationTitle)
            .navigationDestination(for: ActivityHighlight.self) { highlight in
                HighlightDetailView(highlight: highlight)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload") {
                        reloadID += 1
                    }
                }
            }
        }
        .task(id: reloadID) {
            await model.load(
                username: username,
                greetingService: greetingService,
                activityService: activityService
            )
        }
    }
}

struct DashboardFeatureRootView: View {
    let container: DashboardFeatureContainer

    var body: some View {
        DashboardFeatureScreen(username: container.username)
            .innodi(container)
    }
}

struct DashboardShellView: View {
    let container: DashboardFeatureContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dashboard Shell")
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            DashboardFeatureRootView(container: container)
        }
        .background(.background)
    }
}

struct DashboardRootScenario {
    let title: String
    let container: AppContainer

    static func live(username: String = "InnoDI") -> Self {
        Self(
            title: "Live",
            container: AppContainer(username: username)
        )
    }

    static func preview(username: String = "Preview") -> Self {
        Self(
            title: "Preview",
            container: AppContainer(
                username: username,
                greetingService: MockGreetingService(
                    headline: "Preview greeting injected at the feature root.",
                    status: "Mock services can override both environment dependencies at the root boundary."
                ),
                activityService: MockActivityService(
                    highlights: [
                        ActivityHighlight(id: "preview-1", title: "Preview override", detail: "Generated init parameters still provide root-level overrides."),
                        ActivityHighlight(id: "preview-2", title: "Retry flow", detail: "The view keeps retry and cancellation logic local to the screen model.")
                    ]
                )
            )
        )
    }

    static func failure(username: String = "Offline") -> Self {
        Self(
            title: "Failure",
            container: AppContainer(
                username: username,
                greetingService: FailingGreetingService(),
                activityService: MockActivityService(highlights: [])
            )
        )
    }
}

@main
struct SwiftUIExampleMain {
    static func main() {
        let liveScenario = DashboardRootScenario.live()
        _ = liveScenario.container.dashboardRootView()
        _ = DashboardRootScenario.preview().container.dashboardShellRootView()
        _ = DashboardRootScenario.failure().container.dashboardRootView()
    }
}
