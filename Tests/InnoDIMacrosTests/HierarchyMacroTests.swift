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
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "InnoDI._InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
    ]

    @Test("DIComponent suppresses every companion expansion after a reserved qualifier diagnostic")
    func componentReservedQualifierFailsClosed() {
        let result = expandMacroSource(
            """
            struct Swift {
                @DIComponent
                @DIContainer(mainActor: true)
                struct FeatureContainer {
                    @Provide(.input) var config: FeatureConfig
                }
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "container.reserved-module-name"
                )
            ]
        )
        #expect(!result.expansion.contains("FeatureContainerDependencies"))
        #expect(!result.expansion.contains("_InnoDIMainActorComponentMountable"))
        #expect(!result.expansion.contains("dependencies:"))
    }

    @Test("DIComponent suppresses every companion expansion for an invalid container")
    func componentInvalidContainerFailsClosed() {
        let unmanaged = expandMacroSource(
            """
            @DIComponent
            @DIContainer
            struct UnmanagedComponent {
                var rawState = 0
            }
            """,
            macros: Self.macros
        )

        #expect(
            unmanaged.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "container.unmanaged-stored-property"
                )
            ]
        )
        #expect(!unmanaged.expansion.contains("UnmanagedComponentDependencies"))
        #expect(!unmanaged.expansion.contains("_InnoDIComponentMountable"))
        #expect(!unmanaged.expansion.contains("dependencies _innoDIDependencies"))

        let customInitializer = expandMacroSource(
            """
            @DIComponent
            @DIContainer
            struct CustomInitComponent {
                @Provide(.input) var config: String

                init(config: String) {
                    self.config = config
                }
            }
            """,
            macros: Self.macros
        )

        #expect(
            customInitializer.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "container.custom-init-unsupported"
                )
            ]
        )
        #expect(!customInitializer.expansion.contains("_InnoDIProvideAccessor"))
        #expect(!customInitializer.expansion.contains("CustomInitComponentDependencies"))
        #expect(!customInitializer.expansion.contains("_InnoDIComponentMountable"))
        #expect(!customInitializer.expansion.contains("dependencies _innoDIDependencies"))
    }

    @Test("DIComponent suppresses companion expansions after model validation fails")
    func componentValidatorFailureFailsClosed() {
        let result = expandMacroSource(
            """
            @DIComponent
            @DIContainer
            struct InvalidSubComponent {
                @SubContainer
                var child: ChildContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "sub.scope-required"
                )
            ]
        )
        #expect(!result.expansion.contains("InvalidSubComponentDependencies"))
        #expect(!result.expansion.contains("_InnoDIComponentMountable"))
        #expect(!result.expansion.contains("dependencies _innoDIDependencies"))
    }

    @Test("DIComponent and DIContainer each own one Overrides conflict diagnostic")
    func componentOverridesConflictHasStableRoleOwnership() {
        let result = expandMacroSource(
            """
            @DIComponent
            @DIContainer
            struct ConflictingComponent {
                struct Overrides {}
            }
            """,
            macros: Self.macros
        )

        let diagnosticIDs = result.diagnostics.map(\.diagnosticID)
        #expect(diagnosticIDs.count == 2)
        #expect(
            diagnosticIDs.filter {
                $0 == MessageID(
                    domain: "InnoDI.validation",
                    id: "container.overrides-name-conflict"
                )
            }.count == 1
        )
        #expect(
            diagnosticIDs.filter {
                $0 == MessageID(
                    domain: "InnoDI.validation",
                    id: "component.overrides-builder-required"
                )
            }.count == 1
        )
        #expect(!result.expansion.contains("ConflictingComponentDependencies"))
        #expect(!result.expansion.contains("_InnoDIComponentMountable"))
        #expect(!result.expansion.contains("dependencies _innoDIDependencies"))
    }

    @Test("DIHierarchyRoot suppresses conformance after a reserved qualifier diagnostic")
    func hierarchyRootReservedQualifierFailsClosed() {
        let result = expandMacroSource(
            """
            struct Swift {
                @DIHierarchyRoot
                @DIContainer
                struct RootContainer {
                    @Provide(.input) var value: Int
                }
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "container.reserved-module-name"
                )
            ]
        )
        #expect(!result.expansion.contains("_InnoDIHierarchyRoot"))
    }

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
                    @InnoDI._InnoDIProvideAccessor(recovery: false) public var service: any FeatureServiceProtocol

                    // MARK: - Initialization
                    public init(
                        dependencies _innoDIDependencies: any FeatureContainerDependencies,
                        _ _innoDIApplyOverrides: (inout Overrides) -> Void = { _ in
                        }
                    ) {
                        self.init(config: _innoDIDependencies.config, _innoDIApplyOverrides)
                    }

                    public init(config: FeatureConfig, service: (any FeatureServiceProtocol)? = nil) {
                        self._storage_config = config
                        self._storage_service = service ?? FeatureService()
                    }

                    // MARK: - Overrides Builder
                    public struct Overrides {
                        public var service: (any FeatureServiceProtocol)? = nil
                    }

                    public typealias _InnoDIMountOverrides = Overrides

                    // MARK: - Convenience Init with Overrides
                    public init(config: FeatureConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
                        var _innoDIOverrides = Self.Overrides()
                        _innoDIApplyOverrides(&_innoDIOverrides)
                        self.init(config: config, service: _innoDIOverrides.service)
                    }

                    // MARK: - withOverrides
                    public static func withOverrides<OperationResult>(config: FeatureConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
                        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
                        return _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (throws)
                    public static func withOverrides<OperationResult>(config: FeatureConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
                        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
                        return try _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (async)
                    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: FeatureConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
                        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
                        return await _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (async throws)
                    public nonisolated(nonsending) static func withOverrides<OperationResult>(config: FeatureConfig, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
                        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
                        return try await _innoDIOperation(_innoDIContainer)
                    }
                }

                public protocol FeatureContainerDependencies {
                    var config: FeatureConfig {
                        get
                    }
                }

                extension FeatureContainer: InnoDI._InnoDIComponentMountable {
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
                == "InnoDI._InnoDIMainActorComponentMountable"
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
        #expect(dependencies.attributes.trimmedDescription == "@Swift.MainActor")
        #expect(initializer.attributes.trimmedDescription == "@Swift.MainActor")
        #expect(
            initializer.signature.parameterClause.parameters.last?.type.trimmedDescription
                == "@Swift.MainActor (inout Overrides) -> Void"
        )
        #expect(
            mountableConformance.type.trimmedDescription
                == "InnoDI._InnoDIMainActorComponentMountable"
        )
    }

    @Test("Hierarchy macros module-qualify every runtime marker")
    func hierarchyMacrosModuleQualifyRuntimeMarkers() throws {
        let source = Parser.parse(
            source: """
                @DIHierarchyRoot
                @DIContainer
                struct AppContainer {}
                """
        )
        let root = try #require(
            source.statements.first?.item.as(StructDeclSyntax.self)
        )
        let attribute = try #require(
            root.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()

        let extensions = try DIHierarchyRootMacro.expansion(
            of: attribute,
            attachedTo: root,
            providingExtensionsOf: TypeSyntax(stringLiteral: "AppContainer"),
            conformingTo: [],
            in: context
        )

        #expect(context.diagnostics.isEmpty)
        #expect(extensions.count == 1)
        #expect(
            extensions.first?.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription
                == "InnoDI.DIHierarchyRootMarker"
        )
    }

    @Test("DIComponent escaped target diagnostic belongs only to the peer role")
    func componentEscapedTargetHasStableRoleOwnership() throws {
        let source = Parser.parse(
            source: """
                @DIComponent
                @DIContainer
                struct `default` {
                    @Provide(.input) var value: Int
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
            providingExtensionsOf: TypeSyntax(stringLiteral: "`default`"),
            conformingTo: [],
            in: context
        )

        #expect(peers.isEmpty)
        #expect(members.isEmpty)
        #expect(extensions.isEmpty)
        #expect(context.diagnostics.count == 1)
        #expect(
            context.diagnostics.first?.diagnosticID
                == MessageID(
                    domain: "InnoDI.usage",
                    id: "component.escaped-target-unsupported"
                )
        )
        #expect(
            context.diagnostics.first?.message
                == "@DIComponent target 'default' cannot use a backtick-escaped identifier. Rename it to an unescaped Swift identifier so the generated dependency protocol has a canonical name."
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
