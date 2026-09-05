import Foundation
import Testing

@Suite("Documentation snippet script contracts")
struct DocumentationSnippetScriptTests {
    @Test("Local package identity remains stable in renamed checkouts")
    func localDependencyUsesExplicitIdentity() throws {
        let script = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent("Tools/check-docs-code-blocks.sh"),
            encoding: .utf8
        )

        #expect(
            script.contains(
                #".package(name: "InnoDI", path: "%s")"#
            )
        )
        #expect(
            script.contains(
                #".product(name: "InnoDI", package: "InnoDI")"#
            )
        )
        #expect(
            script.contains(
                #".product(name: "InnoDISwiftUI", package: "InnoDI")"#
            )
        )
    }
}
