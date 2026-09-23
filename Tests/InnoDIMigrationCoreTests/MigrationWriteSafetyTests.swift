import Foundation
import Testing

@testable import InnoDIMigrationCore

@Suite("Migration publication safety")
struct MigrationWriteSafetyTests {
    private let source = "import InnoDI\n@DIContainer struct C { @Provide(.input) var value: Int }\n"
    private let editorSource = "// saved by editor\nstruct UserChange {}\n"

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InnoDI-WriteSafety-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try source.write(to: root.appendingPathComponent("C.swift"), atomically: true, encoding: .utf8)
        return root
    }

    private func recoveries(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".innodi-migrate-recovery-") }
    }

    @Test("An atomic editor save in the final publish window is retained and reported")
    func atomicSaveDuringPublication() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try InnoDIMigrator().run(
                root: root, mode: .write, beforeWritingChange: nil,
                beforePublishingChange: { _, rollback in
                    #expect(!rollback)
                    try editorSource.write(to: root.appendingPathComponent("C.swift"), atomically: true, encoding: .utf8)
                }
            )
            Issue.record("Concurrent publication must not report successful migration")
        } catch let error as MigrationError {
            let recovery = try #require(recoveries(in: root).first)
            #expect(try String(contentsOf: recovery, encoding: .utf8) == editorSource)
            #expect(error.description.contains(recovery.lastPathComponent))
            #expect(error.description.contains("No automatic conflict overwrite"))
        }
    }

    @Test("An in-place edit in the publish window is retained and reported")
    func inPlaceEditDuringPublication() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try FileHandle(forWritingTo: root.appendingPathComponent("C.swift"))
        defer { try? editor.close() }
        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(
                root: root, mode: .write, beforeWritingChange: nil,
                beforePublishingChange: { _, _ in
                    try editor.truncate(atOffset: 0)
                    try editor.write(contentsOf: Data(editorSource.utf8))
                }
            )
        }
        let recovery = try #require(recoveries(in: root).first)
        #expect(try String(contentsOf: recovery, encoding: .utf8) == editorSource)
    }

    @Test("Late writes through an old editor descriptor survive successful migration")
    func lateEditorDescriptorIsPreserved() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("C.swift")
        let editor = try FileHandle(forWritingTo: file)
        defer { try? editor.close() }
        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.recoveryPaths.count == 1)
        let recovery = root.appendingPathComponent(try #require(plan.recoveryPaths.first))
        #expect(try String(contentsOf: recovery, encoding: .utf8) == source)
        try editor.truncate(atOffset: 0)
        try editor.write(contentsOf: Data(editorSource.utf8))
        #expect(try String(contentsOf: recovery, encoding: .utf8) == editorSource)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("@Input"))
        #expect(try InnoDIMigrator().plan(root: root).changes.isEmpty)
    }

    @Test("Apply and rollback preserve the original source permissions")
    func permissionsSurviveApplyAndRollback() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("C.swift")
        let second = root.appendingPathComponent("D.swift")
        try source.write(to: second, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o664], ofItemAtPath: first.path)
        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(root: root, mode: .write, beforeWritingChange: { _, index in
                if index == 1 {
                    #expect((try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? NSNumber)?.intValue == 0o664)
                    try editorSource.write(to: second, atomically: true, encoding: .utf8)
                }
            })
        }
        #expect((try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? NSNumber)?.intValue == 0o664)
        #expect(try String(contentsOf: first, encoding: .utf8) == source)
    }

    @Test("A concurrent save during rollback is preserved in a named recovery file")
    func rollbackPublishConflict() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("C.swift")
        let second = root.appendingPathComponent("D.swift")
        try source.write(to: second, atomically: true, encoding: .utf8)
        do {
            try InnoDIMigrator().run(
                root: root, mode: .write,
                beforeWritingChange: { _, index in
                    if index == 1 { try editorSource.write(to: second, atomically: true, encoding: .utf8) }
                },
                beforePublishingChange: { _, rollback in
                    if rollback { try editorSource.write(to: first, atomically: true, encoding: .utf8) }
                }
            )
            Issue.record("Rollback conflict must be reported")
        } catch let error as MigrationError {
            #expect(error.description.contains("Rollback also failed"))
            let saved = try recoveries(in: root).filter { try String(contentsOf: $0, encoding: .utf8) == editorSource }
            #expect(saved.count == 1)
            #expect(error.description.contains(try #require(saved.first).lastPathComponent))
        }
    }
}
