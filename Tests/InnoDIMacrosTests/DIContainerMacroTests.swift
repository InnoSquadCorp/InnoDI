import Foundation
import InnoDICore
import InnoDITestSupport
import SwiftParser
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("DIContainer Macro Tests")
struct DIContainerMacroTests {
    /// Shared across the base suite and its SubContainer-focused extension.
    static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "InnoDI.DIContainer": DIContainerMacro.self,
        "DIComponent": DIComponentMacro.self,
        "DIHierarchyRoot": DIHierarchyRootMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "InnoDI._InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "InnoDI._InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
    ]

    @Test("A flagless concrete shared dependency keeps its declared storage type")
    func flaglessConcreteSharedDependencyGeneratesStorage() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("var apiClient: APIClient"))
        #expect(result.expansion.contains("init(apiClient: APIClient? = nil)"))
        #expect(result.expansion.contains("self._storage_apiClient = apiClient ?? APIClient()"))
    }

    @Test("A flagless concrete transient dependency keeps its declared override type")
    func flaglessConcreteTransientDependencyGeneratesOverride() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("var apiClient: APIClient"))
        #expect(result.expansion.contains("init(apiClient: APIClient? = nil)"))
        #expect(result.expansion.contains("self._override_apiClient = apiClient"))
    }

    @Test("A flagless optional concrete dependency keeps its declared optional type")
    func flaglessOptionalConcreteDependencyGeneratesStorage() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient?
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("var apiClient: APIClient?"))
        #expect(result.expansion.contains("self._storage_apiClient = apiClient ?? APIClient()"))
    }

    @Test("Explicit any protocol shared dependency keeps existential storage")
    func anyProtocolSharedDependencyKeepsExistentialStorage() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: any APIClientProtocol
            }
            """,
            matches: "anyProtocolSharedDependency",
            macros: Self.macros
        )
    }

    @Test("Optional any protocol shared dependency keeps optional existential storage")
    func optionalAnyProtocolSharedDependencyKeepsOptionalExistentialStorage() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: (any APIClientProtocol)?
            }
            """,
            matches: "optionalAnyProtocolSharedDependency",
            macros: Self.macros
        )
    }

    @Test("Opaque some protocol provider types are rejected")
    func someProtocolProviderTypeIsRejected() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared)
                var apiClient: some APIClientProtocol = APIClient()
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.opaque-type-unsupported"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Protocol composition shared dependency keeps composition storage")
    func compositionSharedDependencyKeepsCompositionStorage() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClientProtocol & LoggerProtocol
            }
            """,
            matches: "compositionSharedDependency",
            macros: Self.macros
        )
    }

    @Test("package containers propagate package access to generated APIs")
    func packageContainerGeneratesPackageAPIs() {
        assertMacroExpansionInline(
            """
            @DIContainer
            package struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            expandedSource: """
                package struct AppContainer {
                    @InnoDI._InnoDIProvideAccessor(recovery: false)
                    var apiClient: APIClient

                    // MARK: - Initialization
                    package init(apiClient: APIClient? = nil) {
                        self._storage_apiClient = apiClient ?? APIClient()
                    }

                    // MARK: - Overrides Builder
                    package struct Overrides {
                        package var apiClient: APIClient? = nil
                    }

                    package typealias _InnoDIMountOverrides = Overrides

                    // MARK: - Convenience Init with Overrides
                    package init(_ _innoDIApplyOverrides: (inout Overrides) -> Void) {
                        var _innoDIOverrides = Self.Overrides()
                        _innoDIApplyOverrides(&_innoDIOverrides)
                        self.init(apiClient: _innoDIOverrides.apiClient)
                    }

                    // MARK: - withOverrides
                    package static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (throws)
                    package static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return try _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (async)
                    package nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return await _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (async throws)
                    package nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return try await _innoDIOperation(_innoDIContainer)
                    }
                }
                """,
            macros: Self.macros
        )
    }

    @Test
    func sharedMembersStillRequireFactories() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared)
                var service: any ServiceProtocol
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.shared-factory-required")
            ],
            macros: Self.macros
        )
    }

    @Test
    func inputMembersStillRejectFactoryConfiguration() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input, factory: Service())
                var service: any ServiceProtocol
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration")
            ],
            macros: Self.macros
        )
    }

    @Test("input scope rejects type-based dependency wiring")
    func inputScopeRejectsWithDependencies() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.input, APIClient.self, with: [\\Self.config])
                var apiClient: APIClient
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration"),
            ],
            macros: Self.macros
        )
    }

    @Test
    func detectsContainerDependencyCycle() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { (serviceB: ServiceB) in
                    ServiceA(serviceB: serviceB)
                })
                var serviceA: ServiceA

                @Provide(.transient, factory: { (serviceA: ServiceA) in
                    ServiceB(serviceA: serviceA)
                })
                var serviceB: ServiceB
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.dependency-cycle")
            ],
            macros: Self.macros
        )
    }

    @Test
    func detectsUnknownDependencyInWithClause() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, APIClient.self, with: [\\Self.missing])
                var apiClient: APIClient
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")
            ],
            macros: Self.macros
        )
    }

}
