import InnoDITestSupport
import SwiftDiagnostics
import Testing

@testable import InnoDIMacros

extension DIContainerMacroTests {
    @Test("Plain feature roots never depend on module availability")
    func plainFeatureRootIgnoresAvailableModules() {
        let result = expandMacroSource(
            """
            @DIContainer struct Parent {
                @SubContainer(scope: .shared, featureRoot: Root.self) var child: Child
            }
            """, macros: Self.macros
        )
        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("func childRootView() -> Root"))
        #expect(!result.expansion.contains("canImport"))
        #expect(!result.expansion.contains("InnoDISwiftUI"))
        #expect(!result.expansion.contains("some SwiftUI.View"))
    }

    @Test("Only explicitly hosted roots receive the identity overload")
    func hostedFeatureRootOptIn() {
        let result = expandMacroSource(
            """
            @DIContainer struct Parent {
                @SubContainer(scope: .shared, featureRoots: [
                    FeatureRoot(Root.self, hosted: true),
                    FeatureRoot(Other.self, as: "other", hosted: false)
                ]) var child: Child
            }
            """, macros: Self.macros
        )
        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("func childRootView() -> Root"))
        #expect(result.expansion.contains("func childRootView<_InnoDIIdentity>"))
        #expect(result.expansion.contains("func otherRootView() -> Other"))
        #expect(!result.expansion.contains("func otherRootView<_InnoDIIdentity>"))
        #expect(!result.expansion.contains("canImport"))
    }

    @Test("A hosted .shared child is presented without a close hook; the 7.0 close overload is deprecated")
    func hostedSharedChildDeprecatesCloseOverload() {
        let result = expandMacroSource(
            """
            @DIContainer struct Parent {
                @SubContainer(scope: .shared, featureRoots: [
                    FeatureRoot(Root.self, hosted: true),
                    FeatureRoot(Shell.self, as: "shell", hosted: true)
                ]) var child: Child
            }
            """, macros: Self.macros
        )
        #expect(result.diagnostics.isEmpty)
        let expansion = whitespaceNormalized(result.expansion)
        for helper in ["childRootView", "shellRootView"] {
            #expect(expansion.components(separatedBy: "func \(helper)<_InnoDIIdentity>(").count == 3)
            #expect(expansion.contains(
                "@_Concurrency.MainActor func \(helper)<_InnoDIIdentity>( identity: _InnoDIIdentity ) "
                    + "-> some SwiftUI.View where _InnoDIIdentity: Swift.Hashable & Swift.Sendable { "
                    + "InnoDISwiftUI.DIContainerHost( identity: identity, factory: { _ in self.child }, content:"
            ))
            let message = sharedHostedFeatureRootCloseDeprecationMessage(
                helperName: helper,
                propertyName: "child"
            )
            #expect(expansion.contains(
                "@available(*, deprecated, message: \"\(message)\") @_Concurrency.MainActor "
                    + "func \(helper)<_InnoDIIdentity>( identity: _InnoDIIdentity, "
                    + "close: @escaping InnoDISwiftUI.DIContainerHostOwner<_InnoDIIdentity, Child>.Close ) "
                    + "-> some SwiftUI.View where _InnoDIIdentity: Swift.Hashable & Swift.Sendable { "
                    + "InnoDISwiftUI.DIContainerHost( identity: identity, factory: { _ in self.child }, close: close, content:"
            ))
        }
        // The close overload has no default, so `identity:` alone resolves to
        // the presentation overload and only an explicit hook is deprecated.
        #expect(!expansion.contains("= { _ in }"))
        #expect(expansion.contains("Call shellRootView(identity:) without close:"))
    }

    @Test("A hosted .transient child keeps one host-owned overload with an optional close hook")
    func hostedTransientChildKeepsCloseOverload() {
        let result = expandMacroSource(
            """
            @DIContainer struct Parent {
                @SubContainer(scope: .transient, featureRoots: [FeatureRoot(Root.self, hosted: true)]) var child: Child
            }
            """, macros: Self.macros
        )
        #expect(result.diagnostics.isEmpty)
        let expansion = whitespaceNormalized(result.expansion)
        #expect(expansion.components(separatedBy: "func childRootView<_InnoDIIdentity>(").count == 2)
        #expect(expansion.contains(
            "@_Concurrency.MainActor func childRootView<_InnoDIIdentity>( identity: _InnoDIIdentity, "
                + "close: @escaping InnoDISwiftUI.DIContainerHostOwner<_InnoDIIdentity, Child>.Close = { _ in } ) "
                + "-> some SwiftUI.View where _InnoDIIdentity: Swift.Hashable & Swift.Sendable { "
                + "InnoDISwiftUI.DIContainerHost( identity: identity, factory: { _ in self.child }, close: close, content:"
        ))
        #expect(!expansion.contains("@available(*, deprecated"))
    }

    @Test("Hosting requires a source literal instead of build-dependent input")
    func hostedFeatureRootLiteral() {
        let result = expandMacroSource(
            """
            @DIContainer struct Parent {
                @SubContainer(scope: .shared, featureRoots: [FeatureRoot(Root.self, hosted: enabled)]) var child: Child
            }
            """, macros: Self.macros
        )
        #expect(result.diagnostics.contains { $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-hosting-requires-bool") })
        #expect(!result.expansion.contains("DIContainerHost("))
    }
}

private func whitespaceNormalized(_ source: String) -> String {
    source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
