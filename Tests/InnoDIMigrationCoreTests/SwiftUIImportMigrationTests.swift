import Foundation
@testable import InnoDIMigrationCore
import SwiftParser
import SwiftSyntax
import Testing

/// InnoDI 7.0 stops re-exporting SwiftUI from InnoDISwiftUI, so the
/// migration adds `import SwiftUI` wherever a file relied on the re-export.
@Suite("SwiftUI import migration")
struct SwiftUIImportMigrationTests {
    private func migrated(_ source: String, access: MigrationSwiftUIImportAccess? = nil) -> String {
        addingSwiftUIImportForInnoDISwiftUI(to: Parser.parse(source: source), access: access).description
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

    @Test("A full, unconditional SwiftUI import leaves the file unchanged")
    func existingSwiftUIImportsAreKept() {
        for existing in [
            "import SwiftUI",
            "@preconcurrency import SwiftUI",
            "public import SwiftUI",
            "@_exported import SwiftUI",
        ] {
            let source = "import InnoDISwiftUI\n\(existing)\n\nlet value = 1\n"
            #expect(migrated(source) == source, Comment(rawValue: existing))
        }
    }

    @Test("Scoped and conditional SwiftUI imports do not provide every SwiftUI name")
    func partialSwiftUIImportsGainFullImport() {
        for existing in [
            "import struct SwiftUI.Text",
            "#if os(iOS)\nimport SwiftUI\n#endif",
        ] {
            let source = "import InnoDISwiftUI\n\(existing)\n\nlet value = 1\n"
            let expected = "import InnoDISwiftUI\nimport SwiftUI\n\(existing)\n\nlet value = 1\n"
            #expect(migrated(source) == expected, Comment(rawValue: existing))
            #expect(migrated(expected) == expected, Comment(rawValue: existing))
        }
    }

    @Test("The inserted import keeps the InnoDISwiftUI import's access level")
    func insertedImportKeepsAccessLevel() {
        for level in ["public", "package", "internal", "fileprivate", "private"] {
            let source = "\(level) import InnoDISwiftUI\n\nlet value = 1\n"
            let expected = "\(level) import InnoDISwiftUI\n\(level) import SwiftUI\n\nlet value = 1\n"
            #expect(migrated(source, access: level == "public" ? .public : nil) == expected, Comment(rawValue: level))
            #expect(migrated(expected) == expected, Comment(rawValue: level))
        }
    }

    @Test("An existing SwiftUI import is raised to the visibility the file needs")
    func existingImportIsRaised() {
        let cases: [(source: String, expected: String)] = [
            (
                "public import InnoDISwiftUI\nimport SwiftUI\n",
                "public import InnoDISwiftUI\npublic import SwiftUI\n"
            ),
            (
                "@_exported import InnoDISwiftUI\n// SwiftUI for the views\nimport SwiftUI\n",
                "@_exported import InnoDISwiftUI\n// SwiftUI for the views\n@_exported public import SwiftUI\n"
            ),
            (
                "package import InnoDISwiftUI\n@preconcurrency internal import SwiftUI\n",
                "package import InnoDISwiftUI\n@preconcurrency package import SwiftUI\n"
            ),
        ]
        for (source, expected) in cases {
            #expect(migrated(source, access: source.hasPrefix("public ") ? .public : nil) == expected, Comment(rawValue: source))
            #expect(migrated(expected) == expected, Comment(rawValue: source))
        }
    }

    @Test("Semicolon-separated imports stay on one parseable line")
    func semicolonSeparatedImportsStayParseable() {
        let cases: [(source: String, expected: String)] = [
            (
                "import InnoDISwiftUI; import Foundation\n",
                "import InnoDISwiftUI; import SwiftUI; import Foundation\n"
            ),
            (
                "import InnoDISwiftUI;\nimport Foundation\n",
                "import InnoDISwiftUI; import SwiftUI;\nimport Foundation\n"
            ),
        ]
        for (source, expected) in cases {
            let output = migrated(source)
            #expect(output == expected, Comment(rawValue: source))
            #expect(!Parser.parse(source: output).hasError, Comment(rawValue: output))
            #expect(migrated(output) == output)
        }
    }

    @Test("A CRLF file gets a CRLF line for the inserted import")
    func crlfFileKeepsLineEndings() {
        let source = "import InnoDISwiftUI\r\n\r\nlet value = 1\r\n"
        #expect(migrated(source) == "import InnoDISwiftUI\r\nimport SwiftUI\r\n\r\nlet value = 1\r\n")
    }

    @Test("A clause import needs no SwiftUI import of its own when the file scope provides one")
    func enclosingScopeImportCoversClauses() {
        let source = """
            import InnoDISwiftUI
            #if DEBUG
            @_exported import InnoDISwiftUI
            #endif
            """
        let expected = """
            import InnoDISwiftUI
            import SwiftUI
            #if DEBUG
            @_exported import InnoDISwiftUI
            @_exported public import SwiftUI
            #endif
            """
        #expect(migrated(source) == expected)
        #expect(migrated(expected) == expected)
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
                == "@_exported import InnoDISwiftUI\n@_exported public import SwiftUI\n\npublic let value = 1\n"
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
