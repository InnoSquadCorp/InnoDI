import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("InnoDISwiftUI Macro Tests")
struct InnoDISwiftUIMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "DIEnvironmentBridge": DIEnvironmentBridgeMacro.self,
        "PreviewWithContainer": PreviewWithContainerMacro.self,
    ]

    @Test("DIEnvironmentBridge generates modifier storage and protocol conformance")
    func environmentBridgeGeneratesModifierAndConformance() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "greetingService", environment: \EnvironmentValues.greetingService),
                (member: "activityService", environment: \EnvironmentValues.activityService),
            ])
            struct AppContainer {
                var greetingService: GreetingService
                var activityService: ActivityService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    var greetingService: GreetingService
                    var activityService: ActivityService

                    struct _InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier {
                        let container: AppContainer
                        func body(content: Self.Content) -> some SwiftUI.View {
                            content.environment(\SwiftUI.EnvironmentValues.greetingService, container.greetingService).environment(\SwiftUI.EnvironmentValues.activityService, container.activityService)
                        }
                    }

                    @_Concurrency.MainActor func _innoDIEnvironmentBridgeModifier() -> _InnoDIEnvironmentBridgeModifier {
                        Self._InnoDIEnvironmentBridgeModifier(container: self)
                    }
                }

                extension AppContainer: InnoDISwiftUI.DIEnvironmentBridging {
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge recognizes later bindings in a single variable declaration")
    func environmentBridgeRecognizesLaterBindingsInSingleDeclaration() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "activityService", environment: \EnvironmentValues.activityService),
            ])
            struct AppContainer {
                var greetingService, activityService: ActivityService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    var greetingService, activityService: ActivityService

                    struct _InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier {
                        let container: AppContainer
                        func body(content: Self.Content) -> some SwiftUI.View {
                            content.environment(\SwiftUI.EnvironmentValues.activityService, container.activityService)
                        }
                    }

                    @_Concurrency.MainActor func _innoDIEnvironmentBridgeModifier() -> _InnoDIEnvironmentBridgeModifier {
                        Self._InnoDIEnvironmentBridgeModifier(container: self)
                    }
                }

                extension AppContainer: InnoDISwiftUI.DIEnvironmentBridging {
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge maps open access to public generated members")
    func environmentBridgeMapsOpenAccessToPublicMembers() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "greetingService", environment: \EnvironmentValues.greetingService),
            ])
            open class AppContainer {
                var greetingService: GreetingService
            }
            """#,
            expandedSource: #"""
                open class AppContainer {
                    var greetingService: GreetingService

                    public struct _InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier {
                        let container: AppContainer
                        public func body(content: Self.Content) -> some SwiftUI.View {
                            content.environment(\SwiftUI.EnvironmentValues.greetingService, container.greetingService)
                        }
                    }

                    @_Concurrency.MainActor public func _innoDIEnvironmentBridgeModifier() -> _InnoDIEnvironmentBridgeModifier {
                        Self._InnoDIEnvironmentBridgeModifier(container: self)
                    }
                }

                extension AppContainer: InnoDISwiftUI.DIEnvironmentBridging {
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects duplicate member mappings")
    func environmentBridgeRejectsDuplicateMembers() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "greetingService", environment: \EnvironmentValues.greetingService),
                (member: "greetingService", environment: \EnvironmentValues.activityService),
            ])
            struct AppContainer {
                var greetingService: GreetingService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    var greetingService: GreetingService
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-duplicate-member"),
                    message: "@DIEnvironmentBridge maps container member 'greetingService' more than once.",
                    line: 3,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects async Provide members")
    func environmentBridgeRejectsAsyncProvideMembers() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "remoteService", environment: \EnvironmentValues.remoteService),
            ])
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async in RemoteService() })
                var remoteService: RemoteService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    @Provide(.shared, asyncFactory: { () async in RemoteService() })
                    var remoteService: RemoteService
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-async-member"),
                    message: "@DIEnvironmentBridge cannot map async container member 'remoteService' into SwiftUI EnvironmentValues. Expose a synchronous value or inject a service that performs async work internally.",
                    line: 2,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects invalid environment key paths")
    func environmentBridgeRejectsInvalidEnvironmentKeyPaths() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "greetingService", environment: "not-a-key-path"),
            ])
            struct AppContainer {
                var greetingService: GreetingService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    var greetingService: GreetingService
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-invalid-keypath"),
                    message: "@DIEnvironmentBridge requires 'environment' to be a key-path expression.",
                    line: 2,
                    column: 46
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects key paths outside SwiftUI EnvironmentValues")
    func environmentBridgeRejectsNonEnvironmentValuesKeyPaths() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "greetingService", environment: \OtherValues.greetingService),
            ])
            struct AppContainer {
                var greetingService: GreetingService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    var greetingService: GreetingService
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-invalid-keypath"),
                    message: "@DIEnvironmentBridge requires 'environment' to be a direct-member key-path literal rooted at EnvironmentValues or SwiftUI.EnvironmentValues, such as \\EnvironmentValues.service.",
                    line: 2,
                    column: 46
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge accepts only direct EnvironmentValues members")
    func environmentBridgeRejectsCapturedKeyPathComponents() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            typealias ValuesAlias = EnvironmentValues

            @DIEnvironmentBridge([
                (member: "value", environment: \ValuesAlias.value),
            ])
            struct AliasRootBridge { var value: Int }

            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value.nested),
            ])
            struct ChainedBridge { var value: Int }

            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues[SomeKey.self]),
            ])
            struct SubscriptBridge { var value: Int }
            """#,
            expectedCodes: Array(
                repeating: MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-invalid-keypath"
                ),
                count: 3
            ),
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge canonicalizes qualified EnvironmentValues roots")
    func environmentBridgeAcceptsQualifiedEnvironmentValuesRoot() {
        let result = expandMacroSource(
            #"""
            @DIEnvironmentBridge([
                (member: "value", environment: \SwiftUI.EnvironmentValues.value),
            ])
            struct QualifiedBridge { var value: Int }
            """#,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "content.environment(\\SwiftUI.EnvironmentValues.value, container.value)"
            )
        )
    }

    @Test("DIEnvironmentBridge rejects malformed top-level arguments")
    func environmentBridgeRejectsMalformedTopLevelArguments() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge("not-an-array")
            struct AppContainer {
                var greetingService: GreetingService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    var greetingService: GreetingService
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-invalid-arguments"),
                    message: "@DIEnvironmentBridge requires a single array literal of (member: ..., environment: ...) mappings.",
                    line: 1,
                    column: 1
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge generates a single-member modifier")
    func environmentBridgeSingleMemberShape() {
        assertMacroExpansionInline(
            #"""
            @DIEnvironmentBridge([
                (member: "greetingService", environment: \EnvironmentValues.greetingService),
            ])
            struct AppContainer {
                var greetingService: GreetingService
            }
            """#,
            expandedSource: #"""
                struct AppContainer {
                    var greetingService: GreetingService

                    struct _InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier {
                        let container: AppContainer
                        func body(content: Self.Content) -> some SwiftUI.View {
                            content.environment(\SwiftUI.EnvironmentValues.greetingService, container.greetingService)
                        }
                    }

                    @_Concurrency.MainActor func _innoDIEnvironmentBridgeModifier() -> _InnoDIEnvironmentBridgeModifier {
                        Self._InnoDIEnvironmentBridgeModifier(container: self)
                    }
                }

                extension AppContainer: InnoDISwiftUI.DIEnvironmentBridging {
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects direct nested generated modifier types through #if")
    func environmentBridgeGeneratedModifierTypeConflictsDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            @DIEnvironmentBridge([])
            struct ConditionalTypeConflict {
                #if DEBUG
                struct _InnoDIEnvironmentBridgeModifier {}
                #else
                typealias _InnoDIEnvironmentBridgeModifier = Int
                #endif
            }

            @DIEnvironmentBridge([])
            struct ProtocolTypeConflict {
                protocol _InnoDIEnvironmentBridgeModifier {}
            }

            @DIEnvironmentBridge([])
            struct StaticVariableConflict {
                static var _InnoDIEnvironmentBridgeModifier: Int { 0 }
            }

            @DIEnvironmentBridge([])
            struct StaticFunctionConflict {
                static func _InnoDIEnvironmentBridgeModifier(_ value: Int) {}
            }

            @DIEnvironmentBridge([])
            enum EnumCaseConflict {
                case _InnoDIEnvironmentBridgeModifier
            }

            @DIEnvironmentBridge([])
            class ClassVariableConflict {
                class var _InnoDIEnvironmentBridgeModifier: Int { 0 }
            }
            """#,
            expectedCodes: Array(
                repeating: MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-generated-name-conflict"
                ),
                count: 7
            ),
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects direct instance generated helpers through #if")
    func environmentBridgeGeneratedHelperConflictsDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIEnvironmentBridge([])
            struct ConditionalVariableConflict {
                #if DEBUG
                var _innoDIEnvironmentBridgeModifier: Int { 0 }
                #endif
            }

            @DIEnvironmentBridge([])
            struct FunctionConflict {
                func _innoDIEnvironmentBridgeModifier() {}
            }
            """,
            expectedCodes: Array(
                repeating: MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-generated-name-conflict"
                ),
                count: 2
            ),
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge generated-name diagnostics describe the conflicting namespace")
    func environmentBridgeGeneratedNameConflictMessagesDescribeNamespaces() {
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            struct AppContainer {
                struct _InnoDIEnvironmentBridgeModifier {}
                var _innoDIEnvironmentBridgeModifier: Int { 0 }
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.message) == [
            "@DIEnvironmentBridge generates nested modifier type '_InnoDIEnvironmentBridgeModifier', but the bridge target already declares a conflicting direct type member with that name. Rename the declaration so the modifier can be synthesized without a Swift redeclaration error.",
            "@DIEnvironmentBridge generates zero-parameter instance helper '_innoDIEnvironmentBridgeModifier', but the bridge target already declares a direct instance variable or zero-parameter instance function with that name. Rename the declaration so the helper can be synthesized without a Swift redeclaration error.",
        ])
        #expect(!result.expansion.contains("_InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier"))
    }

    @Test("DIEnvironmentBridge allows generated spellings in other namespaces and binders")
    func environmentBridgeGeneratedNamesInOtherNamespacesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            struct _InnoDIEnvironmentBridgeModifier {}

            @DIEnvironmentBridge([])
            struct _innoDIEnvironmentBridgeModifier {}

            @DIEnvironmentBridge([])
            struct ModifierGeneric<_InnoDIEnvironmentBridgeModifier> {}

            @DIEnvironmentBridge([])
            struct HelperGeneric<_innoDIEnvironmentBridgeModifier> {}

            @DIEnvironmentBridge([])
            struct CrossNamespaceContainer {
                var _InnoDIEnvironmentBridgeModifier: Int { 0 }
                struct _innoDIEnvironmentBridgeModifier {}
            }

            @DIEnvironmentBridge([])
            struct DIEnvironmentBridging {}

            @DIEnvironmentBridge([])
            struct BridgingGeneric<DIEnvironmentBridging> {}
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("struct _InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier"))
        #expect(result.expansion.contains("func _innoDIEnvironmentBridgeModifier()"))
        #expect(
            result.expansion.contains(
                "Self._InnoDIEnvironmentBridgeModifier(container: self)"
            )
        )
        #expect(
            result.expansion.contains(
                "extension DIEnvironmentBridging: InnoDISwiftUI.DIEnvironmentBridging"
            )
        )
        #expect(!result.expansion.contains("_innodiEnvironmentBridgeModifier"))
    }

    @Test("DIEnvironmentBridge safely stores a target that shares the modifier name")
    func environmentBridgeModifierNamedTargetUsesKeyPathStorage() {
        let result = expandMacroSource(
            #"""
            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value),
            ])
            struct _InnoDIEnvironmentBridgeModifier {
                var value: Int { 7 }
            }

            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value),
            ])
            struct GenericBridge<
                _InnoDIEnvironmentBridgeModifier,
                _InnoDIContainer,
                _InnoDIContainer_1,
                _InnoDIValue0,
                _InnoDIValue0_1
            > {
                var value: Int { 8 }
            }
            """#,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "struct _InnoDIEnvironmentBridgeModifier<_InnoDIContainer, _InnoDIValue0>"
            )
        )
        #expect(
            result.expansion.contains(
                "let member0: Swift.KeyPath<_InnoDIContainer, _InnoDIValue0>"
            )
        )
        #expect(
            result.expansion.contains(
                "let environment0: Swift.WritableKeyPath<SwiftUI.EnvironmentValues, _InnoDIValue0>"
            )
        )
        #expect(result.expansion.contains("container[keyPath: member0]"))
        #expect(result.expansion.contains("member0: \\Self.value"))
        #expect(result.expansion.contains("Self._InnoDIEnvironmentBridgeModifier("))
        #expect(result.expansion.contains("-> some SwiftUI.ViewModifier"))
        #expect(
            result.expansion.contains(
                "_InnoDIEnvironmentBridgeModifier<_InnoDIContainer_2, _InnoDIValue0_2>"
            )
        )
    }

    @Test("DIEnvironmentBridge avoids target and EnvironmentValues nested type capture")
    func environmentBridgeNestedTypeCaptureUsesCanonicalStorage() {
        let result = expandMacroSource(
            #"""
            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value),
            ])
            struct Bridge {
                struct Bridge {}
                struct EnvironmentValues {}
                var value: Int { 1 }
            }

            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value),
            ])
            struct NormalBridge {
                struct EnvironmentValues {}
                var value: Int { 2 }
            }
            """#,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "struct _InnoDIEnvironmentBridgeModifier<_InnoDIContainer, _InnoDIValue0>"
            )
        )
        #expect(
            result.expansion.contains(
                "environment0: \\SwiftUI.EnvironmentValues.value"
            )
        )
        #expect(!result.expansion.contains("let container: Bridge"))
        #expect(result.expansion.contains("let container: NormalBridge"))
        #expect(
            result.expansion.contains(
                "content.environment(\\SwiftUI.EnvironmentValues.value, container.value)"
            )
        )
    }

    @Test("DIEnvironmentBridge avoids target names captured by visible generics")
    func environmentBridgeVisibleGenericTargetCaptureUsesCanonicalStorage() {
        let result = expandMacroSource(
            #"""
            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value),
            ])
            struct SelfGenericBridge<SelfGenericBridge> {
                var value: Int { 1 }
            }

            struct Outer<EnclosingBridge> {
                @DIEnvironmentBridge([
                    (member: "value", environment: \EnvironmentValues.value),
                ])
                struct EnclosingBridge {
                    var value: Int { 2 }
                }
            }
            """#,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.components(
                separatedBy: "struct _InnoDIEnvironmentBridgeModifier<"
            ).count == 3
        )
        #expect(!result.expansion.contains("let container: SelfGenericBridge"))
        #expect(!result.expansion.contains("let container: EnclosingBridge"))
    }

    @Test("DIEnvironmentBridge rejects generic parameter-pack targets")
    func environmentBridgeParameterPackDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value),
            ])
            struct PackBridge<each Value> {
                var value: Int { 1 }
            }
            """#,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "swiftui.environment-bridge-parameter-pack-unsupported"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge widens private generated protocol witnesses")
    func environmentBridgePrivateTargetUsesFileprivateWitnesses() {
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            private struct PrivateBridge {}
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "fileprivate struct _InnoDIEnvironmentBridgeModifier"
            )
        )
        #expect(result.expansion.contains("fileprivate func body"))
        #expect(
            result.expansion.contains(
                "@_Concurrency.MainActor fileprivate func _innoDIEnvironmentBridgeModifier()"
            )
        )
        #expect(!result.expansion.contains("\n        private func body"))
    }

    @Test("DIEnvironmentBridge rejects private nested lookup components")
    func environmentBridgePrivateNestedLookupDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct DirectHost {
                @DIEnvironmentBridge([])
                private struct PrivateBridge {}
            }

            struct IndirectHost {
                private struct Namespace {
                    @DIEnvironmentBridge([])
                    struct Bridge {}
                }
            }
            """,
            expectedCodes: Array(
                repeating: MessageID(
                    domain: "InnoDI.usage",
                    id: "swiftui.environment-bridge-private-nested-target"
                ),
                count: 2
            ),
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge allows static members, parameter overloads, and nested bodies")
    func environmentBridgeNonRedeclaringGeneratedNamesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            class StaticPropertyContainer {
                static var _innoDIEnvironmentBridgeModifier = 0
                func _innoDIEnvironmentBridgeModifier(value: Int) {}
                func _InnoDIEnvironmentBridgeModifier() {}

                struct Nested {
                    typealias _InnoDIEnvironmentBridgeModifier = Int
                    var _innoDIEnvironmentBridgeModifier = 0
                }

                func localScope() {
                    struct _InnoDIEnvironmentBridgeModifier {}
                    let _innoDIEnvironmentBridgeModifier = 0
                }
            }

            @DIEnvironmentBridge([])
            class ClassFunctionContainer {
                class func _innoDIEnvironmentBridgeModifier() {}
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("struct _InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier"))
        #expect(result.expansion.contains("func _innoDIEnvironmentBridgeModifier()"))
    }

    @Test("DIEnvironmentBridge rejects direct type declarations that shadow generated qualifiers")
    func environmentBridgeReservedDirectModuleNamesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIEnvironmentBridge([])
            struct AppContainer {
                struct Swift {}
                enum SwiftUI {}
            }
            """,
            expectedCodes: Array(
                repeating: MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-reserved-module-name"
                ),
                count: 2
            ),
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge allows direct InnoDISwiftUI type declarations")
    func environmentBridgeAllowsDirectInnoDISwiftUITypeNames() {
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            struct NestedTypeBridge {
                struct InnoDISwiftUI {}
            }

            @DIEnvironmentBridge([])
            struct TypeAliasBridge {
                typealias InnoDISwiftUI = Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains(
            "extension NestedTypeBridge: InnoDISwiftUI.DIEnvironmentBridging"
        ))
        #expect(result.expansion.contains(
            "extension TypeAliasBridge: InnoDISwiftUI.DIEnvironmentBridging"
        ))
    }

    @Test("DIEnvironmentBridge rejects target and enclosing nominal qualifier shadows")
    func environmentBridgeReservedScopeModuleNamesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct Swift {
                @DIEnvironmentBridge([])
                struct BridgeContainer {}
            }

            @DIEnvironmentBridge([])
            struct SwiftUI {}

            @DIEnvironmentBridge([])
            struct InnoDISwiftUI {}
            """,
            expectedCodes: Array(
                repeating: MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-reserved-module-name"
                ),
                count: 3
            ),
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects target and enclosing generic qualifier shadows")
    func environmentBridgeReservedGenericParametersDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIEnvironmentBridge([])
            struct GenericBridge<SwiftUI> {}

            struct Outer<Swift> {
                @DIEnvironmentBridge([])
                struct NestedBridge {}
            }

            @DIEnvironmentBridge([])
            struct ModuleGeneric<InnoDISwiftUI> {}
            """,
            expectedCodes: Array(
                repeating: MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-reserved-module-name"
                ),
                count: 3
            ),
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects extension lookup contexts")
    func environmentBridgeExtensionContextDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct Host {}

            extension Host {
                @DIEnvironmentBridge([])
                struct NestedBridge {}
            }

            @DIEnvironmentBridge([])
            extension Host {}
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "swiftui.environment-bridge-extension-context-unsupported"
                ),
                MessageID(
                    domain: "InnoDI.usage",
                    id: "swiftui.environment-bridge-extension-context-unsupported"
                ),
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge rejects actor and protocol targets before companion expansion")
    func environmentBridgeUnsupportedDeclarationKindsDiagnose() {
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            actor ActorBridge {}

            @DIEnvironmentBridge([])
            protocol ProtocolBridge {}
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == Array(
                repeating: MessageID(
                    domain: "InnoDI.usage",
                    id: "swiftui.environment-bridge-unsupported-declaration-kind"
                ),
                count: 2
            )
        )
        #expect(!result.expansion.contains("ActorBridge: InnoDISwiftUI"))
        #expect(!result.expansion.contains("ProtocolBridge: InnoDISwiftUI"))
    }

    @Test("DIEnvironmentBridge excludes class members from instance mappings")
    func environmentBridgeClassMembersAreUnknown() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            @DIEnvironmentBridge([
                (member: "value", environment: \EnvironmentValues.value),
            ])
            class ClassMemberBridge {
                class var value: Int { 1 }
            }
            """#,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-unknown-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIEnvironmentBridge keeps module-like value member names available")
    func environmentBridgeModuleValueNamesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            struct AppContainer {
                var Swift: Int
                var SwiftUI: Int
                var InnoDISwiftUI: Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("_InnoDIEnvironmentBridgeModifier"))
    }

    @Test("DIContainer and DIEnvironmentBridge divide qualifier diagnostics without duplicates")
    func environmentBridgeContainerQualifierDiagnosticsHaveSingleOwners() {
        let macros: [String: any Macro.Type] = [
            "DIContainer": DIContainerMacro.self,
            "DIEnvironmentBridge": DIEnvironmentBridgeMacro.self,
        ]
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            @DIContainer
            struct AppContainer {
                struct Swift {}
                struct SwiftUI {}
            }
            """,
            macros: macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID).sorted(by: {
                String(reflecting: $0) < String(reflecting: $1)
            }) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "container.reserved-module-name"
                ),
                MessageID(
                    domain: "InnoDI.validation",
                    id: "swiftui.environment-bridge-reserved-module-name"
                ),
            ].sorted(by: {
                String(reflecting: $0) < String(reflecting: $1)
            })
        )
        #expect(!result.expansion.contains("_InnoDIEnvironmentBridgeModifier"))
    }

    @Test("DIContainer owns generated-name diagnostics shared with DIEnvironmentBridge")
    func environmentBridgeContainerGeneratedNameDiagnosticsHaveSingleOwner() {
        let macros: [String: any Macro.Type] = [
            "DIContainer": DIContainerMacro.self,
            "DIEnvironmentBridge": DIEnvironmentBridgeMacro.self,
        ]
        let result = expandMacroSource(
            """
            @DIEnvironmentBridge([])
            @DIContainer
            struct AppContainer {
                struct _InnoDIEnvironmentBridgeModifier {}
            }
            """,
            macros: macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.validation",
                id: "container.reserved-name-prefix"
            ),
        ])
        #expect(!result.expansion.contains("_InnoDIEnvironmentBridgeModifier: SwiftUI.ViewModifier"))
    }

    @Test("PreviewWithContainer wraps the trailing closure inside a #Preview block")
    func previewWithContainerExpandsToPreviewBlock() {
        assertMacroExpansionInline(
            #"""
            let preview = #PreviewWithContainer(AppContainer(baseURL: "https://example.com")) { container in
                container.dashboardRootView()
            }
            """#,
            expandedSource: ##"""
                let preview = #Preview {
                    InnoDISwiftUI.DIContainerHost(
                        identity: false,
                        factory: { _ in
                            AppContainer(baseURL: "https://example.com")
                        },
                        content: { __innodi_preview_container, _ in
                            ({
                                container in
                                    container.dashboardRootView()
                            })(__innodi_preview_container)
                        },
                        loading: {
                            SwiftUI.EmptyView()
                        },
                        failure: { _, _ in
                            SwiftUI.EmptyView()
                        }
                    )
                }
                """##,
            macros: Self.macros
        )
    }

    @Test("PreviewWithContainer accepts the preview body as an argument closure")
    func previewWithContainerAcceptsArgumentClosure() {
        assertMacroExpansionInline(
            #"""
            let preview = #PreviewWithContainer(AppContainer(baseURL: "https://example.com"), { container in
                container.dashboardRootView()
            })
            """#,
            expandedSource: ##"""
                let preview = #Preview {
                    InnoDISwiftUI.DIContainerHost(
                        identity: false,
                        factory: { _ in
                            AppContainer(baseURL: "https://example.com")
                        },
                        content: { __innodi_preview_container, _ in
                            ({
                                container in
                                    container.dashboardRootView()
                            })(__innodi_preview_container)
                        },
                        loading: {
                            SwiftUI.EmptyView()
                        },
                        failure: { _, _ in
                            SwiftUI.EmptyView()
                        }
                    )
                }
                """##,
            macros: Self.macros
        )
    }

    @Test("PreviewWithContainer diagnoses a missing container expression")
    func previewWithContainerDiagnosesMissingContainerExpression() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            let preview = #PreviewWithContainer { container in
                container.dashboardRootView()
            }
            """#,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.preview-with-container-missing-container")
            ],
            macros: Self.macros
        )
    }

    @Test("PreviewWithContainer diagnoses a closure without a container parameter")
    func previewWithContainerDiagnosesMissingContainerParameter() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            let preview = #PreviewWithContainer(AppContainer()) {
                DashboardRootView()
            }
            """#,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.preview-with-container-missing-parameter")
            ],
            macros: Self.macros
        )
    }

    @Test("PreviewWithContainer diagnoses an explicitly parameterless closure")
    func previewWithContainerDiagnosesExplicitlyParameterlessClosure() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            let preview = #PreviewWithContainer(AppContainer()) { () in
                DashboardRootView()
            }
            """#,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.preview-with-container-missing-parameter")
            ],
            macros: Self.macros
        )
    }

    @Test("PreviewWithContainer diagnoses a trailing closure with multiple container parameters")
    func previewWithContainerDiagnosesMultiParameterTrailingClosure() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            let preview = #PreviewWithContainer(AppContainer()) { container, other in
                container.dashboardRootView(other)
            }
            """#,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.preview-with-container-missing-parameter")
            ],
            macros: Self.macros
        )
    }

    @Test("PreviewWithContainer diagnoses an argument closure with multiple container parameters")
    func previewWithContainerDiagnosesMultiParameterArgumentClosure() {
        assertMacroExpansionDiagnosticCodes(
            #"""
            let preview = #PreviewWithContainer(AppContainer(), { container, other in
                container.dashboardRootView(other)
            })
            """#,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.preview-with-container-missing-parameter")
            ],
            macros: Self.macros
        )
    }

}
