import Foundation
@testable import InnoDIMigrationCore
import SwiftParser
import Testing

@Suite("Mixed-file SwiftUI import access")
struct MixedSwiftUIImportPlanTests {
    @Test("A peer's implicit import blocks newly explicit non-public imports even with an access choice")
    func implicitPeerBlocksWrite() throws {
        let choices: [MigrationSwiftUIImportAccess?] = [nil, .internal, .package]
        for choice in choices {
            let files = [
                "Anchor.swift": "internal import InnoDISwiftUI\n",
                "Peer.swift": "import SwiftUI\n",
                // A valid independent rewrite must not be published partially.
                "Legacy.swift": "import InnoDI\n@DIContainer struct Legacy { @Provide(.input) var number: Int }\n",
            ]
            let root = try makeTree(files)
            defer { try? FileManager.default.removeItem(at: root) }
            let plan = try InnoDIMigrator(swiftUIImportAccess: choice).run(root: root, mode: .write)
            #expect(!plan.canWrite)
            #expect(plan.diagnostics.contains {
                $0.code == "migrate.swiftui-import-access-ambiguous"
                    && $0.message.contains("implicit access")
            })
            for (name, source) in files {
                #expect(try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) == source)
            }
        }
    }

    @Test("Imports newly introduced by two files are checked together before writing")
    func plannedImportsAreCheckedTogether() throws {
        let files = [
            "Anchor.swift": "internal import InnoDISwiftUI\n",
            "Peer.swift": "import InnoDISwiftUI\n",
        ]
        let root = try makeTree(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(!plan.canWrite)
        #expect(plan.diagnostics.contains { $0.code == "migrate.swiftui-import-access-ambiguous" })
        for (name, source) in files {
            #expect(try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) == source)
        }
    }

    @Test("Explicit peers permit an internal migration and a second run is clean")
    func explicitPeerAndIdempotence() throws {
        let root = try makeTree([
            "Anchor.swift": "internal import InnoDISwiftUI\n",
            "Peer.swift": "internal import SwiftUI\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let migrator = InnoDIMigrator(swiftUIImportAccess: .internal)
        let first = try migrator.run(root: root, mode: .write)
        #expect(first.canWrite)
        #expect(first.changes.map(\.path) == ["Anchor.swift"])
        #expect(try String(contentsOf: root.appendingPathComponent("Anchor.swift"), encoding: .utf8)
            == "internal import InnoDISwiftUI\ninternal import SwiftUI\n")
        let second = try migrator.plan(root: root)
        #expect(second.canWrite)
        #expect(second.changes.isEmpty)
    }

    @Test("An explicitly chosen public import does not need to narrow an implicit peer")
    func publicChoiceIsNotNarrowed() throws {
        let root = try makeTree([
            "Anchor.swift": "internal import InnoDISwiftUI\n",
            "Peer.swift": "import SwiftUI\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator(swiftUIImportAccess: .public).plan(root: root)
        #expect(plan.canWrite)
        #expect(plan.changes.first?.migratedSource == "internal import InnoDISwiftUI\npublic import SwiftUI\n")
    }

    @Test("Scoped and conditional peer imports also carry implicit module access", arguments: [
        "import struct SwiftUI.Text\n",
        "#if FEATURE\nimport SwiftUI\n#endif\n",
    ])
    func partialPeersRemainConservative(_ peer: String) throws {
        let root = try makeTree([
            "Anchor.swift": "internal import InnoDISwiftUI\n",
            "Peer.swift": peer,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator(swiftUIImportAccess: .internal).plan(root: root)
        #expect(!plan.canWrite)
    }

    @Test("An implicit import upgraded in the same file is not counted as a remaining peer")
    func upgradedImportIsNotAFalseConflict() {
        let source = "package import InnoDISwiftUI\nimport SwiftUI\n"
        var diagnostics: [String] = []
        let output = addingSwiftUIImportForInnoDISwiftUI(
            to: Parser.parse(source: source), access: .package
        ) { diagnostics.append($0) }.description
        #expect(diagnostics.isEmpty)
        #expect(output == "package import InnoDISwiftUI\npackage import SwiftUI\n")
    }

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-MixedImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, source) in files {
            try source.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return root
    }
}
