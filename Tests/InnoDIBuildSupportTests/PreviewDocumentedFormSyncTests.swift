import Foundation
import Testing

/// `Tests/InnoDISwiftUITests/PreviewWithContainerDocumentedFormTests.swift`
/// compiles the documented `#PreviewWithContainer` form. That target is also
/// linked into a standalone product-consumer package, where its sources may
/// not read the repository, so the comparison with the articles lives here.
@Suite("Documented #PreviewWithContainer form matches its compiled source")
struct PreviewDocumentedFormSyncTests {
    private static let compiledSource = "Tests/InnoDISwiftUITests/PreviewWithContainerDocumentedFormTests.swift"

    @Test(
        "SwiftUIPreviewHelper shows the same preview code that InnoDISwiftUITests compiles",
        arguments: [
            "Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md",
            "Sources/InnoDI/InnoDI.docc/ko.lproj/SwiftUIPreviewHelper.md",
        ]
    )
    func documentedBlockMatchesCompiledSource(article: String) throws {
        let source = try Self.contents(of: Self.compiledSource)
        let compiled = try #require(
            source.components(separatedBy: "// BEGIN documented preview form").dropFirst().first?
                .components(separatedBy: "// END documented preview form").first
        )
        let document = try Self.contents(of: article)
        let block = try #require(
            document.components(separatedBy: "<!-- innodi:compile-library -->\n```swift\n").dropFirst().first?
                .components(separatedBy: "\n```").first
        )
        let documentedCode = Self.code(in: block)
        #expect(!documentedCode.isEmpty)
        #expect(documentedCode == Self.code(in: compiled))
    }

    private static func contents(of path: String) throws -> String {
        try String(contentsOf: packageRootURL().appendingPathComponent(path), encoding: .utf8)
    }

    /// Code lines without imports, comments, or blank lines.
    private static func code(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("import ") }
    }
}
