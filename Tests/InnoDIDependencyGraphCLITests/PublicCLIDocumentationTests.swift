import Foundation
import Testing

@Suite("Public dependency-graph command documentation")
struct PublicCLIDocumentationTests {
    @Test("Every documented render command selects root pruning explicitly")
    func renderCommandsSelectRootPruning() throws {
        let root = packageRootURL()
        let documentationPaths = [
            "README.md",
            "README.ko.md",
            "README.ja.md",
            "README.zh-Hans.md",
            "README.de.md",
            "README.es.md",
            "README.ru.md",
            "Examples/README.md",
            "AGENTS.md",
        ]

        var renderCommands: [String] = []
        for relativePath in documentationPaths {
            let source = try String(
                contentsOf: root.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            for line in source.split(separator: "\n").map(String.init)
            where line.contains("swift run InnoDI-DependencyGraph") {
                if line.contains("--validate-dag")
                    || line.contains("--diagnose-lock")
                    || line.contains("--cache-stats")
                    || line.contains("--why")
                    || line.contains("--dependents")
                    || line.contains("--unused")
                    || line.contains("--diff")
                    || line.contains("--help") {
                    continue
                }
                guard line.contains("--root")
                        || line.contains("--analysis-manifest") else {
                    continue
                }
                renderCommands.append("\(relativePath): \(line)")
                #expect(
                    line.contains("--root-pruning all")
                        || line.contains("--root-pruning roots"),
                    "Missing explicit render scope in \(relativePath): \(line)"
                )
            }
        }

        #expect(!renderCommands.isEmpty)
    }
}
