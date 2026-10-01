import Foundation
@testable import InnoDIMigrationCore
import Testing

/// `--check`, `--report`, and `--write` list which rule changed each file,
/// so an upgrade from 6.x can be reviewed rule by rule.
@Suite("Migration rule inventory")
struct MigrationRuleInventoryTests {
    private static let sources: [String: String] = [
        "Sources/App/ParentKeyPath.swift": """
            import InnoDI

            @DIContainer
            struct AppContainer {
                @Input var config: Config

                @SubContainer(scope: .shared, with: [\\AppContainer.config])
                var feature: FeatureContainer
            }
            """,
        "Sources/App/SwiftUIImport.swift": """
            import InnoDISwiftUI

            struct Screen {}
            """,
        "Sources/App/Both.swift": """
            import InnoDI
            import InnoDISwiftUI

            @DIContainer
            struct RootContainer {
                @Input var config: Config

                @SubContainer(scope: .shared, with: [\\RootContainer.config], featureRoot: RootView.self)
                var feature: FeatureContainer
            }
            """,
        "Sources/App/LegacyInput.swift": """
            import InnoDI

            @DIContainer
            struct LegacyContainer {
                @Provide(.input) var config: Config
            }
            """,
        "Sources/App/Current.swift": """
            import InnoDI
            import InnoDISwiftUI
            import SwiftUI

            @DIContainer
            struct CurrentContainer {
                @Input var config: Config

                @SubContainer(scope: .shared, with: [\\Self.config])
                var feature: FeatureContainer
            }
            """,
    ]

    @Test("The plan and report list the rules behind every changed file")
    func reportInventoriesRules() throws {
        let root = try makeTree(Self.sources)
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let rulesByPath = Dictionary(
            uniqueKeysWithValues: plan.changes.map { ($0.path, $0.rules) }
        )
        #expect(rulesByPath == [
            "Sources/App/Both.swift": [MigrationRule.parentKeyPath, MigrationRule.swiftUIImport],
            "Sources/App/LegacyInput.swift": [MigrationRule.inputAttribute],
            "Sources/App/ParentKeyPath.swift": [MigrationRule.parentKeyPath],
            "Sources/App/SwiftUIImport.swift": [MigrationRule.swiftUIImport],
        ])

        let report = MigrationReport(plan: plan)
        #expect(report.changeCount == 4)
        #expect(report.changes.allSatisfy { $0.code == "migrate.source-update" })
        #expect(report.changes.map(\.rules) == [
            [MigrationRule.parentKeyPath, MigrationRule.swiftUIImport],
            [MigrationRule.inputAttribute],
            [MigrationRule.parentKeyPath],
            [MigrationRule.swiftUIImport],
        ])
        let json = String(decoding: try report.encodedJSON(), as: UTF8.self)
        #expect(json.contains("\"rules\" : [\n        \"migrate.parent-key-path\",\n        \"migrate.swiftui-import\""))

        _ = try InnoDIMigrator().run(root: root, mode: .write)
        let rerun = try InnoDIMigrator().plan(root: root)
        #expect(rerun.changes.isEmpty)
        #expect(rerun.diagnostics.isEmpty)
    }

    @Test("Reports written before rules existed still decode")
    func legacyReportsDecode() throws {
        let legacy = """
            {"code": "migrate.source-update", "path": "Sources/A.swift"}
            """
        let change = try JSONDecoder().decode(MigrationReportChange.self, from: Data(legacy.utf8))
        #expect(change.rules.isEmpty)
        #expect(change.path == "Sources/A.swift")
    }

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MigrationRuleInventory-\(UUID().uuidString)",
            isDirectory: true
        )
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }
}
