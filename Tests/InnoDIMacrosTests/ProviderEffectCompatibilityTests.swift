import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Provider effect compatibility")
struct ProviderEffectCompatibilityTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "InnoDI.DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
        "InnoDI.Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "InnoDI._InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
    ]

    private static let requiresAsync = MessageID(
        domain: "InnoDI.validation",
        id: "provide.async-dependency-requires-async-consumer"
    )
    private static let requiresThrowing = MessageID(
        domain: "InnoDI.validation",
        id: "provide.throwing-dependency-requires-throwing-consumer"
    )
    private static let withRequiresSynchronousProvider = MessageID(
        domain: "InnoDI.validation",
        id: "provide.with-dependency-requires-synchronous-provider"
    )
    private static let duplicateFactoryParameter = MessageID(
        domain: "InnoDI.validation",
        id: "provide.duplicate-factory-parameter"
    )
    private static let duplicateMemberName = MessageID(
        domain: "InnoDI.validation",
        id: "container.duplicate-member-name"
    )
    private static let escapedIdentifierUnsupported = MessageID(
        domain: "InnoDI.usage",
        id: "provide.escaped-identifier-unsupported"
    )

    @Test("A synchronous closure consumer rejects an async provider")
    func syncClosureConsumerRejectsAsyncProvider() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.shared, factory: { (token: Token) in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            expectedCodes: [Self.requiresAsync],
            macros: Self.macros
        )
    }

    @Test("A synchronous closure consumer gets one complete diagnostic for an async-throwing provider")
    func syncClosureConsumerRejectsAsyncThrowingProvider() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async throws -> Token in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.shared, factory: { (token: Token) in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            expectedCodes: [Self.requiresAsync],
            macros: Self.macros
        )
    }

    @Test("An async nonthrowing closure consumer rejects an async-throwing provider")
    func asyncClosureConsumerRejectsThrowingProvider() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async throws -> Token in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.shared, asyncFactory: { (token: Token) async in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            expectedCodes: [Self.requiresThrowing],
            macros: Self.macros
        )
    }

    @Test("Type-based with wiring rejects async providers")
    func withDependencyRejectsAsyncProvider() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.shared, Session.self, with: [\\Self.token], concrete: true)
                var session: Session
            }
            """,
            expectedCodes: [Self.withRequiresSynchronousProvider],
            macros: Self.macros
        )
    }


    @Test("Transient closure consumers enforce async provider effects")
    func syncTransientConsumerRejectsAsyncProvider() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.transient, factory: { (token: Token) in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            expectedCodes: [Self.requiresAsync],
            macros: Self.macros
        )
    }

    @Test("Invalid transient effects expand a recovery accessor")
    func invalidTransientEffectExpandsRecoveryAccessor() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.transient, factory: { (token: Token) in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 1
        )
    }

    @Test("Transient with wiring emits recovery for an async dependency")
    func transientWithDependencyExpandsRecoveryAccessor() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.transient, Session.self, with: [\\Self.token], concrete: true)
                var session: Session
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.count == 1)
        #expect(
            result.diagnostics.first?.diagnosticID == Self.withRequiresSynchronousProvider
        )
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 2
        )
    }


    @Test("Transient async consumers enforce throwing provider effects")
    func asyncTransientConsumerRejectsThrowingProvider() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { () async throws -> Token in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.transient, asyncFactory: { (token: Token) async in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            expectedCodes: [Self.requiresThrowing],
            macros: Self.macros
        )
    }

    @Test("Lazy rejects async transient targets")
    func lazyRejectsAsyncTransientTarget() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (token: Lazy<Token>) in
                    Session(token: token)
                }, concrete: true)
                var session: Session

                @Provide(.transient, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.lazy-unsupported-target")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider effects remain mandatory when DAG validation is disabled")
    func validateDAGFalseStillEnforcesProviderEffects() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token

                @Provide(.shared, factory: { (token: Token) in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            expectedCodes: [Self.requiresAsync],
            macros: Self.macros
        )
    }

    @Test("Invalid providers do not create derived consumer effect diagnostics")
    func invalidProviderDoesNotCreateDerivedEffectDiagnostic() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input, asyncFactory: { () async in Token() }, concrete: true)
                var token: Token

                @Provide(.transient, factory: { (token: Token) in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.input-invalid-configuration"
                ),
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.async-factory-invalid-scope"
                ),
            ]
        )
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 2
        )
    }

    @Test("S, A, and AT providers compose only into compatible consumers")
    func validProviderEffectMatrixProducesNoDiagnostics() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Seed(), concrete: true)
                var seed: Seed

                @Provide(.shared, factory: { (seed: Seed) in
                    SyncValue(seed: seed)
                }, concrete: true)
                var syncValue: SyncValue

                @Provide(.shared, asyncFactory: { (seed: Seed) async in
                    AsyncValue(seed: seed)
                }, concrete: true)
                var asyncValue: AsyncValue

                @Provide(.shared, asyncFactory: { (asyncValue: AsyncValue) async in
                    AsyncConsumer(value: asyncValue)
                }, concrete: true)
                var asyncConsumer: AsyncConsumer

                @Provide(.shared, asyncFactory: { (syncValue: SyncValue) async throws -> ThrowingValue in
                    ThrowingValue(value: syncValue)
                }, concrete: true)
                var throwingValue: ThrowingValue

                @Provide(.shared, asyncFactory: { (asyncValue: AsyncValue) async throws -> ThrowingFromAsync in
                    ThrowingFromAsync(value: asyncValue)
                }, concrete: true)
                var throwingFromAsync: ThrowingFromAsync

                @Provide(.transient, asyncFactory: { (throwingValue: ThrowingValue) async throws -> ThrowingConsumer in
                    ThrowingConsumer(value: throwingValue)
                }, concrete: true)
                var throwingConsumer: ThrowingConsumer
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("A nested non-container @Provide fails with the direct-member diagnostic")
    func nestedNonContainerProvideFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { () async in
                    Token()
                }, concrete: true)
                var token: Token

                struct Helper {
                    @Provide(.transient, factory: { (token: Token) in
                        Session(token: token)
                    }, concrete: true)
                    var session: Session
                }
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.count == 1)
        #expect(
            result.diagnostics.first?.diagnosticID == MessageID(
                domain: "InnoDI.usage",
                id: "provide.requires-direct-container-member"
            )
        )
        let helperStart = result.expansion.range(of: "struct Helper")?.lowerBound
        #expect(helperStart != nil)
        if let helperStart {
            let helperExpansion = result.expansion[helperStart...]
            #expect(!helperExpansion.contains("_InnoDIProvideAccessor"))
            #expect(!helperExpansion.contains("preconditionFailure"))
            #expect(helperExpansion.contains("var session: Session"))
        }
    }

    @Test("Every @Provide scope requires a direct container member")
    func allProvideScopesRequireDirectContainerMember() {
        let directMemberCode = MessageID(
            domain: "InnoDI.usage",
            id: "provide.requires-direct-container-member"
        )
        assertMacroExpansionDiagnosticCodes(
            """
            struct PlainDependencies {
                @Provide(.input)
                var input: Input

                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service

                @Provide(.transient, factory: Request(), concrete: true)
                var request: Request

                @Provide(.input)
                static var staticInput: Input
            }
            """,
            expectedCodes: [
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
            ],
            macros: Self.macros
        )
    }

    @Test("A local @Provide inside a container method is not a direct member")
    func localProvideInsideContainerMethodFailsClosed() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                func makeService() {
                    @Provide(.shared, factory: Service(), concrete: true)
                    var localService: Service
                    _ = localService
                }
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.requires-direct-container-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("@Provide requires a plain stored instance var")
    func provideRejectsUnsupportedStorageDeclarations() {
        let directMemberCode = MessageID(
            domain: "InnoDI.usage",
            id: "provide.requires-direct-container-member"
        )
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                let immutable: Int

                @Provide(.shared, factory: 42, concrete: true)
                var computed: Int { 42 }

                @Provide(.shared, factory: 42, concrete: true)
                lazy var lazyValue: Int = 42

                @Provide(.input)
                weak var weakValue: Service?

                @Provide(.input)
                unowned var unownedValue: Service

                @Provide(.shared, factory: 42, concrete: true)
                var observed: Int {
                    didSet {}
                }

                @Provide(.input)
                private(set) var restrictedValue: Int

                @Box
                @Provide(.shared, factory: 42, concrete: true)
                var wrappedValue: Int

                @BoxActor
                @Provide(.shared, factory: 42, concrete: true)
                var actorNamedWrapperValue: Int

                @MainActor
                @Provide(.shared, factory: 42, concrete: true)
                var sourceWrittenMainActorValue: Int

                #if os(macOS)
                @Box
                #endif
                @Provide(.shared, factory: 42, concrete: true)
                var conditionalWrapperValue: Int

                @Provide(.shared, factory: 42, concrete: true)
                class var classValue: Int { 42 }
            }
            """,
            expectedCodes: [
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
                directMemberCode,
            ],
            macros: Self.macros
        )
    }

    @Test("Unsafe binding shapes keep specific diagnostics and skip hidden accessors")
    func unsafeBindingShapesSkipHiddenAccessors() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var (first, second): (Int, Int)

                @Provide(.shared, concrete: true)
                var inferred = 42

                @Provide(.input)
                var one: Int, two: Int
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "SwiftSyntaxMacroExpansion",
                    id: "peerMacroOnVariableWithMultipleBindings"
                ),
                MessageID(domain: "InnoDI.usage", id: "provide.named-property-required"),
                MessageID(domain: "InnoDI.usage", id: "provide.explicit-type-required"),
                MessageID(domain: "InnoDI.usage", id: "provide.single-binding"),
            ]
        )
        #expect(!result.expansion.contains("_InnoDIProvideAccessor"))
    }

    @Test("Conditionally compiled providers fail closed before peer or accessor generation")
    func conditionallyCompiledProviderFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                #if os(macOS)
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service
                #endif
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.conditional-declaration-unsupported"
                )
            ]
        )
        #expect(!result.expansion.contains("_storage_service"))
        #expect(!result.expansion.contains("_InnoDIProvideAccessor"))
    }

    @Test("Duplicate Provide attributes fail before peer storage generation")
    func duplicateProvideAttributesFailClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: 42, concrete: true)
                @Provide(.shared, factory: 42, concrete: true)
                var value: Int = 0
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(domain: "InnoDI.usage", id: "provide.duplicate-attribute")
            ]
        )
        #expect(!result.expansion.contains("_storage_value"))
        #expect(!result.expansion.contains("_InnoDIProvideAccessor"))
    }

    @Test("Duplicate provider names diagnose once and suppress generated peers")
    func duplicateProviderNamesFailClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var duplicatedValue: Int

                @Provide(.input)
                var duplicatedValue: Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [Self.duplicateMemberName])
        #expect(!result.expansion.contains("_storage_duplicatedValue"))
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 2
        )
    }

    @Test("MainActor duplicate provider names suppress generated peers")
    func mainActorDuplicateProviderNamesFailClosed() {
        let result = expandMacroSource(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input)
                var duplicatedMainActorValue: Int

                @Provide(.input)
                var duplicatedMainActorValue: Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [Self.duplicateMemberName])
        #expect(!result.expansion.contains("_storage_duplicatedMainActorValue"))
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 2
        )
    }

    @Test("A static provider with the same spelling does not suppress an instance peer")
    func staticProviderDoesNotCreateFalseDuplicateRecovery() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                static var value: Int = 0

                @Provide(.input)
                var value: Int
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.requires-direct-container-member"
                )
            ]
        )
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: false)"
            ).count - 1 == 1
        )
    }

    @Test("An invalid static peer keeps its own diagnostic beside instance duplicates")
    func staticProviderKeepsDiagnosticBesideInstanceDuplicates() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                static var duplicatedValue: Int = 0

                @Provide(.input)
                var duplicatedValue: Int

                @Provide(.input)
                var duplicatedValue: Int
            }
            """,
            macros: Self.macros
        )

        #expect(
            Set(result.diagnostics.map(\.diagnosticID)) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.requires-direct-container-member"
                ),
                Self.duplicateMemberName,
            ]
        )
        #expect(result.diagnostics.count == 2)
        #expect(!result.expansion.contains("_storage_duplicatedValue"))
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 2
        )
    }

    @Test("Duplicate factory parameter names fail closed for every dependency kind")
    func duplicateFactoryParameterNamesFailClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (hardValue: Int, hardValue: Int) in 0 }, concrete: true)
                var hardConsumer: Int

                @Provide(.shared, factory: { (lazyValue: Lazy<Int>, lazyValue: Lazy<Int>) in 0 }, concrete: true)
                var lazyConsumer: Int

                @Provide(.shared, factory: { (providerValue: Provider<Int>, providerValue: Provider<Int>) in 0 }, concrete: true)
                var providerConsumer: Int

                @Provide(.shared, factory: { (mixedValue: Int, mixedValue: Lazy<Int>) in 0 }, concrete: true)
                var mixedConsumer: Int
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == Array(
                repeating: Self.duplicateFactoryParameter,
                count: 4
            )
        )
        for memberName in [
            "hardConsumer",
            "lazyConsumer",
            "providerConsumer",
            "mixedConsumer",
        ] {
            #expect(!result.expansion.contains("_storage_\(memberName)"))
        }
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 4
        )
    }

    @Test("Escaped provider property identifiers fail closed")
    func escapedProviderPropertyIdentifierFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var `default`: Int
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                Self.escapedIdentifierUnsupported
            ]
        )
        #expect(!result.expansion.contains("_storage_"))
        #expect(result.expansion.contains("@InnoDI._InnoDIProvideAccessor(recovery: true)"))
    }

    @Test("Escaped/plain factory parameter spellings fail closed before lookup")
    func escapedFactoryParameterIdentifierFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(
                    .shared,
                    factory: { (dependency: Int, `dependency`: Int) in 0 },
                    concrete: true
                )
                var consumer: Int
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                Self.escapedIdentifierUnsupported
            ]
        )
        #expect(!result.expansion.contains("_storage_consumer"))
        #expect(result.expansion.contains("@InnoDI._InnoDIProvideAccessor(recovery: true)"))
    }

    @Test("Duplicate Provide attributes fail closed outside containers")
    func standaloneDuplicateProvideAttributesFailClosed() {
        let result = expandMacroSource(
            """
            struct Plain {
                @Provide(.input)
                @Provide(.input)
                var value: Int

                struct Nested {
                    @Provide(.input)
                    @Provide(.input)
                    var nestedValue: Int
                }
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(domain: "InnoDI.usage", id: "provide.duplicate-attribute"),
                MessageID(domain: "InnoDI.usage", id: "provide.duplicate-attribute"),
            ]
        )
        #expect(!result.expansion.contains("_storage_value"))
        #expect(!result.expansion.contains("_storage_nestedValue"))
    }

    @Test("Foreign qualified attributes cannot impersonate InnoDI wrappers")
    func foreignQualifiedProvideWrapperFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Other.Provide
                @Provide(.input)
                var value: Int
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.requires-direct-container-member"
                )
            ]
        )
        #expect(!result.expansion.contains("_storage_value"))
        #expect(!result.expansion.contains("_InnoDIProvideAccessor"))
    }

    @Test("Implicitly unwrapped optional provider types fail closed")
    func implicitlyUnwrappedOptionalProviderFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var service: Service!
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(domain: "InnoDI.validation", id: "provide.iuo-type-unsupported")
            ]
        )
        #expect(!result.expansion.contains("_storage_service"))
        #expect(!result.expansion.contains("_InnoDIProvideAccessor"))
    }

    @Test("Provide with wiring requires root-qualified key paths")
    func unqualifiedProvideWithFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, Service.self, with: [\\.config], concrete: true)
                var service: Service
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.invalid-with-dependencies"
                )
            ]
        )
        #expect(!result.expansion.contains("_storage_service"))
    }

    @Test("Provide with wiring rejects a different key-path root")
    func foreignRootProvideWithFailsClosed() {
        let result = expandMacroSource(
            """
            struct OtherRoot {
                var config: Config
            }

            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, Service.self, with: [\\OtherRoot.config], concrete: true)
                var service: Service
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.invalid-with-dependencies"
                )
            ]
        )
        #expect(!result.expansion.contains("_storage_service"))
    }

    @Test("Provide with wiring requires a direct member key path")
    func nestedProvideWithFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var holder: Holder

                @Provide(.input)
                var values: [Config]

                @Provide(.shared, Service.self, with: [\\Self.holder.config], concrete: true)
                var nested: Service

                @Provide(.shared, Service.self, with: [\\Self.values[0]], concrete: true)
                var subscripted: Service
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(domain: "InnoDI.validation", id: "provide.invalid-with-dependencies"),
                MessageID(domain: "InnoDI.validation", id: "provide.invalid-with-dependencies"),
            ]
        )
        #expect(!result.expansion.contains("_storage_nested"))
        #expect(!result.expansion.contains("_storage_subscripted"))
    }

    @Test("Partially invalid with wiring still recovers an async key-path target")
    func partiallyInvalidWithRecoversAsyncTarget() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async in Token() }, concrete: true)
                var token: Token

                @Provide(
                    .shared,
                    Session.self,
                    with: [\\Self.token, Paths.other],
                    concrete: true
                )
                var session: Session
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.invalid-with-dependencies"
                )
            ]
        )
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 2
        )
    }

    @Test("Invalid construction sources do not create derived cycle diagnostics")
    func invalidConstructionSourceDoesNotCreateCycleDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(
                    .transient,
                    A.self,
                    with: [\\Self.b],
                    factory: { (b: B) in A(b: b) },
                    concrete: true
                )
                var a: A

                @Provide(
                    .transient,
                    factory: { (a: A) in B(a: a) },
                    concrete: true
                )
                var b: B
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.construction-source-conflict"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Invalid custom actor providers are excluded from transient recovery wiring")
    func actorConflictForcesTransientRecoveryAcrossSiblingEdges() {
        let result = expandMacroSource(
            """
            @globalActor
            actor FeatureActor {
                static let shared = FeatureActor()
            }

            @DIContainer(mainActor: true)
            struct AppContainer {
                @FeatureActor
                @Provide(.transient, asyncFactory: { () async in Token() }, concrete: true)
                var token: Token

                @Provide(.transient, factory: { (token: Token) in
                    Session(token: token)
                }, concrete: true)
                var session: Session
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.count == 1)
        #expect(
            result.diagnostics.first?.diagnosticID == MessageID(
                domain: "InnoDI.validation",
                id: "container.mainactor-conflict"
            )
        )
        #expect(
            result.expansion.components(
                separatedBy: "@InnoDI._InnoDIProvideAccessor(recovery: true)"
            ).count - 1 == 1
        )
    }

    @Test("The compiler-support provider accessor rejects an invalid owner")
    func provideAccessorRejectsInvalidOwner() throws {
        let parsed = Parser.parse(
            source: """
            struct ForgedAccessor {
                @InnoDI._InnoDIProvideAccessor(recovery: true)
                var value: Int
            }
            """
        )
        let forgedType = try #require(
            parsed.statements.first?.item.as(StructDeclSyntax.self)
        )
        let variable = try #require(
            forgedType.memberBlock.members.first?.decl.as(VariableDeclSyntax.self)
        )
        let attribute = try #require(
            variable.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()

        let accessors = try InnoDIProvideAccessorMacro.expansion(
            of: attribute,
            providingAccessorsOf: variable,
            in: context
        )

        #expect(context.diagnostics.count == 1)
        #expect(
            context.diagnostics.first?.diagnosticID == MessageID(
                domain: "InnoDI.usage",
                id: "provide.generated-accessor-manual-attachment"
            )
        )
        #expect(accessors.count == 1)
        #expect(accessors.first?.description.contains("Invalid generated @Provide accessor owner") == true)
    }

    @Test("Forged recovery cannot suppress standalone Provide diagnostics")
    func forgedRecoveryCannotSuppressStandaloneProvideDiagnostics() throws {
        let parsed = Parser.parse(
            source: """
            struct Plain {
                @InnoDI._InnoDIProvideAccessor(recovery: true)
                @Provide(.input)
                var value: Int
            }
            """
        )
        let plain = try #require(
            parsed.statements.first?.item.as(StructDeclSyntax.self)
        )
        let variable = try #require(
            plain.memberBlock.members.first?.decl.as(VariableDeclSyntax.self)
        )
        let accessorAttribute = try #require(
            variable.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()

        let accessors = try InnoDIProvideAccessorMacro.expansion(
            of: accessorAttribute,
            providingAccessorsOf: variable,
            in: context
        )

        #expect(
            context.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.generated-accessor-manual-attachment"
                )
            ]
        )
        #expect(accessors.count == 1)
        #expect(
            accessors.first?.description.contains(
                "Invalid generated @Provide accessor owner"
            ) == true
        )

        assertMacroExpansionDiagnosticCodes(
            parsed.description,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.requires-direct-container-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Container owns one diagnostic for a forged accessor without Provide")
    func containerOwnsForgedAccessorDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @InnoDI._InnoDIProvideAccessor(recovery: true)
                var value: Int
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.generated-accessor-manual-attachment"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Direct providers reject manually attached compiler-support accessors")
    func directProvidersRejectManualAccessorAttachment() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @InnoDI._InnoDIProvideAccessor(recovery: false)
                @Provide(.transient, factory: 42, concrete: true)
                var transientValue: Int

                @InnoDI._InnoDIProvideAccessor(recovery: false)
                @Provide(.shared, factory: 42, concrete: true)
                var sharedValue: Int

                @InnoDI._InnoDIProvideAccessor(recovery: flag)
                @Provide(.input)
                var inputValue: Int
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.generated-accessor-manual-attachment"
                ),
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.generated-accessor-manual-attachment"
                ),
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.generated-accessor-manual-attachment"
                ),
            ],
            macros: Self.macros
        )
    }

}
