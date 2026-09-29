import Foundation
@testable import InnoDIMigrationCore
import SwiftParser
import SwiftSyntax
import Testing

/// InnoDI 7.0 stops re-exporting SwiftUI from InnoDISwiftUI, so the
/// migration adds `import SwiftUI` wherever a file relied on the re-export.
@Suite("SwiftUI import migration")
struct SwiftUIImportMigrationTests {
    private func migrated(_ source: String) -> String {
        addingSwiftUIImportForInnoDISwiftUI(to: Parser.parse(source: source)).description
    }

    @Test("A file that imports only InnoDISwiftUI gains import SwiftUI once")
    func insertsAfterInnoDISwiftUI() {
        let source = """
            import Foundation
            import InnoDI
            import InnoDISwiftUI
            import Layers

            @DIContainer
            struct AppContainer {}
            """
        let expected = """
            import Foundation
            import InnoDI
            import InnoDISwiftUI
            import SwiftUI
            import Layers

            @DIContainer
            struct AppContainer {}
            """
        #expect(migrated(source) == expected)
        #expect(migrated(expected) == expected)
    }

    @Test("Any existing SwiftUI import leaves the file unchanged")
    func existingSwiftUIImportsAreKept() {
        for existing in [
            "import SwiftUI",
            "@preconcurrency import SwiftUI",
            "import struct SwiftUI.Text",
            "#if canImport(SwiftUI)\nimport SwiftUI\n#endif",
        ] {
            let source = "import InnoDISwiftUI\n\(existing)\n\nlet value = 1\n"
            #expect(migrated(source) == source, Comment(rawValue: existing))
        }
    }

    @Test("Files without InnoDISwiftUI are unchanged")
    func unrelatedFilesAreUnchanged() {
        let source = "import InnoDI\nimport InnoDISwiftUIExtras\n\nlet value = 1\n"
        #expect(migrated(source) == source)
    }

    @Test("An exported InnoDISwiftUI import keeps SwiftUI visible to clients")
    func exportedImportStaysExported() {
        let source = "@_exported import InnoDISwiftUI\n\npublic let value = 1\n"
        #expect(
            migrated(source)
                == "@_exported import InnoDISwiftUI\n@_exported import SwiftUI\n\npublic let value = 1\n"
        )
    }

    @Test("A testable import gains an ordinary SwiftUI import")
    func testableImportGainsPlainImport() {
        let source = "@testable import InnoDISwiftUI\nimport Testing\n"
        #expect(migrated(source) == "@testable import InnoDISwiftUI\nimport SwiftUI\nimport Testing\n")
    }

    @Test("Conditional imports gain SwiftUI inside each clause")
    func conditionalImportsGainImportPerClause() {
        let source = """
            #if os(iOS)
            import InnoDISwiftUI
            #elseif os(macOS)
                import InnoDISwiftUI
            #endif

            let value = 1
            """
        let expected = """
            #if os(iOS)
            import InnoDISwiftUI
            import SwiftUI
            #elseif os(macOS)
                import InnoDISwiftUI
                import SwiftUI
            #endif

            let value = 1
            """
        #expect(migrated(source) == expected)
        #expect(migrated(expected) == expected)
    }

    @Test("An unconditional import takes precedence over conditional ones")
    func unconditionalImportInsertsOnce() {
        let source = """
            import InnoDISwiftUI
            #if DEBUG
            import InnoDISwiftUI
            #endif
            """
        let expected = """
            import InnoDISwiftUI
            import SwiftUI
            #if DEBUG
            import InnoDISwiftUI
            #endif
            """
        #expect(migrated(source) == expected)
    }

    @Test("The migrator plans the insertion and reruns clean")
    func migratorPlansInsertionIdempotently() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-SwiftUIImportMigration-\(UUID().uuidString)",
            isDirectory: true
        )
        let file = root.appendingPathComponent("Sources/App/AppContainer.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try """
            import InnoDI
            import InnoDISwiftUI

            @DIContainer
            struct AppContainer {
                @Input var config: Config

                @SubContainer(scope: .shared, with: [\\Self.config], featureRoot: FeatureRootView.self)
                var feature: FeatureContainer
            }
            """.write(to: file, atomically: true, encoding: .utf8)

        let migrator = InnoDIMigrator()
        let plan = try migrator.plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        #expect(plan.changes.map(\.path) == ["Sources/App/AppContainer.swift"])
        #expect(plan.changes.first?.migratedSource.contains("import InnoDISwiftUI\nimport SwiftUI\n") == true)

        _ = try migrator.run(root: root, mode: .write)
        let second = try migrator.plan(root: root)
        #expect(second.diagnostics.isEmpty)
        #expect(second.changes.isEmpty)
    }
}
