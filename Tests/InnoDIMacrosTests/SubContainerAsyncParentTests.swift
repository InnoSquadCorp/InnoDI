import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// A sub-container child input is a synchronous value in both child scopes,
/// so an asynchronous parent member cannot feed it. Before
/// `sub.async-parent-member`, the generated child construction failed to
/// compile with an unrelated missing-member error.
@Suite("Sub-container async parent members")
struct SubContainerAsyncParentTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Input": ProvideMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "SubContainerFactory": ProvideMacro.self,
        "Multibinding": ProvideMacro.self,
    ]

    private static let asyncParent = MessageID(
        domain: "InnoDI.validation",
        id: "sub.async-parent-member"
    )

    private static let sharedParentMustNotBeTransient = MessageID(
        domain: "InnoDI.validation",
        id: "sub.shared-parent-must-not-be-transient"
    )

    private static let asyncProviders = [
        "@Provide(.shared, asyncFactory: { () async in Token() })",
        "@Provide(.transient, asyncFactory: { () async in Token() })",
        "@Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Token() })",
    ]

    @Test("Every wiring form rejects an asynchronous parent member")
    func everyWiringRejectsAsyncParents() {
        for provider in Self.asyncProviders {
            for wiring in [
                "scope: .shared",
                "scope: .transient",
                "scope: .shared, with: [\\Self.token]",
                "scope: .transient, with: [\\Self.token]",
                "scope: .shared, bindings: [(child: \\ChildContainer.value, parent: \\Self.token)]",
                "scope: .transient, bindings: [(child: \\ChildContainer.value, parent: \\Self.token)]",
            ] {
                let result = expandMacroSource(
                    """
                    @DIContainer
                    struct AppContainer {
                        \(provider)
                        var token: Token

                        @SubContainer(\(wiring))
                        var child: ChildContainer
                    }
                    """,
                    macros: Self.macros
                )
                // A shared child also cannot read a transient parent. Both
                // rules apply, and fixing only one would not compile.
                let alsoTransient = wiring.hasPrefix("scope: .shared")
                    && provider.hasPrefix("@Provide(.transient")
                let expected = alsoTransient
                    ? [Self.sharedParentMustNotBeTransient, Self.asyncParent]
                    : [Self.asyncParent]
                #expect(
                    result.diagnostics.map(\.diagnosticID) == expected,
                    Comment(rawValue: "\(provider) / \(wiring)")
                )
            }
        }
    }

    @Test("The diagnostic anchors on the parent key path")
    func diagnosticAnchorsOnParentKeyPath() throws {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async in Token() })
                var token: Token

                @SubContainer(scope: .shared, with: [\\Self.token])
                var child: ChildContainer
            }
            """,
            macros: Self.macros
        )
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.node.trimmedDescription == "\\Self.token")
        #expect(
            diagnostic.message
                == "@SubContainer 'child' cannot pass parent member 'token' to a child input because 'token' is asynchronous. Child inputs are synchronous values: wire a synchronous parent member instead, or construct the child after awaiting 'token'."
        )
    }

    @Test("A sub-container factory binding rejects an asynchronous parent member")
    func factoryBindingRejectsAsyncParents() throws {
        for provider in Self.asyncProviders {
            let result = expandMacroSource(
                """
                @DIContainer
                struct AppContainer {
                    \(provider)
                    var token: Token

                    @SubContainerFactory(
                        SessionContainer.self,
                        bindings: [(child: \\SessionContainer.value, parent: \\Self.token)]
                    )
                    var session: SessionContainer.AssistedFactory
                }
                """,
                macros: Self.macros
            )
            #expect(result.diagnostics.map(\.diagnosticID) == [Self.asyncParent], Comment(rawValue: provider))
            let diagnostic = try #require(result.diagnostics.first)
            #expect(diagnostic.node.trimmedDescription == "\\Self.token")
            #expect(
                diagnostic.message
                    == "@SubContainerFactory 'session' cannot pass parent member 'token' to a child input because 'token' is asynchronous. Child inputs are synchronous values: wire a synchronous parent member instead, or make the child input @Input(.assisted) and pass the awaited value to the factory."
            )
        }
    }

    /// Validation recovery keeps an asynchronous member's accessor
    /// synchronous whenever a sibling key path names it, so the dedicated
    /// diagnostic must stay terminal even without DAG validation.
    @Test("validateDAG: false still rejects every key path to an asynchronous member")
    func keyPathsToAsyncMembersStayRejectedWithoutDAGValidation() {
        let cases: [(wiring: String, expected: MessageID)] = [
            (
                """
                @SubContainer(scope: .shared, with: [\\Self.token])
                var child: ChildContainer
                """,
                Self.asyncParent
            ),
            (
                """
                @SubContainer(scope: .transient, bindings: [(child: \\ChildContainer.value, parent: \\Self.token)])
                var child: ChildContainer
                """,
                Self.asyncParent
            ),
            (
                """
                @SubContainerFactory(SessionContainer.self, bindings: [(child: \\SessionContainer.value, parent: \\Self.token)])
                var session: SessionContainer.AssistedFactory
                """,
                Self.asyncParent
            ),
            (
                """
                @Multibinding([\\Self.token])
                var tokens: [Token]
                """,
                MessageID(domain: "InnoDI.validation", id: "multibinding.async-contributor")
            ),
        ]
        for provider in Self.asyncProviders {
            for item in cases {
                let result = expandMacroSource(
                    """
                    @DIContainer(validateDAG: false)
                    struct AppContainer {
                        \(provider)
                        var token: Token

                        \(item.wiring)
                    }
                    """,
                    macros: Self.macros
                )
                #expect(
                    result.diagnostics.map(\.diagnosticID).contains(item.expected),
                    Comment(rawValue: "\(provider) / \(item.wiring)")
                )
            }
        }
    }

    @Test("A child can skip an asynchronous parent member")
    func childCanSkipAsyncParent() {
        for provider in Self.asyncProviders {
            let result = expandMacroSource(
                """
                @DIContainer
                struct AppContainer {
                    @Input var config: Config

                    \(provider)
                    var token: Token

                    @SubContainer(scope: .shared, with: [\\Self.config])
                    var shared: ChildContainer

                    @SubContainer(scope: .transient, with: [])
                    var transient: ChildContainer
                }
                """,
                macros: Self.macros
            )
            #expect(result.diagnostics.isEmpty, Comment(rawValue: provider))
        }
    }
}
