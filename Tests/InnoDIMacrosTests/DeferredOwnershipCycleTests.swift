import InnoDITestSupport
import SwiftDiagnostics
import Testing

@testable import InnoDIMacros

extension DIContainerMacroTests {
    @Test("Deferred self-reference is rejected even with graph diagnostics disabled",
          arguments: ["Lazy", "InnoDI.Lazy", "Provider", "InnoDI.Provider"], [true, false])
    func deferredSelfCycle(wrapper: String, validateDAG: Bool) {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(validateDAG: \(validateDAG))
            struct Container {
                @Provide(.transient, factory: { (a: \(wrapper)<A>) in A(a: a) })
                var a: A
            }
            """,
            expectedCodes: [MessageID(domain: "InnoDI.validation", id: "container.dependency-cycle")],
            macros: Self.macros
        )
    }

    @Test("Mixed Provider and Lazy cycle is rejected before creating resolver cells",
          arguments: [true, false])
    func mixedDeferredCycle(validateDAG: Bool) {
        let result = expandMacroSource(
            """
            @DIContainer(validateDAG: \(validateDAG))
            struct Container {
                @Input var token: Token
                @Provide(.shared, factory: { (token: Token, b: InnoDI.Provider<B>) in A(token: token, b: b) })
                var a: A
                @Provide(.transient, factory: { (token: Token, a: InnoDI.Lazy<A>) in B(token: token, a: a) })
                var b: B
            }
            """,
            macros: Self.macros
        )
        #expect(result.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.dependency-cycle")
        })
    }
}
