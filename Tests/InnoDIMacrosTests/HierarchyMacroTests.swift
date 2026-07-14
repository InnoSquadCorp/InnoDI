import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
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
                    @InnoDI._InnoDIProvideAccessor(recovery: false) public var config: FeatureConfig
                
                    private var _storage_config: FeatureConfig? = nil
                    @InnoDI._InnoDIProvideAccessor(recovery: false) public var service: any FeatureServiceProtocol

                    private var _storage_service: (any FeatureServiceProtocol)? = nil

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
                    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: FeatureConfig, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
                        let container = Self(config: config, applyOverrides)
                        return await operation(container)
                    }

                    // MARK: - withOverrides (async throws)
                    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: FeatureConfig, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
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
                    public typealias _InnoDIComponentDependencies = any FeatureContainerDependencies
                    public typealias _InnoDIComponentOverrides = Overrides
                }
                """,
            macros: Self.macros
        )
    }

    @Test("DIComponent qualifies a multi-level nested actor-isolated dependency contract")
    func diComponentQualifiesNestedDependencyContract() throws {
        let source = Parser.parse(
            source: """
                struct Outer {
                    struct Middle {
                        @DIComponent
                        @DIContainer(mainActor: true)
                        struct FeatureContainer {
                            @Provide(.input) var config: String
                        }
                    }
                }
                """
        )
        let outer = try #require(
            source.statements.first?.item.as(StructDeclSyntax.self)
        )
        let middle = try #require(
            outer.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        let component = try #require(
            middle.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        let attribute = try #require(
            component.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()

        let extensions = try DIComponentMacro.expansion(
            of: attribute,
            attachedTo: component,
            providingExtensionsOf: TypeSyntax(stringLiteral: "Outer.Middle.FeatureContainer"),
            conformingTo: [],
            in: context
        )

        #expect(context.diagnostics.isEmpty)
        let extensionDecl = try #require(extensions.first)
        let generated = extensionDecl.trimmedDescription
        #expect(extensions.count == 1)
        #expect(
            extensionDecl.extendedType.trimmedDescription == "Outer.Middle.FeatureContainer"
        )
        #expect(
            generated.contains(
                "typealias _InnoDIComponentDependencies = any Outer.Middle.FeatureContainerDependencies"
            )
        )
        #expect(
            extensionDecl.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription
                == "_InnoDIMainActorComponentMountable"
        )
    }

    @Test("DIComponent propagates MainActor isolation across its generated contract")
    func diComponentPropagatesMainActorIsolation() throws {
        let source = Parser.parse(
            source: """
                @DIComponent
                @DIContainer(mainActor: true)
                public struct FeatureContainer {
                    @Provide(.input) public var config: String
                }
                """
        )
        let component = try #require(
            source.statements.first?.item.as(StructDeclSyntax.self)
        )
        let attribute = try #require(
            component.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()

        let peers = try DIComponentMacro.expansion(
            of: attribute,
            providingPeersOf: component,
            in: context
        )
        let members = try DIComponentMacro.expansion(
            of: attribute,
            providingMembersOf: component,
            in: context
        )
        let extensions = try DIComponentMacro.expansion(
            of: attribute,
            attachedTo: component,
            providingExtensionsOf: TypeSyntax(stringLiteral: "FeatureContainer"),
            conformingTo: [],
            in: context
        )

        #expect(context.diagnostics.isEmpty)
        let dependencies = try #require(
            peers.first?.as(ProtocolDeclSyntax.self)
        )
        let initializer = try #require(
            members.first?.as(InitializerDeclSyntax.self)
        )
        let mountableConformance = try #require(
            extensions.first?.inheritanceClause?.inheritedTypes.first
        )

        #expect(peers.count == 1)
        #expect(members.count == 1)
        #expect(extensions.count == 1)
        #expect(dependencies.attributes.trimmedDescription == "@MainActor")
        #expect(initializer.attributes.trimmedDescription == "@MainActor")
        #expect(
            initializer.signature.parameterClause.parameters.last?.type.trimmedDescription
                == "@MainActor (inout Overrides) -> Void"
        )
        #expect(
            mountableConformance.type.trimmedDescription
                == "_InnoDIMainActorComponentMountable"
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
                MessageID(
                    domain: "InnoDI.usage",
                    id: "provide.requires-direct-container-member"
                ),
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
