import Foundation
@testable import InnoDIMigrationCore
import Testing

/// Removing `@DIComponent`, `@DIHierarchyRoot`, or `@DIFeatureRoot` deletes
/// that attribute's line and nothing else: the blank line and indentation
/// above it stay, and the next line keeps its own comments.
@Suite("Migration attribute removal layout")
struct MigrationAttributeRemovalLayoutTests {
    @Test("A removed first marker keeps the blank line above it")
    func removedFirstMarkerKeepsBlankLine() throws {
        let migrated = try migrate("""
            import InnoDI

            @DIHierarchyRoot
            @DIContainer(root: true, mainActor: true)
            struct AppContainer {}
            """)
        #expect(migrated.contains("""
            import InnoDI

            @DIContainerRole(role: ContainerRole.root, mainActor: true)
            struct AppContainer {}
            """))
    }

    @Test("A removed last marker leaves the declaration on its own line")
    func removedLastMarkerKeepsDeclarationLine() throws {
        let migrated = try migrate("""
            import InnoDI

            @DIContainer(mainActor: true)
            @DIComponent
            public struct FeatureContainer {}

            @DIContainer
            @DIHierarchyRoot
            struct AppContainer {}
            """)
        #expect(migrated.contains("""
            import InnoDI

            @DIContainerRole(role: ContainerRole.component, mainActor: true)
            public struct FeatureContainer {}

            @DIContainerRole(role: ContainerRole.root)
            struct AppContainer {}
            """))
    }

    @Test("A nested container keeps its indentation and the comment below the marker")
    func nestedContainerKeepsIndentationAndComment() throws {
        let migrated = try migrate("""
            import InnoDI

            enum Features {
                static let name = "features"

                @DIComponent
                /// The mountable feature.
                @DIContainer
                struct FeatureContainer {}
            }
            """)
        #expect(migrated.contains("""
                static let name = "features"

                /// The mountable feature.
                @DIContainerRole(role: ContainerRole.component)
                struct FeatureContainer {}
            }
            """))
    }

    @Test("A removed feature root keeps the member layout")
    func removedFeatureRootKeepsMemberLayout() throws {
        let migrated = try migrate("""
            import InnoDISwiftUI
            import SwiftUI

            @DIContainer
            struct AppContainer {
                @Input var config: Config

                @DIFeatureRoot(FeatureView.self)
                @SubContainer(scope: .shared)
                var feature: FeatureContainer

                @SubContainer(scope: .shared)
                @DIFeatureRoot(SettingsView.self)
                public var settings: SettingsContainer
            }
            """)
        #expect(migrated.contains("""
                @Input var config: Config

                @SubContainer(scope: .shared, featureRoot: FeatureView.self)
                var feature: FeatureContainer

                @SubContainer(scope: .shared, featureRoot: SettingsView.self)
                public var settings: SettingsContainer
            }
            """))
    }

    private func migrate(_ source: String) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MigrationAttributeRemovalLayout-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/App/App.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: file, atomically: true, encoding: .utf8)
        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty, Comment(rawValue: plan.diagnostics.map(\.rendered).joined(separator: "\n")))
        return try #require(plan.changes.first?.migratedSource)
    }
}
