import Foundation
import Testing

@Suite("Public dependency-graph command documentation")
struct PublicCLIDocumentationTests {
    @Test("Release upgrade diagnostics provide a consumer root without applying changes")
    func releaseUpgradeCommandsAreReadOnlyAndComplete() throws {
        let source = try String(
            contentsOf: packageRootURL().appendingPathComponent("RELEASING.md"),
            encoding: .utf8
        )
        let upgradeStart = try #require(source.range(of: "### Upgrade Actions\n"))
        let currentUpgrade = source[upgradeStart.upperBound...]
            .components(separatedBy: "\n## ")[0]
        let commands = currentUpgrade.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter {
            $0.hasPrefix("swift run InnoDI-Doctor ") || $0.hasPrefix("swift run InnoDI-Migrate ")
        }
        #expect(commands.contains("swift run InnoDI-Doctor --root /path/to/consumer"))
        #expect(commands.contains("swift run InnoDI-Migrate --root /path/to/consumer --check"))
        #expect(commands.contains("swift run InnoDI-Migrate --root /path/to/consumer --report"))
        for command in commands {
            #expect(command.contains("--root /path/to/consumer"))
            #expect(!command.contains("--write"))
            #expect(!command.contains("--apply"))
            #expect(!command.contains("--verify"))
        }
    }

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
