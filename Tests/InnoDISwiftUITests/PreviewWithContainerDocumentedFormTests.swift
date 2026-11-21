import InnoDISwiftUI
import SwiftUI
import Testing

// The documented `#PreviewWithContainer` form, compiled in an ordinary source
// file as an application would write it. The region below must match the
// `innodi:compile-library` block of SwiftUIPreviewHelper.md (English and
// Korean) apart from imports and comments. `PreviewDocumentedFormSyncTests`
// in InnoDIBuildSupportTests checks that: this target is also built as a
// standalone product consumer, so it cannot read files next to its sources.

// BEGIN documented preview form
@DIContainer
struct DashboardContainer {
    @Input var baseURL: String
}

struct DashboardRootView: View {
    let container: DashboardContainer

    var body: some View {
        Text(container.baseURL)
    }
}

@DIContainer
struct AppContainer {
    @Input var baseURL: String

    @SubContainer(scope: .transient, with: [\Self.baseURL], featureRoot: DashboardRootView.self)
    var dashboard: DashboardContainer
}

// Generated initializers and helpers are called from ordinary declarations,
// never from the #PreviewWithContainer arguments themselves.
func makePreviewApp() -> AppContainer {
    AppContainer(baseURL: "https://example.com")
}

struct AppPreviewRoot: View {
    let container: AppContainer

    var body: some View {
        container.dashboardRootView()
    }
}

#PreviewWithContainer(makePreviewApp()) { container in
    AppPreviewRoot(container: container)
}
// END documented preview form

@Suite("Documented #PreviewWithContainer form")
struct PreviewWithContainerDocumentedFormTests {
    @MainActor
    @Test("The documented wrapper form renders the generated helper")
    func documentedFormBuildsTheGeneratedHelper() {
        let root = AppPreviewRoot(container: makePreviewApp())
        #expect(root.container.dashboard.baseURL == "https://example.com")
        _ = root.body
    }
}
