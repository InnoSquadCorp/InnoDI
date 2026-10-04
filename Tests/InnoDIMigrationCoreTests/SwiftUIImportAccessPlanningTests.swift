import Foundation
@testable import InnoDIMigrationCore
import Testing

@Suite("SwiftUI import access planning")
struct SwiftUIImportAccessPlanningTests {
    @Test("CLI accepts one explicit SwiftUI access choice and rejects malformed choices")
    func argumentContract() {
        for access in [MigrationSwiftUIImportAccess.internal, .package, .public] {
            #expect(parseMigrationArguments(["--root", ".", "--write", "--swiftui-import-access", access.rawValue])
                    == .options(MigrationOptions(rootPath: ".", mode: .write, swiftUIImportAccess: access)))
        }
        #expect(parseMigrationArguments(["--root", ".", "--write", "--swiftui-import-access"])
                == .failure(.missingOptionValue("--swiftui-import-access")))
        #expect(parseMigrationArguments(["--root", ".", "--write", "--swiftui-import-access", "auto"])
                == .failure(.invalidSwiftUIImportAccess("auto")))
        #expect(parseMigrationArguments(["--root", ".", "--write", "--swiftui-import-access", "public", "--swiftui-import-access", "internal"])
                == .failure(.duplicateOption("--swiftui-import-access")))
    }

    @Test("An explicit peer import blocks ambiguous insertion before any file is written")
    func ambiguousWritePreservesEveryFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-ImportPlanning-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = [
            "Container.swift": "import InnoDISwiftUI\n@DIContainer struct C { @Provide(.input) var value: Int }\n",
            "Other.swift": "internal import SwiftUI\n",
        ]
        for (name, source) in sources {
            try source.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(!plan.canWrite)
        #expect(plan.diagnostics.map(\.code) == ["migrate.swiftui-import-access-ambiguous"])
        #expect(plan.diagnostics.first?.path == "Container.swift")
        for (name, source) in sources {
            #expect(try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) == source)
        }
        let accepted = try InnoDIMigrator(swiftUIImportAccess: .internal).run(root: root, mode: .write)
        #expect(accepted.canWrite)
        let result = try String(contentsOf: root.appendingPathComponent("Container.swift"), encoding: .utf8)
        #expect(result.contains("internal import SwiftUI"))
        #expect(result.contains("@Input"))
        #expect(try InnoDIMigrator(swiftUIImportAccess: .internal).plan(root: root).changes.isEmpty)
    }
}
