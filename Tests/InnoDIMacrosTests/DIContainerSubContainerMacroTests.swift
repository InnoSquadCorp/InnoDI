import Foundation
import InnoDICore
import InnoDITestSupport
import SwiftParser
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Child-container contracts stay in the parent suite while remaining
/// navigable independently from provider and container-core behavior.
extension DIContainerMacroTests {
    // MARK: - @SubContainer

    @Test("`.shared` sub-container auto-matches parent members into the child init")
    func subContainerSharedAutoMatch() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerSharedAutoMatch",
            macros: Self.macros
        )
    }

    @Test("@SubContainer(featureRoot:) generates the default SwiftUI root helper")
    func subContainerFeatureRootGeneratesDefaultHelper() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            public struct AppContainer {
                @Provide(.input) public var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.config], featureRoot: FeatureRootScene.self)
                public var feature: FeatureContainer
            }
            """,
            matches: "subContainerFeatureRootGeneratesDefaultHelper",
            macros: Self.macros
        )
    }

    @Test("mainActor: true propagates to generated SwiftUI root helpers")
    func mainActorSubContainerFeatureRootPropagatesIsolation() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(mainActor: true)
            public struct AppContainer {
                @Provide(.input) public var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.config], featureRoot: FeatureRootScene.self)
                public var feature: FeatureContainer
            }
            """,
            matches: "mainActorSubContainerFeatureRootPropagatesIsolation",
            macros: Self.macros
        )
    }

    @Test("@SubContainer(featureRoots:) generates default and aliased SwiftUI root helpers")
    func subContainerFeatureRootsGenerateDefaultAndAliasHelpers() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            public struct AppContainer {
                @Provide(.input) public var config: AppConfig

                @SubContainer(
                    scope: .transient,
                    with: [\\.config],
                    featureRoots: [
                        FeatureRoot(FeatureRootScene.self),
                        FeatureRoot(FeatureShellScene.self, as: "featureShell")
                    ]
                )
                public var feature: FeatureContainer
            }
            """,
            matches: "subContainerFeatureRootsGenerateDefaultAndAliasHelpers",
            macros: Self.macros
        )
    }

    @Test("`.transient` sub-container binds a build closure captured from a self snapshot")
    func subContainerTransientBuildsFreshChild() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .transient)
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerTransientBuildsFreshChild",
            macros: Self.macros
        )
    }

    @Test("@SubContainer featureRoots rejects duplicate default roots")
    func subContainerFeatureRootsRejectDuplicateDefaults() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.config],
                    featureRoot: FeatureRootScene.self,
                    featureRoots: [
                        FeatureRoot(FeatureShellScene.self)
                    ]
                )
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-duplicate-default")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer featureRoots rejects invalid aliases")
    func subContainerFeatureRootsRejectInvalidAliases() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.config],
                    featureRoots: [
                        FeatureRoot(FeatureRootScene.self, as: "for")
                    ]
                )
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-invalid-alias")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer feature roots reject helper name conflicts")
    func subContainerFeatureRootRejectsHelperNameConflict() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                func featureRootView() -> ExistingRoot { fatalError() }

                @SubContainer(scope: .shared, with: [\\.config], featureRoot: FeatureRootScene.self)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-helper-name-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports explicit child/parent input remapping via bindings:")
    func subContainerSharedExplicitBindings() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            matches: "subContainerSharedExplicitBindings",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports key-path same-label subset wiring")
    func subContainerSharedWithSubset() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [\\.config])
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerSharedWithSubset",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports explicit empty with wiring")
    func subContainerSharedWithEmptySubset() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [])
                var feature: EmptyFeatureContainer
            }
            """,
            matches: "subContainerSharedWithEmptySubset",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports explicit empty bindings wiring")
    func subContainerSharedWithEmptyBindings() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, bindings: [])
                var feature: EmptyFeatureContainer
            }
            """,
            matches: "subContainerSharedWithEmptyBindings",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports multiple bindings remapping different child/parent pairs")
    func subContainerSharedBindingsMultipleRemaps() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.input) var apiService: any APIClientProtocol
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(
                    scope: .shared,
                    bindings: [
                        (child: \\.featureConfig, parent: \\.config),
                        (child: \\.apiClient, parent: \\.apiService),
                        (child: \\.featureLogger, parent: \\.logger)
                    ]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            matches: "subContainerSharedBindingsMultipleRemaps",
            macros: Self.macros
        )
    }

    @Test("`.transient` sub-container supports explicit child/parent input remapping via bindings:")
    func subContainerTransientExplicitBindings() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .transient,
                    bindings: [(child: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            matches: "subContainerTransientExplicitBindings",
            macros: Self.macros
        )
    }

    @Test("Container with only @SubContainer still generates init and Overrides")
    func subContainerOnlyParentGeneratesInitAndOverrides() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerOnlyParentGeneratesInitAndOverrides",
            macros: Self.macros
        )
    }

    @Test("@SubContainer with both with: and bindings: emits sub.bindings-conflicts-with-with")
    func subContainerBindingsConflictWithWithDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.config],
                    bindings: [(child: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.bindings-conflicts-with-with")
            ],
            macros: Self.macros
        )
    }

    @Test("Invalid child wiring suppresses container support but keeps valid async peers")
    func invalidChildWiringKeepsValidAsyncPeerSupport() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var value: Int

                @Provide(asyncFactory: { () async -> Int in 1 })
                var asyncValue: Int

                @SubContainer(
                    scope: .transient,
                    with: [\\.value],
                    bindings: [(child: \\.value, parent: \\.value)]
                )
                var invalidChild: Child
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.validation",
                id: "sub.bindings-conflicts-with-with"
            )
        ])
        #expect(result.expansion.contains(
            "@InnoDI._InnoDIProvideAccessor(recovery: false)\n"
                + "    var asyncValue: Int"
        ))
        #expect(result.expansion.contains(
            "@InnoDI._InnoDISubContainerAccessor(recovery: true)\n"
                + "    var invalidChild: Child"
        ))
        #expect(!result.expansion.contains("_innoDISubBuild_invalidChild"))
        #expect(!result.expansion.contains("InnoDI.DeferredCell"))
    }

    @Test("@SubContainer with: requires a literal key-path array")
    func subContainerWithVariableDiagnosesInvalidSameNameWiring() {
        assertMacroExpansionDiagnosticCodes(
            """
            let keyPaths = [\\AppContainer.config]

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: keyPaths)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-same-name-wiring")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with: rejects partially computed literal arrays")
    func subContainerWithComputedElementDiagnosesInvalidSameNameWiring() {
        assertMacroExpansionDiagnosticCodes(
            """
            func makeKeyPath() -> Any { fatalError() }

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [\\.config, makeKeyPath()])
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-same-name-wiring")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: requires a literal tuple key-path array")
    func subContainerBindingsVariableDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            let explicitBindings = [(child: \\FeatureBindingsContainer.featureConfig, parent: \\AppContainer.config)]

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, bindings: explicitBindings)
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: rejects malformed tuple entries")
    func subContainerBindingsMalformedTupleDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, bindings: [(child: \\.featureConfig)])
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: rejects duplicate labels inside a tuple")
    func subContainerBindingsDuplicateTupleLabelDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.input) var fallbackConfig: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureConfig, child: \\.fallbackConfig)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: rejects unknown labels inside a tuple")
    func subContainerBindingsUnknownTupleLabelDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(source: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer duplicate child bindings emit sub.duplicate-child-binding")
    func subContainerDuplicateChildBindingDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.input) var fallbackConfig: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [
                        (child: \\.featureConfig, parent: \\.config),
                        (child: \\.featureConfig, parent: \\.fallbackConfig)
                    ]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.duplicate-child-binding")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with bindings: + non-literal with: prefers bindings-conflict diagnostic")
    func subContainerBindingsConflictPrecedesInvalidWiringDiagnoses() {
        // Locks the precedence ordering when both sub.bindings-conflicts-with-with
        // and sub.invalid-same-name-wiring would otherwise fire on the same
        // attribute. The validator suppresses the invalid-same-name-wiring
        // diagnostic when bindings-conflict is already emitted (see
        // DIContainerValidator's `hasBindingWiringConflict` guard).
        assertMacroExpansionDiagnosticCodes(
            """
            let keyPaths = [\\AppContainer.config]

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: keyPaths,
                    bindings: [(child: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.bindings-conflicts-with-with")
            ],
            macros: Self.macros
        )
    }

    @Test("Generated implementation bindings use the canonical InnoDI namespace")
    func generatedImplementationBindingsUseCanonicalNamespace() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct FeatureContainer {}

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(
                    .shared,
                    asyncFactory: { (config: AppConfig) async in Service(config: config) },
                )
                var service: Service

                @Provide(
                    .shared,
                    factory: { (request: Lazy<Request>) in Consumer(request: request) },
                )
                var consumer: Consumer

                @Provide(.transient, factory: Request())
                var request: Request

                @SubContainer(scope: .transient, with: [])
                var feature: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        for generatedName in [
            "_innoDIResolved_config",
            "_innoDITask_service",
            "_innoDILazyCell_request",
            "_innoDILazySelf",
            "_innoDISubBuildCell_feature",
            "_innoDILazySelfForSub",
            "_innoDIApplyOverrides",
            "_innoDIOverrides",
            "_innoDIOperation",
            "_innoDIContainer",
        ] {
            #expect(result.expansion.contains(generatedName))
        }
        for obsoleteName in [
            "let _resolved_config =",
            "let _task_service:",
            "_lazyCell_request",
            "_subBuildCell_feature",
            "let _lazySelf =",
            "let _lazySelfForSub =",
        ] {
            #expect(!result.expansion.contains(obsoleteName))
        }
    }

    @Test("validateDAG false emits typed fallback wrappers for unresolved deferred dependencies")
    func validateDAGFalseSupportsUnresolvedDeferredWrappers() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct ChildContainer {}

            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(
                    .shared,
                    factory: { (missingLazy: Lazy<Int>) in Service() },
                )
                var lazyService: Service

                @Provide(
                    .shared,
                    factory: { (missingProvider: Provider<Int>) in Service() },
                )
                var providerService: Service

                @Provide(
                    .shared,
                    asyncFactory: { (missingAsyncLazy: Lazy<Int>) async in Service() },
                )
                var asyncLazyService: Service

                @Provide(
                    .shared,
                    asyncFactory: { (missingAsyncProvider: Provider<Int>) async in Service() },
                )
                var asyncProviderService: Service

                @SubContainer(scope: .shared, with: [])
                var child: ChildContainer
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("internal.codegen-invariant"))
        for name in [
            "missingLazy",
            "missingProvider",
            "missingAsyncLazy",
            "missingAsyncProvider",
        ] {
            #expect(
                result.expansion.contains(
                    "InnoDI._innoDITrap(\"InnoDI could not resolve dependency '\(name)'"
                )
            )
        }
        #expect(result.expansion.contains("_storage_sub_child"))
    }

    @Test("unmanaged stored container state fails closed before initializer synthesis")
    func unmanagedStoredContainerMembersDiagnose() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                let token: Int
                var count = 0
                var observed = 0 { didSet {} }

                #if os(macOS)
                var conditional = "macOS"
                #endif

                static var shared = 0
                var computed: Int { 42 }

                @Provide(.input)
                var config: String
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == Array(
                repeating: MessageID(
                    domain: "InnoDI.usage",
                    id: "container.unmanaged-stored-property"
                ),
                count: 4
            )
        )
        #expect(!result.expansion.contains("init("))
        #expect(!result.expansion.contains("_storage_config"))
        #expect(!result.expansion.contains("struct Overrides"))
    }

    @Test("Former generated-local prefixes remain valid provider names")
    func formerGeneratedLocalPrefixesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var _resolved_config: Int
                @Provide(.input) var _task_service: Int
                @Provide(.input) var _lazyCell_request: Int
                @Provide(.input) var _subBuildCell_feature: Int
                @Provide(.input) var _lazySelf: Int
                @Provide(.input) var _lazySelfForSub: Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
    }

    @Test("Container members starting with canonical reserved prefixes are rejected")
    func containerReservedNamePrefixDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var _storage_config: AppConfig
                @Provide(.input) var _override_config: AppConfig
                @Provide(.input) var _innoDIConfig: AppConfig
                @Provide(.input) var _InnoDIConfig: AppConfig
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix")
            ],
            macros: Self.macros
        )
    }

    @Test("Managed member named InnoDI cannot shadow generated runtime support")
    func containerReservedModuleNameDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var InnoDI: AppConfig
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name")
            ],
            macros: Self.macros
        )
    }

    @Test("Direct nested types cannot shadow generated module qualifiers")
    func containerReservedNestedModuleNamesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                struct Swift {}
                enum _Concurrency {}
                typealias InnoDI = Int

                @Provide(.input) var config: AppConfig
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name")
            ],
            macros: Self.macros
        )
    }

    @Test("Container and enclosing nominal names cannot shadow generated module qualifiers")
    func containerReservedScopeModuleNamesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct Swift {
                @DIContainer
                struct FirstContainer {
                    @Provide(.input) var value: Int
                }
            }

            enum _Concurrency {
                @DIContainer
                struct SecondContainer {
                    @Provide(.input) var value: Int
                }
            }

            @DIContainer
            struct InnoDI {
                @Provide(.input) var value: Int
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
            ],
            macros: Self.macros
        )
    }

    @Test("Value members named Swift or _Concurrency remain available")
    func containerModuleValueNamesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input) var Swift: Int
                @Provide(.input) var _Concurrency: Int

                @Provide(
                    .shared,
                    asyncFactory: { () async in 1 },
                )
                var asyncValue: Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("@_Concurrency.MainActor"))
        #expect(result.expansion.contains("_Concurrency.Task<Int, Swift.Never>"))
    }

    @Test("Plain direct declarations also honor reserved generated prefixes")
    func plainDirectDeclarationsHonorReservedPrefixes() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                struct _InnoDIHelper {}
                func _innoDIHelper() {}
                var _storage_probe: Int { 0 }
                typealias _override_Alias = Int
                #if DEBUG
                typealias _innoDIConditional = Int
                #endif
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer member starting with reserved prefix emits container.reserved-name-prefix")
    func subContainerReservedNamePrefixDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.config])
                var _innoDISubBuild_feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer multi-binding emits sub.single-binding")
    func subContainerSingleBindingDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var first, second: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "SwiftSyntaxMacroExpansion", id: "peerMacroOnVariableWithMultipleBindings"),
                MessageID(domain: "InnoDI.usage", id: "sub.single-binding")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: with an unknown parent member emits sub.unknown-parent-member")
    func subContainerBindingsUnknownParentMemberDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureConfig, parent: \\.missing)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer wildcard binding emits sub.named-property-required")
    func subContainerNamedPropertyRequiredDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var _: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "sub.named-property-required")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer inferred type emits sub.explicit-type-required")
    func subContainerExplicitTypeRequiredDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var feature = FeatureContainer()
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "sub.explicit-type-required")
            ],
            macros: Self.macros
        )
    }

    @Test("Escaped SubContainer property identifiers suppress every generated peer")
    func escapedSubContainerPropertyIdentifierFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var `default`: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.escaped-identifier-unsupported"
                )
            ]
        )
        for prefix in [
            "_storage_sub_",
            "_override_sub_",
            "_override_sub_apply_",
            "_innoDISubBuild_",
        ] {
            #expect(!result.expansion.contains(prefix))
        }
        #expect(!result.expansion.contains("_InnoDISubContainerAccessor"))
    }

    @Test("Standalone escaped SubContainer identifiers keep recovery unreachable")
    func standaloneEscapedSubContainerIdentifierDiagnoses() {
        let result = expandMacroSource(
            """
            struct StandaloneParent {
                @SubContainer(scope: .shared)
                var `default`: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.escaped-identifier-unsupported"
                )
            ]
        )
        #expect(!result.expansion.contains("_storage_sub_"))
        #expect(!result.expansion.contains("while true"))
    }

    @Test("Standalone SubContainer declarations are rejected")
    func standaloneSubContainerRequiresContainer() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct StandaloneParent {
                @SubContainer(scope: .shared)
                var child: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.requires-direct-container-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Static SubContainer declarations are rejected")
    func staticSubContainerRequiresInstanceMember() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                static var child: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.requires-direct-container-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("SubContainer declaration matrix rejects non-plain storage")
    func subContainerDeclarationMatrixFailsClosed() {
        let declarations = [
            "let child: FeatureContainer",
            "lazy var child: FeatureContainer = .init()",
            "weak var child: FeatureContainer?",
            "unowned var child: FeatureContainer",
            "private(set) var child: FeatureContainer",
            "@MainActor var child: FeatureContainer",
            "@UnknownWrapper var child: FeatureContainer",
            "var child: FeatureContainer { .init() }",
            "var child: FeatureContainer { didSet {} }",
        ]

        for declaration in declarations {
            let result = expandMacroSource(
                """
                @DIContainer
                struct AppContainer {
                    @SubContainer(scope: .shared)
                    \(declaration)
                }
                """,
                macros: Self.macros
            )

            #expect(
                result.diagnostics.map(\.diagnosticID) == [
                    MessageID(
                        domain: "InnoDI.usage",
                        id: "sub.requires-direct-container-member"
                    )
                ]
            )
            #expect(!result.expansion.contains("_InnoDISubContainerAccessor"))
            #expect(!result.expansion.contains("_storage_sub_"))
            #expect(!result.expansion.contains("struct Overrides"))
            #expect(!result.expansion.contains("withOverrides"))
        }
    }

    @Test("Duplicate SubContainer attributes emit one public usage diagnostic")
    func duplicateSubContainerAttributesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                @SubContainer(scope: .shared)
                var child: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "sub.duplicate-attribute")
            ],
            macros: Self.macros
        )
    }

    @Test("Conditionally compiled SubContainer declarations fail closed")
    func conditionalSubContainerDeclarationDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                #if os(macOS)
                @SubContainer(scope: .shared)
                var child: FeatureContainer
                #endif
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.conditional-declaration-unsupported"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Conditional SubContainer owns the terminal diagnostic before name validation")
    func conditionalEscapedSubContainerHasOneDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                #if os(macOS)
                @SubContainer(scope: .shared)
                var `default`: FeatureContainer
                #endif
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.conditional-declaration-unsupported"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Hidden SubContainer support owns peers and accessors")
    func hiddenSubContainerSupportOwnsGeneration() throws {
        let parsed = Parser.parse(source: """
        @DIContainer
        struct AppContainer {
            @SubContainer(scope: .shared)
            @InnoDI._InnoDISubContainerAccessor(recovery: false)
            var child: FeatureContainer
        }
        """)
        guard let container = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let variable = container.memberBlock.members.first?.decl.as(VariableDeclSyntax.self),
              let support = findInnoDIAttribute(
                  named: "_InnoDISubContainerAccessor",
                  in: variable.attributes
              ) else {
            Issue.record("Should parse hidden SubContainer support")
            return
        }
        let context = TestMacroExpansionContext()
        let peers = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingPeersOf: variable,
            in: context
        )
        let accessors = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingAccessorsOf: variable,
            in: context
        )
        let peerText = peers.map(\.description).joined(separator: "\n")

        #expect(context.diagnostics.isEmpty)
        #expect(accessors.map(\.description).joined().contains("get"))
        #expect(peerText.contains("_storage_sub_child"))
        #expect(peerText.contains("_override_sub_apply_child"))
    }

    @Test("Hidden SubContainer support uses the nearest container isolation")
    func hiddenSubContainerSupportUsesNearestLexicalContainer() throws {
        let parsed = Parser.parse(source: """
        @DIContainer
        struct OuterContainer {
            @DIContainer(mainActor: true)
            struct InnerContainer {
                @SubContainer(scope: .transient)
                @InnoDI._InnoDISubContainerAccessor(recovery: false)
                var child: FeatureContainer
            }
        }
        """)
        let outer = try #require(
            parsed.statements.first?.item.as(StructDeclSyntax.self)
        )
        let inner = try #require(
            outer.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        let variable = try #require(
            inner.memberBlock.members.first?.decl.as(VariableDeclSyntax.self)
        )
        let support = try #require(
            findInnoDIAttribute(
                named: "_InnoDISubContainerAccessor",
                in: variable.attributes
            )
        )
        let context = TestMacroExpansionContext(
            lexicalContext: [Syntax(inner), Syntax(outer)]
        )

        let peers = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingPeersOf: variable,
            in: context
        )
        let peerText = peers.map(\.description).joined(separator: "\n")

        #expect(context.diagnostics.isEmpty)
        #expect(peerText.contains("@_Concurrency.MainActor"))
        #expect(peerText.contains("_innoDISubBuild_child"))
    }

    @Test("Hidden SubContainer recovery emits no peers")
    func hiddenSubContainerSupportRecoverySuppressesPeers() throws {
        let parsed = Parser.parse(source: """
        @DIContainer
        struct AppContainer {
            @SubContainer(scope: .shared)
            @InnoDI._InnoDISubContainerAccessor(recovery: true)
            var child: FeatureContainer
        }
        """)
        guard let container = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let variable = container.memberBlock.members.first?.decl.as(VariableDeclSyntax.self),
              let support = findInnoDIAttribute(
                  named: "_InnoDISubContainerAccessor",
                  in: variable.attributes
              ) else {
            Issue.record("Should parse hidden SubContainer recovery support")
            return
        }
        let context = TestMacroExpansionContext()
        let peers = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingPeersOf: variable,
            in: context
        )
        let accessors = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingAccessorsOf: variable,
            in: context
        )

        #expect(context.diagnostics.isEmpty)
        #expect(peers.isEmpty)
        #expect(accessors.map(\.description).joined().contains("while true"))
    }

    @Test("Source-attached hidden SubContainer support rejects the parent model")
    func manualSubContainerSupportAttachmentFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                @InnoDI._InnoDISubContainerAccessor(recovery: false)
                var child: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.generated-accessor-manual-attachment"
                )
            ]
        )
        #expect(!result.expansion.contains("struct Overrides"))
        #expect(!result.expansion.contains("withOverrides"))
    }

    @Test("@SubContainer without scope: emits sub.scope-required")
    func subContainerMissingScopeDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer()
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.scope-required")
            ],
            macros: Self.macros
        )
    }

    @Test("@Provide dynamic scope anchors provide.unknown-scope to the expression")
    func provideDynamicScopeAnchorsToExpression() {
        assertMacroExpansionSnapshot(
            """
            let requestedScope: DIScope = .shared

            @DIContainer
            struct AppContainer {
                @Provide(
                    requestedScope,
                    factory: Service(),
                )
                var service: Service
            }
            """,
            matches: "provideDynamicScopeAnchorsToExpression",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.usage", id: "provide.unknown-scope"),
                    message: "Unknown @Provide scope: requestedScope.",
                    line: 6,
                    column: 9
                )
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer unknown scope anchors the diagnostic to the scope expression")
    func subContainerUnknownScopeAnchorsToScopeExpression() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .request
                )
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerUnknownScopeAnchorsToScopeExpression",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "sub.unknown-scope"),
                    message: "Unknown @SubContainer scope '.request' on 'feature'. Valid scopes are .shared and .transient.",
                    line: 6,
                    column: 16
                )
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with unknown scope value emits sub.unknown-scope")
    func subContainerUnknownScopeDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .request)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.unknown-scope")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with unknown parent member anchors the diagnostic to the keypath")
    func subContainerUnknownParentMemberAnchorsToKeyPath() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.missing]
                )
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerUnknownParentMemberAnchorsToKeyPath",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member"),
                    message: "@SubContainer on 'feature' references parent member 'missing' via with:, but no such member exists. Only @Provide-annotated parent members can be passed to a child container.",
                    line: 7,
                    column: 16
                )
            ],
            macros: Self.macros
        )
    }

    @Test("@Provide + @SubContainer on the same property emits sub.conflicts-with-provide")
    func subContainerConflictsWithProvideDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(.shared, factory: { (config: AppConfig) in
                    FeatureContainer(config: config)
                })
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.conflicts-with-provide")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with transient parent in with: anchors the diagnostic to the keypath")
    func subContainerTransientParentAnchorUsesKeyPath() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.transient, factory: Request()) var request: Request

                @SubContainer(
                    scope: .shared,
                    with: [\\.request]
                )
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerTransientParentAnchorUsesKeyPath",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient"),
                    message: "@SubContainer(scope: .shared) 'feature' cannot read parent member 'request' because it has .transient scope — the child is built inside init where transient accessors are not yet callable. Use @SubContainer(scope: .transient) instead, or restructure the parent so 'request' is .shared or @Input.",
                    line: 8,
                    column: 16
                )
            ],
            macros: Self.macros
        )
    }

    @Test("`with: [\\.unknown]` emits sub.unknown-parent-member")
    func subContainerUnknownParentMemberDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.nonexistent])
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member")
            ],
            macros: Self.macros
        )
    }

}
