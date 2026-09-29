import Foundation
import Testing

@Suite("Public dependency-graph command documentation")
struct PublicCLIDocumentationTests {
    @Test("Release upgrade diagnostics provide a consumer root without applying changes")
    func releaseUpgradeCommandsAreReadOnlyAndComplete() throws {
        let source = try String(
            contentsOf: packageRootURL().appendingPathComponent("CHANGELOG.md"),
            encoding: .utf8
        )
        // The latest published release owns the complete upgrade commands.
        // An Unreleased section may accumulate its own commands during a train;
        // they must follow the same read-only placeholder contract.
        let stableMarker = "Latest stable public release: `"
        let markerRange = try #require(source.range(of: stableMarker))
        let versionEnd = try #require(
            source[markerRange.upperBound...].firstIndex(of: "`")
        )
        let stableVersion = String(source[markerRange.upperBound..<versionEnd])
        let stableCommands = try upgradeCommands(in: source, section: stableVersion)
        #expect(stableCommands.contains("swift run InnoDI-Doctor --root /path/to/consumer"))
        #expect(stableCommands.contains("swift run InnoDI-Migrate --root /path/to/consumer --check"))
        #expect(stableCommands.contains("swift run InnoDI-Migrate --root /path/to/consumer --report"))

        var commands = stableCommands
        if source.contains("\n## Unreleased\n") {
            commands += try upgradeCommands(in: source, section: "Unreleased")
        }
        for command in commands {
            #expect(command.contains("--root /path/to/consumer"))
            #expect(!command.contains("--write"))
            #expect(!command.contains("--apply"))
            #expect(!command.contains("--verify"))
        }
    }

    private func upgradeCommands(in source: String, section: String) throws -> [String] {
        let sectionStart = try #require(source.range(of: "\n## \(section)\n"))
        let body = source[sectionStart.upperBound...].components(separatedBy: "\n## ")[0]
        let upgradeStart = try #require(body.range(of: "### Upgrade Actions\n"))
        return body[upgradeStart.upperBound...].split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter {
            $0.hasPrefix("swift run InnoDI-Doctor ") || $0.hasPrefix("swift run InnoDI-Migrate ")
        }
    }

    @Test("Every documented render command selects root pruning explicitly")
    func renderCommandsSelectRootPruning() throws {
        let root = packageRootURL()
        let documentationPaths = [
            "README.md",
            "README.ko.md",
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
