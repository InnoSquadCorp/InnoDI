import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Multibinding prototype")
struct MultibindingPrototypeMacroTests {
    private static let macros: [String: any Macro.Type] =
        DIContainerMacroTests.macros.merging([
            "_InnoDIMultibindingPrototype": InnoDIMultibindingPrototypeMacro.self,
        ]) { current, _ in current }

    @Test("Contributor order and common type produce one deterministic collection")
    func generatesOrderedCollection() {
        let result = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: ["auth", "logging"])
            @DIContainer
            public struct NetworkContainer {
                @Provide(.shared, factory: Auth()) public var auth: any Interceptor
                @Provide(.transient, factory: Logging()) public var logging: any Interceptor
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("@_spi(Experimental)"))
        #expect(
            result.expansion.contains(
                "public var _innoDIMultibindingPrototype: [any Interceptor]"
            )
        )
        let authIndex = result.expansion.range(of: "self.auth")?.lowerBound
        let loggingIndex = result.expansion.range(of: "self.logging")?.lowerBound
        #expect(authIndex != nil)
        #expect(loggingIndex != nil)
        if let authIndex, let loggingIndex {
            #expect(authIndex < loggingIndex)
        }
    }

    @Test("Contributor names must resolve uniquely and expose one written type")
    func rejectsUnknownAndMismatchedMembers() {
        let unknown = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: ["missing"])
            @DIContainer
            struct UnknownContainer {
                @Provide(.shared, factory: Auth()) var auth: any Interceptor
            }
            """,
            macros: Self.macros
        )
        let mismatch = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: ["auth", "logger"])
            @DIContainer
            struct MismatchedContainer {
                @Provide(.shared, factory: Auth()) var auth: any Interceptor
                @Provide(.shared, factory: Logger()) var logger: Logger
            }
            """,
            macros: Self.macros
        )

        #expect(unknown.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.experimental",
                id: "multibinding-prototype.unknown-member"
            ),
        ])
        #expect(mismatch.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.experimental",
                id: "multibinding-prototype.type-mismatch"
            ),
        ])
    }

    @Test("Contributor lists are nonempty, literal, unique, and synchronous")
    func rejectsInvalidListsAndAsyncMembers() {
        let empty = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: [])
            @DIContainer
            struct EmptyContainer {
                @Provide(.shared, factory: Auth()) var auth: any Interceptor
            }
            """,
            macros: Self.macros
        )
        let nonliteral = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: [String()])
            @DIContainer
            struct NonliteralContainer {
                @Provide(.shared, factory: Auth()) var auth: any Interceptor
            }
            """,
            macros: Self.macros
        )
        let duplicate = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: ["auth", "auth"])
            @DIContainer
            struct DuplicateContainer {
                @Provide(.shared, factory: Auth()) var auth: any Interceptor
            }
            """,
            macros: Self.macros
        )
        let asynchronous = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: ["auth"])
            @DIContainer
            struct AsyncContainer {
                @Provide(.shared, asyncFactory: { () async in Auth() })
                var auth: any Interceptor
            }
            """,
            macros: Self.macros
        )

        #expect(empty.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.experimental",
                id: "multibinding-prototype.empty-members"
            ),
        ])
        #expect(nonliteral.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.experimental",
                id: "multibinding-prototype.invalid-members"
            ),
        ])
        #expect(duplicate.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.experimental",
                id: "multibinding-prototype.duplicate-member"
            ),
        ])
        #expect(asynchronous.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.experimental",
                id: "multibinding-prototype.async-member"
            ),
        ])
    }

    @Test("Prototype requires a DI container declaration")
    func rejectsInvalidDeclaration() {
        let missingContainer = expandMacroSource(
            """
            @_InnoDIMultibindingPrototype(members: ["auth"])
            struct PlainType {}
            """,
            macros: Self.macros
        )

        #expect(missingContainer.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.experimental",
                id: "multibinding-prototype.requires-container"
            ),
        ])
    }
}
