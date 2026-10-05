import Foundation
import Testing

@testable import InnoDIMigrationCore

@Suite("Cross-file import namespace planning")
struct ImportNamespacePlanTests {
    @Test("Public import remains intact and does not block a sibling migration")
    func publicImportIsLocal() throws {
        let root = try tree(directive: "public import OtherDI")
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.canWrite)
        #expect(plan.changes.map(\.path) == ["App.swift"])
        #expect(plan.changes.first?.migratedSource.contains("@Input var value: Int") == true)
        #expect(try String(contentsOf: root.appendingPathComponent("Imports.swift"), encoding: .utf8)
            == "public import OtherDI\n")
    }

    @Test("A real sibling re-export blocks publication and identifies its source module")
    func realReexportBlocksPlan() throws {
        let root = try tree(directive: "@_exported public import OtherDI")
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator().plan(root: root)
        #expect(!plan.canWrite)
        let diagnostic = try #require(plan.diagnostics.first)
        #expect(diagnostic.code == "migrate.unqualified-ownership-ambiguous")
        #expect(diagnostic.path == "App.swift")
        #expect(diagnostic.message.contains("OtherDI"))
        #expect(try String(contentsOf: root.appendingPathComponent("App.swift"), encoding: .utf8)
            == source)
    }

    private let source = "import InnoDI\n@DIContainer struct App { @Provide(.input) var value: Int }\n"

    private func tree(directive: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InnoDI-ImportPlan-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try source.write(to: root.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try (directive + "\n").write(to: root.appendingPathComponent("Imports.swift"), atomically: true, encoding: .utf8)
        return root
    }
}
