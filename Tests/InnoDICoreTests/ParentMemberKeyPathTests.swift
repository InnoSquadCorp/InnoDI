import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDICore

/// One shared classification keeps the macro, build support, and graph
/// collectors aligned on which parent key paths name a single member.
@Suite("Parent member key path spelling")
struct ParentMemberKeyPathTests {
    @Test("Self-rooted and rootless key paths with one member are canonical")
    func canonicalSpellings() {
        #expect(parentMemberKeyPathSpelling(expression("\\Self.config")) == .canonical(member: "config"))
        #expect(parentMemberKeyPathSpelling(expression("\\.config")) == .canonical(member: "config"))
    }

    @Test("A named root keeps its member name but is not canonical")
    func namedRoot() {
        let spelling = parentMemberKeyPathSpelling(expression("\\AppContainer.config"))
        #expect(spelling == .namedRoot(root: "AppContainer", member: "config"))
        #expect(spelling.memberName == "config")
    }

    @Test("Nested components, optional chaining, subscripts, and non-key-paths are invalid")
    func invalidSpellings() {
        for source in [
            "\\Self.config.baseURL",
            "\\AppContainer.config.baseURL",
            "\\Self.config?",
            "\\Self.values[0]",
            "config",
        ] {
            #expect(parentMemberKeyPathSpelling(expression(source)) == .invalid, Comment(rawValue: source))
        }
    }

    @Test("A module-qualified child root still resolves the child input")
    func moduleQualifiedChildRoot() throws {
        let info = try subContainerInfo(
            "bindings: [(child: \\FeatureKit.FeatureContainer.config, parent: \\Self.settings)]"
        )
        #expect(info.bindings == [
            SubContainerBindingArgument(childName: "config", parentName: "settings"),
        ])
    }

    @Test("Sub-container with: and bindings: reject nested components but resolve named roots")
    func subContainerArguments() throws {
        let nestedWith = try subContainerInfo("with: [\\Self.config.baseURL]")
        #expect(nestedWith.sameNameWiring == .invalid(label: .with))

        let namedWith = try subContainerInfo("with: [\\AppContainer.config]")
        #expect(namedWith.sameNameWiring == .parsed(label: .with, dependencies: ["config"]))

        let nestedParent = try subContainerInfo(
            "bindings: [(child: \\FeatureContainer.config, parent: \\Self.settings.config)]"
        )
        #expect(nestedParent.bindingsParseState == .invalid)

        let named = try subContainerInfo(
            "bindings: [(child: \\FeatureContainer.config, parent: \\AppContainer.settings)]"
        )
        #expect(named.bindings == [
            SubContainerBindingArgument(childName: "config", parentName: "settings"),
        ])
    }

    private func expression(_ source: String) -> ExprSyntax {
        let file = Parser.parse(source: "let value = \(source)")
        let binding = file.statements.first?.item.as(VariableDeclSyntax.self)?.bindings.first
        return binding?.initializer?.value ?? ExprSyntax(NilLiteralExprSyntax())
    }

    private func subContainerInfo(_ arguments: String) throws -> SubContainerAttributeInfo {
        let file = Parser.parse(source: """
            struct AppContainer {
                @SubContainer(scope: .shared, \(arguments))
                var feature: FeatureContainer
            }
            """)
        let structDecl = try #require(
            file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
        )
        let variable = try #require(
            structDecl.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.first
        )
        return try #require(parseSubContainerAttribute(variable.attributes))
    }
}
