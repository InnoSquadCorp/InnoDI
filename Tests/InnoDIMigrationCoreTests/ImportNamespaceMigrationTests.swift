import SwiftParser
import Testing

@testable import InnoDIMigrationCore

@Suite("Import access and namespace visibility")
struct ImportNamespaceMigrationTests {
    @Test("Public imports do not make an untrusted namespace visible to sibling sources")
    func publicImportDoesNotReexportNamespace() {
        let migrator = InnoDIMigrator()
        let imports = Parser.parse(source: "public import OtherDI\n")
        let shadows = migrator.innoDIAttributeShadowNames(in: imports)
        #expect(shadows.isEmpty)
        let sibling = Parser.parse(source: "import InnoDI\n@DIContainer struct App { @Provide(.input) var value: Int }\n")
        let context = migrator.unqualifiedInnoDIAttributeContext(in: sibling, additionalAmbiguousNames: shadows)
        #expect(context.allows("DIContainer"))
        #expect(context.allows("Provide"))
        // A public import is still a real import within its own source file.
        let local = migrator.unqualifiedInnoDIAttributeContext(
            in: Parser.parse(source: "import InnoDI\npublic import OtherDI\n"),
            additionalAmbiguousNames: []
        )
        #expect(!local.allows("Provide"))
        #expect(local.untrustedModules == ["OtherDI"])
    }

    @Test("Only explicit re-export propagates the untrusted namespace",
          arguments: ["@_exported import OtherDI", "@_exported public import OtherDI"])
    func explicitReexportRemainsConservative(_ directive: String) {
        let shadows = InnoDIMigrator().innoDIAttributeShadowNames(in: Parser.parse(source: directive))
        #expect(shadows.contains("DIContainer"))
        #expect(shadows.contains("Provide"))
    }

    @Test("A selective public import remains local to its source")
    func selectivePublicImportDoesNotReexportNamespace() {
        let shadows = InnoDIMigrator().innoDIAttributeShadowNames(
            in: Parser.parse(source: "public import struct OtherDI.Provide\n")
        )
        #expect(shadows.isEmpty)
    }

    @Test("A sibling re-export ambiguity identifies the responsible module")
    func reexportDiagnosticNamesModule() {
        let migrator = InnoDIMigrator()
        let exported = migrator.innoDIAttributeShadowContext(in: Parser.parse(source: "@_exported import OtherDI"))
        let source = Parser.parse(source: "import InnoDI\n@DIContainer struct App { @Provide(.input) var value: Int }\n")
        let context = migrator.unqualifiedInnoDIAttributeContext(
            in: source, additionalAmbiguousNames: exported.names,
            reexportedUntrustedModules: exported.modules
        )
        let rewriter = InnoDISourceMigrationRewriter(path: "App.swift", attributeContext: context)
        _ = rewriter.rewrite(source)
        #expect(rewriter.diagnostics.contains {
            $0.code == "migrate.unqualified-ownership-ambiguous"
                && $0.message.contains("source-tree re-exports expose OtherDI")
        })
    }

    @Test("Name-specific ownership provenance does not blame an unrelated attribute")
    func selectiveReexportProvenanceIsNameSpecific() {
        // Exercise the diagnostic's internal ownership context directly.
        // Swift does not support `import macro Module.Name` source syntax.
        let source = Parser.parse(source: "import InnoDI\n@InnoDI.DIContainer struct App { @Provide(.input) var value: Int }\n")
        let context = UnqualifiedInnoDIAttributeContext(
            availableNames: ["DIContainer", "Provide"],
            ambiguousNames: ["DIContainer", "Provide"],
            reexportedUntrustedModules: ["DIContainer": ["ContainerOnly"], "Provide": ["ProviderOnly"]]
        )
        let rewriter = InnoDISourceMigrationRewriter(path: "App.swift", attributeContext: context)
        _ = rewriter.rewrite(source)
        let diagnostic = rewriter.diagnostics.first { $0.code == "migrate.unqualified-ownership-ambiguous" }
        #expect(diagnostic?.message.contains("ProviderOnly") == true)
        #expect(diagnostic?.message.contains("ContainerOnly") == false)
    }
}
