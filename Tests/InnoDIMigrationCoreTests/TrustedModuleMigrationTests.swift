import Foundation
@testable import InnoDIMigrationCore
import Testing

/// A real application's container files import its own modules, and the
/// migrator cannot prove those modules declare no `Provide` or `DIContainer`
/// attribute. `--trust-module` lets the user assert that per module.
@Suite("Trusted module migration")
struct TrustedModuleMigrationTests {
    private static let container = """
        import Domain
        import InnoDI
        import Layers

        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: Config
        }
        """

    @Test("--trust-module is repeatable and deduplicated")
    func parsesTrustedModules() {
        #expect(
            parseMigrationArguments([
                "--root", "/tmp/app", "--check",
                "--trust-module", "Domain",
                "--trust-module", "Layers",
                "--trust-module", "Domain",
            ]) == .options(
                MigrationOptions(
                    rootPath: "/tmp/app",
                    mode: .check,
                    trustedModules: ["Domain", "Layers"]
                )
            )
        )
        #expect(
            parseMigrationArguments(["--root", "/tmp/app", "--check", "--trust-module"])
                == .failure(.missingOptionValue("--trust-module"))
        )
        #expect(
            parseMigrationArguments(["--root", "/tmp/app", "--check", "--trust-module", "--write"])
                == .failure(.missingOptionValue("--trust-module"))
        )
    }

    @Test("The ambiguity diagnostic names the imports behind it")
    func ambiguityNamesImports() throws {
        let root = try makeTree(["Sources/App/AppContainer.swift": Self.container])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator().plan(root: root)
        let diagnostic = try #require(plan.diagnostics.first)
        #expect(plan.diagnostics.count == 1)
        #expect(diagnostic.code == "migrate.unqualified-ownership-ambiguous")
        #expect(diagnostic.message.contains("this file imports Domain, Layers"))
        #expect(diagnostic.message.contains("--trust-module <name>"))
        #expect(!plan.canWrite)
    }

    @Test("Trusting every imported module unblocks the migration")
    func trustedModulesMigrate() throws {
        let root = try makeTree(["Sources/App/AppContainer.swift": Self.container])
        defer { try? FileManager.default.removeItem(at: root) }

        let migrator = InnoDIMigrator(trustedModules: ["Domain", "Layers"])
        let plan = try migrator.plan(root: root)
        #expect(plan.diagnostics.isEmpty)
        #expect(plan.changes.first?.rules == [MigrationRule.inputAttribute])
        #expect(plan.changes.first?.migratedSource.contains("@Input var config: Config") == true)

        _ = try migrator.run(root: root, mode: .write)
        #expect(try migrator.plan(root: root).changes.isEmpty)
    }

    @Test("Trusting only some modules keeps the rest ambiguous")
    func partialTrustStaysBlocked() throws {
        let root = try makeTree(["Sources/App/AppContainer.swift": Self.container])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator(trustedModules: ["Domain"]).plan(root: root)
        let diagnostic = try #require(plan.diagnostics.first)
        #expect(diagnostic.message.contains("this file imports Layers,"))
        #expect(!diagnostic.message.contains("Domain"))
    }

    @Test("Trust never overrides a shadowing declaration in the sources")
    func trustDoesNotOverrideSourceShadows() throws {
        let root = try makeTree([
            "Sources/App/AppContainer.swift": Self.container,
            "Sources/Domain/Provide.swift": """
                @attached(peer)
                public macro Provide(_ value: Any) = #externalMacro(module: "DomainMacros", type: "ProvideMacro")
                """,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try InnoDIMigrator(trustedModules: ["Domain", "Layers"]).plan(root: root)
        #expect(plan.diagnostics.map(\.code) == ["migrate.unqualified-ownership-ambiguous"])
        #expect(!plan.canWrite)
    }

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-TrustedModuleMigration-\(UUID().uuidString)",
            isDirectory: true
        )
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }
}
