import Foundation
@testable import InnoDIMigrationCore
import Testing

/// Legacy `@DIContainer(root:mainActor:)` options become a role only when one
/// applies. `@DIContainerRole` requires `role:`, so a container that keeps no
/// role stays an ordinary `@DIContainer`.
@Suite("Container role migration")
struct ContainerRoleMigrationTests {
    @Test("An isolated container without a marker becomes a local role")
    func isolatedContainerBecomesLocalRole() throws {
        let migrated = try migrate("""
            import InnoDI

            @DIContainer(mainActor: true)
            struct FeatureContainer {}

            @DIContainer(mainActor: true, validateDAG: false)
            struct FixtureContainer {}

            @InnoDI.DIContainer(root: false, mainActor: true)
            struct QualifiedContainer {}
            """)
        #expect(migrated.contains("""
            @DIContainerRole(role: ContainerRole.local, mainActor: true)
            struct FeatureContainer {}
            """))
        #expect(migrated.contains("""
            @DIContainerRole(role: ContainerRole.local, mainActor: true, validateDAG: false)
            struct FixtureContainer {}
            """))
        #expect(migrated.contains("""
            @InnoDI.DIContainerRole(role: InnoDI.ContainerRole.local, mainActor: true)
            struct QualifiedContainer {}
            """))
    }

    @Test("Default-valued legacy options leave an ordinary container")
    func defaultOptionsKeepOrdinaryContainer() throws {
        let migrated = try migrate("""
            import InnoDI

            @DIContainer(root: false) // kept as an ordinary container
            struct FeatureContainer {}

            @DIContainer(mainActor: false, validateDAG: false)
            struct FixtureContainer {}

            @InnoDI.DIContainer(root: false, mainActor: false)
            struct QualifiedContainer {}
            """)
        #expect(migrated.contains("""
            @DIContainer // kept as an ordinary container
            struct FeatureContainer {}
            """))
        #expect(migrated.contains("""
            @DIContainer(validateDAG: false)
            struct FixtureContainer {}
            """))
        #expect(migrated.contains("""
            @InnoDI.DIContainer
            struct QualifiedContainer {}
            """))
        #expect(!migrated.contains("DIContainerRole"))
    }

    @Test("Role migration is idempotent")
    func roleMigrationIsIdempotent() throws {
        let root = try makeTree("""
            import InnoDI

            @DIContainer(mainActor: true)
            struct FeatureContainer {}

            @DIContainer(root: false)
            struct PlainContainer {}
            """)
        defer { try? FileManager.default.removeItem(at: root) }

        let migrator = InnoDIMigrator()
        let written = try migrator.run(root: root, mode: .write)
        #expect(written.diagnostics.isEmpty)
        #expect(written.changes.count == 1)
        let second = try migrator.plan(root: root)
        #expect(second.diagnostics.isEmpty)
        #expect(second.changes.isEmpty)
    }

    @Test("A marker on a container without arguments gains the role argument list")
    func markerOnlyContainerGainsArgumentList() throws {
        let root = try makeTree("""
            import InnoDI

            @DIComponent
            @DIContainer // mounted by AppContainer
            struct FeatureContainer {}

            @InnoDI.DIHierarchyRoot
            @InnoDI.DIContainer
            struct AppContainer {}
            """)
        defer { try? FileManager.default.removeItem(at: root) }

        let migrator = InnoDIMigrator()
        let plan = try migrator.plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(migrated.contains("""
            @DIContainerRole(role: ContainerRole.component) // mounted by AppContainer
            struct FeatureContainer {}
            """))
        #expect(migrated.contains("""
            @InnoDI.DIContainerRole(role: InnoDI.ContainerRole.root)
            struct AppContainer {}
            """))

        _ = try migrator.run(root: root, mode: .write)
        #expect(try migrator.plan(root: root).changes.isEmpty)
    }

    @Test("A component marked root: true blocks instead of dropping a role")
    func componentMarkedRootBlocks() throws {
        let source = """
            import InnoDI

            @DIComponent
            @DIContainer(root: true)
            struct FeatureContainer {}
            """
        let root = try makeTree(source)
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        #expect(plan.changes.isEmpty)
        #expect(plan.diagnostics.map(\.code) == ["migrate.container-role-conflict"])
        #expect(
            try String(contentsOf: root.appendingPathComponent(Self.sourcePath), encoding: .utf8)
                == source
        )
    }

    private static let sourcePath = "Sources/App/App.swift"

    private func makeTree(_ source: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-ContainerRoleMigration-\(UUID().uuidString)",
            isDirectory: true
        )
        let file = root.appendingPathComponent(Self.sourcePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: file, atomically: true, encoding: .utf8)
        return root
    }

    private func migrate(_ source: String) throws -> String {
        let root = try makeTree(source)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty, Comment(rawValue: plan.diagnostics.map(\.rendered).joined(separator: "\n")))
        return try #require(plan.changes.first?.migratedSource)
    }
}
