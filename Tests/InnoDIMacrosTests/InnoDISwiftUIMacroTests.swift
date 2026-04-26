import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("InnoDISwiftUI Macro Tests")
struct InnoDISwiftUIMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "DIEnvironmentBridge": DIEnvironmentBridgeMacro.self,
        "DIFeatureRoot": DIFeatureRootMacro.self,
        "InnoDISwiftUI.DIFeatureRoot": DIFeatureRootMacro.self,
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
                        func body(content: Content) -> some SwiftUI.View {
                            content.environment(\EnvironmentValues.greetingService, container.greetingService).environment(\EnvironmentValues.activityService, container.activityService)
                        }
                    }

                    @MainActor func _innodiEnvironmentBridgeModifier() -> _InnoDIEnvironmentBridgeModifier {
                        _InnoDIEnvironmentBridgeModifier(container: self)
                    }
                }

                extension AppContainer: DIEnvironmentBridging {
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
                        func body(content: Content) -> some SwiftUI.View {
                            content.environment(\EnvironmentValues.activityService, container.activityService)
                        }
                    }

                    @MainActor func _innodiEnvironmentBridgeModifier() -> _InnoDIEnvironmentBridgeModifier {
                        _InnoDIEnvironmentBridgeModifier(container: self)
                    }
                }

                extension AppContainer: DIEnvironmentBridging {
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
                        public func body(content: Content) -> some SwiftUI.View {
                            content.environment(\EnvironmentValues.greetingService, container.greetingService)
                        }
                    }

                    @MainActor public func _innodiEnvironmentBridgeModifier() -> _InnoDIEnvironmentBridgeModifier {
                        _InnoDIEnvironmentBridgeModifier(container: self)
                    }
                }

                extension AppContainer: DIEnvironmentBridging {
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

    @Test("DIFeatureRoot generates default and named helpers")
    func featureRootGeneratesDefaultAndNamedHelpers() {
        assertMacroExpansionInline(
            #"""
            struct ParentContainer {
                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self)
                @DIFeatureRoot(DashboardShellView.self, as: "dashboardShell")
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                struct ParentContainer {
                    @SubContainer(scope: .shared)
                    var dashboard: DashboardContainer

                    func dashboardRootView() -> DashboardRootView {
                        DashboardRootView(container: dashboard)
                    }

                    func dashboardShellRootView() -> DashboardShellView {
                        DashboardShellView(container: dashboard)
                    }
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot maps open access to public generated helpers")
    func featureRootMapsOpenAccessToPublicHelpers() {
        assertMacroExpansionInline(
            #"""
            open class ParentContainer {
                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self)
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                open class ParentContainer {
                    @SubContainer(scope: .shared)
                    var dashboard: DashboardContainer

                    public func dashboardRootView() -> DashboardRootView {
                        DashboardRootView(container: dashboard)
                    }
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot accepts qualified InnoDI SubContainer attributes")
    func featureRootAcceptsQualifiedSubContainerAttributes() {
        assertMacroExpansionInline(
            #"""
            struct ParentContainer {
                @InnoDI.SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self)
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                struct ParentContainer {
                    @InnoDI.SubContainer(scope: .shared)
                    var dashboard: DashboardContainer

                    func dashboardRootView() -> DashboardRootView {
                        DashboardRootView(container: dashboard)
                    }
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot rejects invalid aliases before generating helpers")
    func featureRootRejectsInvalidAlias() {
        assertMacroExpansionInline(
            #"""
            struct ParentContainer {
                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self, as: "dashboard-shell")
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                struct ParentContainer {
                    @SubContainer(scope: .shared)
                    var dashboard: DashboardContainer
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-invalid-alias"),
                    message: "Alias 'dashboard-shell' for @DIFeatureRoot must be a non-empty Swift identifier.",
                    line: 3,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot rejects reserved keyword aliases")
    func featureRootRejectsReservedKeywordAlias() {
        assertMacroExpansionInline(
            #"""
            struct ParentContainer {
                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self, as: "class")
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                struct ParentContainer {
                    @SubContainer(scope: .shared)
                    var dashboard: DashboardContainer
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-invalid-alias"),
                    message: "Alias 'class' for @DIFeatureRoot must be a non-empty Swift identifier.",
                    line: 3,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot accepts raw-string aliases")
    func featureRootAcceptsRawStringAlias() {
        assertMacroExpansionInline(
            ##"""
            struct ParentContainer {
                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self, as: #"dashboardShell"#)
                var dashboard: DashboardContainer
            }
            """##,
            expandedSource: #"""
                struct ParentContainer {
                    @SubContainer(scope: .shared)
                    var dashboard: DashboardContainer

                    func dashboardShellRootView() -> DashboardRootView {
                        DashboardRootView(container: dashboard)
                    }
                }
                """#,
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot rejects interpolated aliases instead of treating them as default helpers")
    func featureRootRejectsInterpolatedAlias() {
        assertMacroExpansionInline(
            #"""
            struct ParentContainer {
                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self, as: "dashboard\(suffix)")
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                struct ParentContainer {
                    @SubContainer(scope: .shared)
                    var dashboard: DashboardContainer
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-invalid-alias"),
                    message: #"Alias '"dashboard\(suffix)"' for @DIFeatureRoot must be a non-empty Swift identifier."#,
                    line: 3,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot ignores multi-binding declarations")
    func featureRootIgnoresMultiBindingDeclarations() {
        let expansion = expandMacroSource(
            #"""
            struct ParentContainer {
                @SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self)
                var dashboard, secondaryDashboard: DashboardContainer
            }
            """#,
            macros: Self.macros
        )

        #expect(!expansion.expansion.contains("dashboardRootView"))
        #expect(expansion.diagnostics.count == 1)
        #expect(expansion.diagnostics.first?.message == "peer macro can only be applied to a single variable")
    }

    @Test("DIFeatureRoot requires SubContainer")
    func featureRootRequiresSubContainer() {
        assertMacroExpansionInline(
            #"""
            struct ParentContainer {
                @DIFeatureRoot(DashboardRootView.self)
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                struct ParentContainer {
                    var dashboard: DashboardContainer
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-without-subcontainer"),
                    message: "@DIFeatureRoot can only be attached to a property that also declares @SubContainer.",
                    line: 2,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }

    @Test("DIFeatureRoot ignores foreign qualified SubContainer attributes")
    func featureRootIgnoresForeignQualifiedSubContainer() {
        assertMacroExpansionInline(
            #"""
            struct ParentContainer {
                @OtherDI.SubContainer(scope: .shared)
                @DIFeatureRoot(DashboardRootView.self)
                var dashboard: DashboardContainer
            }
            """#,
            expandedSource: #"""
                struct ParentContainer {
                    @OtherDI.SubContainer(scope: .shared)
                    var dashboard: DashboardContainer
                }
                """#,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-without-subcontainer"),
                    message: "@DIFeatureRoot can only be attached to a property that also declares @SubContainer.",
                    line: 3,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }
}
