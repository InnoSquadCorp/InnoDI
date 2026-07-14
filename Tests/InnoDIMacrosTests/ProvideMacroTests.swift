import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Provide Macro Tests")
struct ProvideMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "InnoDI.DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
        "InnoDI.Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "InnoDI._InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
    ]

    // MARK: - Parsing tests (no expansion)

    @Test
    func parseProvideAttributes() throws {
        let source = """
        @Provide(.input)
        var bar: Int
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }

        let args = parseProvideArguments(attr)
        #expect(args.scope == .input)
        #expect(args.factoryExpr == nil)
    }

    @Test
    func parseProvideWithFactory() throws {
        let source = """
        @Provide(.shared, factory: SomeType())
        var foo: SomeProtocol
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }

        let args = parseProvideArguments(attr)
        #expect(args.scope == .shared)
        let factoryExpr = try #require(args.factoryExpr)
        #expect(factoryExpr.trimmedDescription == "SomeType()")
    }

    @Test
    func parseProvideWithTypeAndDependencies() throws {
        let source = """
        @Provide(.shared, APIClient.self, with: [\\Self.config, \\Self.logger])
        var apiClient: APIClientProtocol
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }

        let args = parseProvideArguments(attr)
        #expect(args.scope == .shared)
        #expect(args.typeExpr != nil)
        #expect(args.dependencies == ["config", "logger"])
    }

    @Test("Provide parser preserves invalid concrete: Bool")
    func parseProvideWithNonLiteralConcretePreservesInvalidState() throws {
        let source = """
        @Provide(.shared, factory: SomeType(), concrete: shouldUseConcrete)
        var foo: SomeType
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }

        let args = parseProvideArguments(attr)
        #expect(args.concrete == false)
        #expect(args.concreteParseState == .invalid)
    }

    @Test("Provide parser preserves escaping input opt-in and invalid literals")
    func parseProvideEscapingState() throws {
        let source = """
        @Provide(.input, escaping: true)
        var handler: Handler

        @Provide(.input, escaping: shouldEscape)
        var invalid: Handler
        """

        let parsed = Parser.parse(source: source)
        let declarations = parsed.statements.compactMap {
            $0.item.as(VariableDeclSyntax.self)
        }
        let firstAttribute = try #require(
            declarations.first?.attributes.first?.as(AttributeSyntax.self)
        )
        let secondAttribute = try #require(
            declarations.last?.attributes.first?.as(AttributeSyntax.self)
        )

        let valid = parseProvideArguments(firstAttribute)
        #expect(valid.escaping)
        #expect(valid.escapingParseState == .parsed(true))

        let invalid = parseProvideArguments(secondAttribute)
        #expect(!invalid.escaping)
        #expect(invalid.escapingParseState == .invalid)
    }

    @Test("Provide parser preserves invalid with: dependencies")
    func parseProvideWithNonLiteralDependenciesPreservesInvalidState() throws {
        let source = """
        @Provide(.shared, APIClient.self, with: dependencyKeyPaths)
        var apiClient: APIClientProtocol
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }

        let args = parseProvideArguments(attr)
        #expect(args.dependencies.isEmpty)
        #expect(args.dependenciesParseState == .invalid)
    }

    @Test("Closure parameter parser skips wildcard placeholders and keeps named args")
    func parseClosureParameterNamesSkipsWildcard() throws {
        let source = """
        @Provide(.transient, factory: { (_: APIClient, logger: Logger) in ViewModel(logger: logger) })
        var viewModel: ViewModel
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self),
              let closure = parseProvideArguments(attr).factoryExpr?.as(ClosureExprSyntax.self) else {
            Issue.record("Should parse transient factory closure")
            return
        }

        let parameterList = parseClosureParameterNames(closure)
        #expect(parameterList.hasWildcard == true)
        #expect(parameterList.names == ["logger"])
    }

    @Test("Closure parameter parser preserves type annotations on full parameter clauses")
    func parseClosureParameterNamesPreservesTypes() throws {
        // Soft-edge detection relies on the type annotation to identify
        // `Lazy<T>`. Shorthand closures have no type site — assert nil there.
        let source = """
        @Provide(.shared, factory: { (api: APIClient, raw) in Service(api: api, raw: raw) })
        var service: Service
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self),
              let closure = parseProvideArguments(attr).factoryExpr?.as(ClosureExprSyntax.self) else {
            Issue.record("Should parse shared factory closure")
            return
        }

        let parameterList = parseClosureParameterNames(closure)
        #expect(parameterList.names == ["api", "raw"])
        // Parameter clause form — first param carries a type annotation.
        // The parser mixes forms by taking the parameter-clause branch here,
        // where every parameter yields a TypeSyntax (even `raw` as an
        // identifier type).
        let apiType = parameterList.references.first { $0.name == "api" }?.type
        #expect(apiType?.trimmedDescription == "APIClient")
    }

    @Test("Qualified Lazy parameter preserves the written wrapper callee")
    func parseClosureParameterNamesPreservesQualifiedLazyCallee() throws {
        let source = """
        @Provide(.shared, factory: { (service: InnoDI.Lazy<Service>) in Holder(service: service) })
        var holder: Holder
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self),
              let closure = parseProvideArguments(attr).factoryExpr?.as(ClosureExprSyntax.self) else {
            Issue.record("Should parse shared factory closure")
            return
        }

        let parameterList = parseClosureParameterNames(closure)
        let serviceReference = try #require(parameterList.references.first { $0.name == "service" })
        #expect(serviceReference.type?.trimmedDescription == "InnoDI.Lazy<Service>")
        #expect(serviceReference.lazyWrapperCalleeDescription == "InnoDI.Lazy")
    }

    // MARK: - Accessor/peer expansion tests (migrated to snapshot/inline)

    @Test("Function inputs keep eager parameters and support aliased escaping values")
    func functionInputsUseSelectiveEscapingParameters() {
        assertMacroExpansionSnapshot(
            """
            typealias Handler = @Sendable () -> Void

            @DIContainer
            struct AppContainer {
                @Provide(.input, escaping: true)
                var aliasedHandler: Handler

                @Provide(.input)
                var directHandler: @Sendable () -> Void
            }
            """,
            matches: "functionInputsUseSelectiveEscapingParameters",
            macros: Self.macros
        )
    }

    @Test("escaping input configuration fails closed outside its supported type and scope")
    func escapingInputConfigurationFailsClosed() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service(), escaping: true)
                var service: any ServiceProtocol

                @Provide(.input, escaping: true)
                var optionalHandler: (@Sendable () -> Void)?

                @Provide(.input, escaping: true)
                var genericOptionalHandler: Optional<@Sendable () -> Void>

                @Provide(.input, escaping: true)
                var qualifiedOptionalHandler: Swift.Optional<@Sendable () -> Void>
            }
            """,
            expectedCodes: [
                InnoDIDiagnosticCode.provideEscapingInvalidScope.messageID,
                InnoDIDiagnosticCode.provideEscapingNonFunctionType.messageID,
                InnoDIDiagnosticCode.provideEscapingNonFunctionType.messageID,
                InnoDIDiagnosticCode.provideEscapingNonFunctionType.messageID,
            ],
            macros: Self.macros
        )
    }

    @Test("escaping requires a literal Bool")
    func escapingInputRequiresLiteralBool() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input, escaping: shouldEscape)
                var handler: Handler
            }
            """,
            expectedCodes: [InnoDIDiagnosticCode.provideBoolLiteralRequired.messageID],
            macros: Self.macros
        )
    }

    @Test("User-qualified function aliases named Optional remain supported")
    func userQualifiedOptionalFunctionAliasRemainsSupported() {
        let result = expandMacroSource(
            """
            enum Namespace {
                typealias Optional<T> = @Sendable (T) -> Void
            }

            @DIContainer
            struct AppContainer {
                @Provide(.input, escaping: true)
                var handler: Namespace.Optional<Int>
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("handler: @escaping Namespace.Optional<Int>"))
    }

    @Test("Standalone @Provide rejects a dynamic scope exactly once")
    func standaloneProvideRejectsDynamicScope() {
        assertMacroExpansionSnapshot(
            """
            struct PlainContainer {
                @Provide(ScopeChooser.shared, factory: Service(), concrete: true)
                var service: Service
            }
            """,
            matches: "standaloneProvideRejectsDynamicScope",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.usage", id: "provide.unknown-scope"),
                    message: "Unknown @Provide scope: ScopeChooser.shared.",
                    line: 2,
                    column: 14
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Transient factory closure injects dependencies by parameter name")
    func transientFactoryClosureInjectsDependenciesByParameterName() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var apiClient: APIClient

                @Provide(.transient, factory: { (apiClient: APIClient) in ViewModel(apiClient: apiClient) }, concrete: true)
                var viewModel: ViewModel
            }
            """,
            matches: "transientFactoryClosureInjectsDependenciesByParameterName",
            macros: Self.macros
        )
    }

    @Test("Transient factory closure with no parameters does not inject dependencies")
    func transientFactoryClosureWithNoParametersDoesNotInjectDependencies() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { ViewModel() }, concrete: true)
                var viewModel: ViewModel
            }
            """,
            matches: "transientFactoryClosureWithNoParametersDoesNotInjectDependencies",
            macros: Self.macros
        )
    }

    @Test("Transient factory closure injects all dependencies for multiple parameters")
    func transientFactoryClosureInjectsAllDependenciesForMultipleParameters() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var apiClient: APIClient

                @Provide(.input)
                var logger: Logger

                @Provide(.transient, factory: { (apiClient: APIClient, logger: Logger) in ViewModel(apiClient: apiClient, logger: logger) }, concrete: true)
                var viewModel: ViewModel
            }
            """,
            matches: "transientFactoryClosureInjectsAllDependenciesForMultipleParameters",
            macros: Self.macros
        )
    }

    @Test("Transient type factory with with: injects dependencies via accessors")
    func transientTypeFactoryWithDependenciesUsesAccessorInjection() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, ViewModel.self, with: [\\Self.config], concrete: true)
                var viewModel: ViewModel
            }
            """,
            matches: "transientTypeFactoryWithDependenciesUsesAccessorInjection",
            macros: Self.macros
        )
    }

    @Test("Transient factory closure with underscore parameter emits diagnostic")
    func transientFactoryClosureWithUnderscoreParameterEmitsDiagnostic() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var logger: Logger

                @Provide(.transient, factory: { (_: APIClient, logger: Logger) in ViewModel(logger: logger) }, concrete: true)
                var viewModel: ViewModel
            }
            """

        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [
                InnoDIDiagnosticCode.transientFactoryUnnamedParameters.messageID,
            ],
            macros: Self.macros
        )
    }

    @Test("Transient accessor avoids generating broken self references for unknown parameters")
    func transientFactoryClosureWithUnknownParameterFallsBackToFatalErrorGetter() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var apiClient: APIClient

                @Provide(.transient, factory: { (missing: APIClient) in ViewModel(apiClient: missing) }, concrete: true)
                var viewModel: ViewModel
            }
            """

        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [InnoDIDiagnosticCode.provideUnresolvedFactoryParameter.messageID],
            macros: Self.macros
        )
    }

    @Test("validateDAG: false transient factory misses still emit terminal InnoDI diagnostic")
    func validateDAGFalseTransientFactoryMissingParameterEmitsDiagnostic() {
        let source = """
            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.input)
                var apiClient: APIClient

                @Provide(.transient, factory: { (missing: APIClient) in ViewModel(apiClient: missing) }, concrete: true)
                var viewModel: ViewModel
            }
            """

        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [InnoDIDiagnosticCode.provideUnresolvedFactoryParameter.messageID],
            macros: Self.macros
        )
        assertMacroExpansionSnapshot(
            source,
            matches: "validateDAGFalseTransientFactoryMissingParameterEmitsDiagnostic",
            diagnostics: [
                DiagnosticSpec(
                    id: InnoDIDiagnosticCode.provideUnresolvedFactoryParameter.messageID,
                    message: "Factory parameter 'missing' for 'viewModel' does not match any injectable container member.",
                    line: 6,
                    column: 38,
                    severity: .error,
                    notes: [
                        NoteSpec(
                            message: "Rename the factory parameter to match an injectable member name, or switch to explicit wiring inside the factory body.",
                            line: 6,
                            column: 5
                        ),
                        NoteSpec(
                            message: "'viewModel' can only inject members declared in the container by exact member name.",
                            line: 7,
                            column: 9
                        ),
                    ]
                )
            ],
            macros: Self.macros
        )
    }

    // MARK: - Eliminated-fatalError reproduce tests (Phase 2.B)
    //
    // The five sites in `ProvideMacro.swift` that previously synthesized
    // a `fatalErrorGetter(...)` are tracked in
    // `docs/internal/fatalerror-inventory.md`. After Phase 2.B these
    // tests assert two things:
    //   1) The user-facing diagnostic is still emitted at error severity.
    //   2) The macro expansion no longer contains a `fatalError(` call —
    //      malformed input fails to compile on the primary diagnostic while
    //      an unreachable recovery accessor suppresses structural follow-ons.

    @Test("Async transient factory with underscore parameter emits diagnostic without trap")
    func asyncTransientFactoryClosureWithUnderscoreParameterEmitsDiagnostic() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var apiClient: APIClient

                @Provide(.transient, asyncFactory: { (_: APIClient) async in await ViewModel.load() }, concrete: true)
                var viewModel: ViewModel
            }
            """

        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [
                InnoDIDiagnosticCode.transientFactoryUnnamedParameters.messageID,
            ],
            macros: Self.macros
        )
        assertMacroExpansionSnapshot(
            source,
            matches: "asyncTransientFactoryClosureWithUnderscoreParameterEmitsDiagnostic",
            diagnostics: [
                DiagnosticSpec(
                    id: InnoDIDiagnosticCode.transientFactoryUnnamedParameters.messageID,
                    message: "Factory closure parameters must be named for injection.",
                    line: 6,
                    column: 5,
                    severity: .error
                ),
            ],
            macros: Self.macros
        )
    }

    @Test("Transient with no factory, no typeExpr, no initializer emits diagnostic without trap")
    func transientMissingFactoryEmitsDiagnostic() {
        // No `factory:`, no `Type.self` typeExpr, no inline initializer.
        // Site #4 in the inventory. The container emits the terminal
        // diagnostic and the generated accessor owner takes its recovery path
        // without duplicating the error.
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, concrete: true)
                var viewModel: ViewModel
            }
            """

        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [
                InnoDIDiagnosticCode.provideTransientFactoryRequired.messageID,
            ],
            macros: Self.macros
        )
        assertMacroExpansionSnapshot(
            source,
            matches: "transientMissingFactoryEmitsDiagnostic",
            diagnostics: [
                DiagnosticSpec(
                    id: InnoDIDiagnosticCode.provideTransientFactoryRequired.messageID,
                    message: "@Provide(.transient) requires factory: <expr>, type: Type.self, or property initializer.",
                    line: 3,
                    column: 5,
                    severity: .error
                ),
            ],
            macros: Self.macros
        )
    }

    @Test("Transient with unresolved factory parameter emits diagnostic without trap (site #1)")
    func transientWithUnresolvedFactoryParameterEmitsDiagnostic() {
        // Site #1 in the inventory. The container owns the terminal
        // diagnostic and the generated transient accessor takes the
        // non-observing recovery path instead of synthesizing a fatalError
        // getter.
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var apiClient: APIClient

                @Provide(.transient, factory: { (missing: APIClient) in ViewModel(apiClient: missing) }, concrete: true)
                var viewModel: ViewModel
            }
            """

        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [InnoDIDiagnosticCode.provideUnresolvedFactoryParameter.messageID],
            macros: Self.macros
        )
        assertMacroExpansionSnapshot(
            source,
            matches: "transientWithUnresolvedFactoryParameterEmitsDiagnostic",
            diagnostics: [
                DiagnosticSpec(
                    id: InnoDIDiagnosticCode.provideUnresolvedFactoryParameter.messageID,
                    message: "Factory parameter 'missing' for 'viewModel' does not match any injectable container member.",
                    line: 6,
                    column: 38,
                    severity: .error,
                    notes: [
                        NoteSpec(
                            message: "Rename the factory parameter to match an injectable member name, or switch to explicit wiring inside the factory body.",
                            line: 6,
                            column: 5
                        ),
                        NoteSpec(
                            message: "'viewModel' can only inject members declared in the container by exact member name.",
                            line: 7,
                            column: 9
                        ),
                    ]
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Async transient factory generates async accessor")
    func asyncTransientFactoryGeneratesAsyncAccessor() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var apiClient: APIClient

                @Provide(.transient, asyncFactory: { (apiClient: APIClient) async in await ViewModel.load(apiClient: apiClient) }, concrete: true)
                var viewModel: ViewModel
            }
            """,
            matches: "asyncTransientFactoryGeneratesAsyncAccessor",
            macros: Self.macros
        )
    }

    @Test("Container mainActor option applies MainActor to dependency property")
    func mainActorContainerAppliesMainActorToAccessor() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.transient, factory: Service(), concrete: true)
                var service: Service
            }
            """,
            matches: "mainActorContainerAppliesMainActorToAccessor",
            macros: Self.macros
        )
    }

    // MARK: - Peer + generated-accessor dual-phase verification
    //
    // This test intentionally calls the public peer macro and compiler-owned
    // accessor macro separately to verify the Task storage peer declaration is
    // paired with the async getter.

    @Test("Async shared factory generates task storage peer and async getter")
    func asyncSharedFactoryGeneratesTaskStorageAndAsyncGetter() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, asyncFactory: { () async in Service() }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        let generatedAttributeSource = Parser.parse(
            source: "@InnoDI._InnoDIProvideAccessor(recovery: false) var value: Int"
        )
        guard let containerDecl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let varDecl = containerDecl.memberBlock.members.first?.decl.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self),
              let generatedVariable = generatedAttributeSource.statements.first?.item.as(VariableDeclSyntax.self),
              let generatedAttribute = generatedVariable.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse a direct @Provide member with async shared factory closure")
            return
        }

        let context = TestMacroExpansionContext()
        let peerDecls = try ProvideMacro.expansion(
            of: attr,
            providingPeersOf: varDecl,
            in: context
        )
        let accessors = try InnoDIProvideAccessorMacro.expansion(
            of: generatedAttribute,
            providingAccessorsOf: varDecl,
            in: context
        )

        let peerGenerated = peerDecls.map(\.description).joined(separator: "\n")
        let accessorGenerated = accessors.map(\.description).joined(separator: "\n")
        #expect(peerGenerated == "private var _storage_task_service: Task<Service, Never>? = nil")
        #expect(accessorGenerated == #"getasync{return await _storage_task_service!.value}"#)
    }

    @Test("Qualified InnoDI provide members resolve transient dependencies by member name")
    func qualifiedProvideMembersResolveTransientDependencies() throws {
        let source = """
        @InnoDI.DIContainer
        struct AppContainer {
            @InnoDI.Provide(.input)
            var logger: Logger

            @InnoDI.Provide(.transient, factory: { (logger: Logger) in ViewModel(logger: logger) }, concrete: true)
            var viewModel: ViewModel
        }
        """

        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [],
            macros: Self.macros
        )

        let parsed = Parser.parse(source: source)
        let generatedAttributeSource = Parser.parse(
            source: "@InnoDI._InnoDIProvideAccessor(recovery: false) var value: Int"
        )
        guard let containerDecl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let transientDecl = containerDecl.memberBlock.members.last?.decl.as(VariableDeclSyntax.self),
              let generatedVariable = generatedAttributeSource.statements.first?.item.as(VariableDeclSyntax.self),
              let generatedAttribute = generatedVariable.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse qualified container with transient provide member")
            return
        }

        let context = TestMacroExpansionContext()
        let accessors = try InnoDIProvideAccessorMacro.expansion(
            of: generatedAttribute,
            providingAccessorsOf: transientDecl,
            in: context
        )

        let accessorGenerated = accessors.map(\.description).joined(separator: "\n")
        #expect(context.diagnostics.isEmpty)
        #expect(!accessorGenerated.contains("fatalError"))
        #expect(accessorGenerated.contains("self.logger"))
    }

    // MARK: - Public API presence

    @Test("Public Provide macro declaration allows async shared task storage peers")
    func provideMacroDeclarationIncludesStorageTaskPrefix() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = fileURL
            .deletingLastPathComponent() // InnoDIMacrosTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Package root

        let publicAPISource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/InnoDI/InnoDI.swift"),
            encoding: .utf8
        )

        #expect(publicAPISource.contains("prefixed(_storage_task_)"))
    }
}
