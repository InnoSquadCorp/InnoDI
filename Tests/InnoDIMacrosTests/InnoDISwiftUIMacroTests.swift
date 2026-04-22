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
