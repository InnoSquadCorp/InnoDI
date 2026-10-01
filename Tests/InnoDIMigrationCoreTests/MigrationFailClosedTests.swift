import Foundation
@testable import InnoDIMigrationCore
import Testing

/// The rewrites read only direct attributes and unqualified names, so each
/// case below used to report clean or write code that no longer compiles.
/// Every one now blocks the run and leaves the files untouched.
@Suite("Migration fails closed")
struct MigrationFailClosedTests {
    @Test("Legacy spellings the rewrites cannot reach block the run")
    func unreachableLegacyFormsBlock() throws {
        let cases: [(name: String, source: String)] = [
            ("marker in #if", """
                import InnoDI

                #if DEBUG
                @DIComponent
                #endif
                @DIContainer(mainActor: true)
                struct FeatureContainer {}
                """),
            ("container options in #if", """
                import InnoDI

                #if os(iOS)
                @DIContainer(mainActor: true)
                #else
                @DIContainer(root: true)
                #endif
                struct FeatureContainer {}
                """),
            ("input in #if", """
                import InnoDI

                @DIContainer
                struct AppContainer {
                    #if DEBUG
                    @Provide(.input)
                    #endif
                    var config: Config
                }
                """),
            ("parent key path in a macro argument", """
                import InnoDI

                @DIContainer
                struct AppContainer {
                    @Input var config: Config
                    #declarations {
                        @SubContainer(scope: .shared, with: [\\AppContainer.config])
                        var feature: FeatureContainer
                    }
                }
                """),
        ]
        for (name, source) in cases {
            let codes = try blockedCodes(files: ["Sources/App/App.swift": source])
            #expect(codes == ["migrate.legacy-form-unsupported"], Comment(rawValue: name))
        }
    }

    @Test("A nested parent key path in a file with an untrusted import is ambiguous")
    func nestedKeyPathWithUntrustedImportBlocks() throws {
        let codes = try blockedCodes(files: [
            "Sources/App/App.swift": """
                import FeatureKit
                import InnoDI

                @DIContainer
                struct AppContainer {
                    @Input var config: Config
                    @SubContainer(scope: .shared, with: [\\Self.config.baseURL])
                    var feature: FeatureContainer
                }
                """,
        ])
        #expect(codes == ["migrate.unqualified-ownership-ambiguous"])
    }

    @Test("A rewrite target that the scanned sources declare blocks the rewrite")
    func shadowedRewriteTargetsBlock() throws {
        let inputShadow = try blockedCodes(files: [
            "Sources/App/InputMacro.swift": """
                @attached(peer)
                macro Input() = #externalMacro(module: "AppMacros", type: "InputMacro")
                """,
            "Sources/App/AppContainer.swift": """
                import InnoDI

                @DIContainer
                struct AppContainer {
                    @Provide(.input) var config: Config
                }
                """,
        ])
        #expect(inputShadow == ["migrate.rewrite-target-ambiguous"])

        let roleShadow = try blockedCodes(files: [
            "Sources/App/Roles.swift": "enum ContainerRole {\n    case primary\n}\n",
            "Sources/App/Feature.swift": """
                import InnoDI

                @DIComponent
                @DIContainer
                struct FeatureContainer {}
                """,
        ])
        #expect(roleShadow == ["migrate.rewrite-target-ambiguous"])
    }

    @Test("Module-qualified rewrites ignore a same-named local declaration")
    func qualifiedRewritesStillApply() throws {
        let root = try makeTree([
            "Sources/App/Shadows.swift": """
                @attached(peer)
                macro Input() = #externalMacro(module: "AppMacros", type: "InputMacro")
                enum ContainerRole {
                    case primary
                }
                """,
            "Sources/App/App.swift": """
                import InnoDI

                @InnoDI.DIComponent
                @InnoDI.DIContainer
                struct FeatureContainer {
                    @InnoDI.Provide(.input) var config: Config
                }
                """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator().plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        let migrated = try #require(plan.changes.first?.migratedSource)
        #expect(migrated.contains("@InnoDI.DIContainerRole(role: InnoDI.ContainerRole.component)"))
        #expect(migrated.contains("@InnoDI.Input var config: Config"))
    }

    private func blockedCodes(files: [String: String]) throws -> [String] {
        let root = try makeTree(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try InnoDIMigrator().run(root: root, mode: .write)
        for (path, source) in files {
            let written = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            #expect(written == source, Comment(rawValue: path))
        }
        return plan.diagnostics.map(\.code)
    }

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MigrationFailClosed-\(UUID().uuidString)",
            isDirectory: true
        )
        for (path, source) in files {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try source.write(to: file, atomically: true, encoding: .utf8)
        }
        return root
    }
}
