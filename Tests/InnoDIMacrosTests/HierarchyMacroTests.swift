import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Hierarchy Macro Tests")
struct HierarchyMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "DIComponent": DIComponentMacro.self,
        "DIHierarchyRoot": DIHierarchyRootMacro.self,
        "InnoDI.DIContainer": DIContainerMacro.self,
        "InnoDI.DIHierarchyRoot": DIHierarchyRootMacro.self,
        "Provide": ProvideMacro.self,
        "SubContainer": SubContainerMacro.self,
    ]

    @Test("DIComponent generates a dependency contract and mountable conformance")
    func diComponentGeneratesDependencyContract() {
        assertMacroExpansionInline(
            """
            @DIComponent
            @DIContainer
            public struct FeatureContainer {
                @Provide(.input) public var config: FeatureConfig
                @Provide(.shared, factory: FeatureService()) public var service: any FeatureServiceProtocol
            }
            """,
            expandedSource: """
                public struct FeatureContainer {
                    public var config: FeatureConfig {
                        get {
                            return _storage_config
                        }
                    }
                
                    private let _storage_config: FeatureConfig
                    public var service: any FeatureServiceProtocol {
                        get {
                            return _storage_service
                        }
                    }

                    private let _storage_service: any FeatureServiceProtocol

                    // MARK: - Initialization
                    public init(
                        dependencies: any FeatureContainerDependencies,
                        _ applyOverrides: (inout Overrides) -> Void = { _ in
                        }
                    ) {
                        self.init(config: dependencies.config, applyOverrides)
                    }

                    public init(config: FeatureConfig, service: (any FeatureServiceProtocol)? = nil) {
                        self._storage_config = config
                        self._storage_service = service ?? FeatureService()
                    }

                    // MARK: - Overrides Builder
                    public struct Overrides {
                        public var service: (any FeatureServiceProtocol)? = nil
                    }

                    // MARK: - Convenience Init with Overrides
                    public init(config: FeatureConfig, _ applyOverrides: (inout Overrides) -> Void) {
                        var overrides = Overrides()
                        applyOverrides(&overrides)
                        self.init(config: config, service: overrides.service)
                    }

                    // MARK: - withOverrides
                    public static func withOverrides<OperationResult>(config: FeatureConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
                        let container = Self(config: config, applyOverrides)
                        return operation(container)
                    }

                    // MARK: - withOverrides (throws)
                    public static func withOverrides<OperationResult>(config: FeatureConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
                        let container = Self(config: config, applyOverrides)
                        return try operation(container)
                    }

                    // MARK: - withOverrides (async)
                    public static func withOverrides<OperationResult>(config: FeatureConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
                        let container = Self(config: config, applyOverrides)
                        return await operation(container)
                    }

                    // MARK: - withOverrides (async throws)
                    public static func withOverrides<OperationResult>(config: FeatureConfig, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
                        let container = Self(config: config, applyOverrides)
                        return try await operation(container)
                    }
                }

                public protocol FeatureContainerDependencies {
                    var config: FeatureConfig {
                        get
                    }
                }

                extension FeatureContainer: _InnoDIComponentMountable {
                    typealias _InnoDIComponentDependencies = any FeatureContainerDependencies
                    typealias _InnoDIComponentOverrides = Overrides
                }
                """,
            macros: Self.macros
        )
    }

    @Test("DIComponent requires DIContainer")
    func diComponentRequiresContainer() {
        assertMacroExpansionInline(
            """
            @DIComponent
            struct FeatureContainer {
                let config: FeatureConfig
            }
            """,
            expandedSource: """
                struct FeatureContainer {
                    let config: FeatureConfig
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "component.requires-container"),
                    message: "@DIComponent can only be attached to a type that also declares @DIContainer.",
                    line: 1,
                    column: 1
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIHierarchyRoot requires DIContainer")
    func diHierarchyRootRequiresContainer() {
        assertMacroExpansionInline(
            """
            @DIHierarchyRoot
            struct AppRoot {
            }
            """,
            expandedSource: """
                struct AppRoot {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "hierarchy-root.requires-container"),
                    message: "@DIHierarchyRoot can only be attached to a type that also declares @DIContainer.",
                    line: 1,
                    column: 1
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIComponent accepts qualified DIContainer attributes")
    func diComponentAcceptsQualifiedDIContainerAttribute() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIComponent
            @InnoDI.DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: FeatureConfig
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("DIComponent rejects foreign qualified DIContainer attributes")
    func diComponentRejectsForeignQualifiedDIContainerAttribute() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIComponent
            @OtherDI.DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: FeatureConfig
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "component.requires-container")
            ],
            macros: Self.macros
        )
    }

    @Test("DIHierarchyRoot accepts qualified DIContainer attributes")
    func diHierarchyRootAcceptsQualifiedDIContainerAttribute() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIHierarchyRoot
            @InnoDI.DIContainer
            struct AppRoot {
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("DIHierarchyRoot rejects foreign qualified DIContainer attributes")
    func diHierarchyRootRejectsForeignQualifiedDIContainerAttribute() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIHierarchyRoot
            @OtherDI.DIContainer
            struct AppRoot {
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "hierarchy-root.requires-container")
            ],
            macros: Self.macros
        )
    }
}
