import Foundation
import Testing

@Suite("Documentation snippet script contracts")
struct DocumentationSnippetScriptTests {
    @Test("Unreleased examples and stable installation have explicit version boundaries")
    func readmeInstallationMatchesDocumentationChannel() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", "-m", "unittest", "discover", "-s", "Tools/tests", "-p", "test_readme_installation.py"]
        process.currentDirectoryURL = packageRootURL()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

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
