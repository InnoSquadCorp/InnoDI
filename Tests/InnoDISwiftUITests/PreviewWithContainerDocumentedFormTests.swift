import Foundation
import InnoDISwiftUI
import SwiftUI
import Testing

// The documented `#PreviewWithContainer` form, compiled in an ordinary source
// file as an application would write it. The region below must match the
// `innodi:compile-library` block of SwiftUIPreviewHelper.md (English and
// Korean) apart from imports and comments; the suite checks that.

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
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @MainActor
    @Test("The documented wrapper form renders the generated helper")
    func documentedFormBuildsTheGeneratedHelper() {
        let root = AppPreviewRoot(container: makePreviewApp())
        #expect(root.container.dashboard.baseURL == "https://example.com")
        _ = root.body
    }

    @Test(
        "SwiftUIPreviewHelper compiles the same preview code as this file",
        arguments: [
            "Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md",
            "Sources/InnoDI/InnoDI.docc/ko.lproj/SwiftUIPreviewHelper.md",
        ]
    )
    func documentedBlockMatchesCompiledSource(article: String) throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let compiled = try #require(
            source.components(separatedBy: "// BEGIN documented preview form").dropFirst().first?
                .components(separatedBy: "// END documented preview form").first
        )
        let document = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(article),
            encoding: .utf8
        )
        let block = try #require(
            document.components(separatedBy: "<!-- innodi:compile-library -->\n```swift\n").dropFirst().first?
                .components(separatedBy: "\n```").first
        )
        #expect(Self.code(in: block) == Self.code(in: compiled))
    }

    /// Code lines without imports, comments, or blank lines.
    private static func code(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("import ") }
    }
}
