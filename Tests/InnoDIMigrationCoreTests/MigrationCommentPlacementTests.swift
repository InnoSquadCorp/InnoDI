import Foundation
@testable import InnoDIMigrationCore
import Testing

/// Comments around an attribute survive every rewrite because the rewrites
/// keep the attribute's surrounding trivia. Only a comment between an
/// attribute's tokens, or one attached to an attribute that is removed,
/// still blocks the migration.
@Suite("Migration comment placement")
struct MigrationCommentPlacementTests {
    @Test("Comments above and after @Provide(.input) are kept")
    func commentsAroundInputMigrate() throws {
        let migrated = try migrate("""
            import InnoDI

            @DIContainer
            struct AppContainer {
                // MARK: - Inputs

                /// The service endpoint.
                @Provide(.input) // injected by the app
                var baseURL: String
            }
            """)
        #expect(migrated.contains("""
                // MARK: - Inputs

                /// The service endpoint.
                @Input // injected by the app
                var baseURL: String
            """))
    }

    @Test("A comment inside @Provide(.input) still blocks")
    func commentInsideInputBlocks() throws {
        let plan = try plan("""
            import InnoDI

            @DIContainer
            struct AppContainer {
                @Provide(.input /* keep */)
                var baseURL: String
            }
            """)
        #expect(plan.diagnostics.map(\.code) == ["migrate.input-argument-unsupported"])
    }

    @Test("A doc comment above a legacy container is kept")
    func docCommentAboveLegacyContainerMigrates() throws {
        let migrated = try migrate("""
            import InnoDI

            /// The application root.
            @DIContainer(root: true)
            struct AppContainer {
                @Input var baseURL: String
            }
            """)
        #expect(migrated.contains("""
            /// The application root.
            @DIContainerRole(role: ContainerRole.root)
            struct AppContainer {
            """))
    }

    @Test("A comment on a removed legacy marker still blocks")
    func commentOnRemovedMarkerBlocks() throws {
        let plan = try plan("""
            import InnoDI

            @DIContainer
            // The hierarchy root.
            @DIHierarchyRoot
            struct AppContainer {
                @Input var baseURL: String
            }
            """)
        #expect(plan.diagnostics.map(\.code) == ["migrate.container-option-comment"])
    }

    @Test("A doc comment above @SubContainer survives the feature-root move")
    func docCommentAboveSubContainerMigrates() throws {
        let migrated = try migrate("""
            import InnoDISwiftUI
            import SwiftUI

            @DIContainer
            struct AppContainer {
                /// The feature entry point.
                @SubContainer(scope: .shared)
                @DIFeatureRoot(FeatureView.self)
                var feature: FeatureContainer
            }
            """)
        #expect(migrated.contains("""
                /// The feature entry point.
                @SubContainer(scope: .shared, featureRoot: FeatureView.self)
                var feature: FeatureContainer
            """))
    }

    private func plan(_ source: String) throws -> MigrationPlan {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MigrationCommentPlacement-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/App/App.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: file, atomically: true, encoding: .utf8)
        return try InnoDIMigrator().plan(root: root)
    }

    private func migrate(_ source: String) throws -> String {
        let plan = try plan(source)
        #expect(plan.diagnostics.isEmpty, Comment(rawValue: plan.diagnostics.map(\.rendered).joined(separator: "\n")))
        return try #require(plan.changes.first?.migratedSource)
    }
}
