import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Assisted factory")
struct AssistedFactoryMacroTests {
    private static let macros: [String: any Macro.Type] =
        DIContainerMacroTests.macros.merging([
            "AssistedFactory": AssistedFactoryMacro.self,
            "SubContainerFactory": ProvideMacro.self,
        ]) { _, new in new }

    @Test("factory owns static inputs and accepts assisted inputs")
    func expandsTypedFactoryMembers() {
        let result = expandMacroSource(
            """
            @AssistedFactory(
                Child.self,
                static: [\\Child.repository],
                assisted: [\\Child.sessionID]
            )
            public struct AssistedFactory {}
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("private let repository: Child._InnoDIInputType_repository"))
        #expect(result.expansion.contains("public init(repository: Child._InnoDIInputType_repository)"))
        #expect(result.expansion.contains("sessionID: Child._InnoDIInputType_sessionID"))
        #expect(result.expansion.contains("repository: self.repository"))
        #expect(result.expansion.contains("sessionID: sessionID"))
    }

    @Test("factory input partition must match the child declaration")
    func rejectsMismatchedPartition() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct Child {
                @Input var repository: Repository
                @Input(.assisted) var sessionID: Int

                @AssistedFactory(
                    Child.self,
                    static: [\\Child.sessionID],
                    assisted: [\\Child.repository]
                )
                struct AssistedFactory {}
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.validation",
                    id: "assisted-factory.input-partition-mismatch"
                )
            )
        )
    }
}
