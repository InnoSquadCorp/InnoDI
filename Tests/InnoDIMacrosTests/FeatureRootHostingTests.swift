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
        #expect(result.expansion.contains("func childRootView<Identity>"))
        #expect(result.expansion.contains("func otherRootView() -> Other"))
        #expect(!result.expansion.contains("func otherRootView<Identity>"))
        #expect(!result.expansion.contains("canImport"))
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
