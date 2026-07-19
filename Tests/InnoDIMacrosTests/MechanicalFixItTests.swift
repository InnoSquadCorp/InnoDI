import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Covers unambiguous, single-edit repairs end to end: the diagnostic must
/// advertise the edit, SwiftSyntax must apply it to the original source, and
/// expanding the repaired source must produce no follow-up diagnostic.
@Suite("Mechanical fix-its")
struct MechanicalFixItTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
    ]

    @Test("Opaque provider type repair applies some→any and re-expands")
    func opaqueTypeRepairAppliesAndReexpands() {
        assertRepair(
            originalSource: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    var service: some ServiceProtocol
                }
                """,
            expandedSource: """
                struct AppContainer {
                    var service: some ServiceProtocol
                }
                """,
            diagnostic: DiagnosticSpec(
                id: messageID(.provideOpaqueTypeUnsupported),
                message: "@Provide member 'service' cannot use an opaque 'some' property type because generated storage and Overrides require a stable optional type. Expose an existential 'any Protocol' instead.",
                line: 4,
                column: 18,
                fixIts: [FixItSpec(message: "Replace 'some' with 'any'")]
            ),
            applying: "Replace 'some' with 'any'",
            fixedSource: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    var service: any ServiceProtocol
                }
                """
        )
    }

    @Test("Implicitly unwrapped provider repair applies !→? and re-expands")
    func iuoTypeRepairAppliesAndReexpands() {
        assertRepair(
            originalSource: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    var service: ServiceImpl!
                }
                """,
            expandedSource: """
                struct AppContainer {
                    var service: ServiceImpl!
                }
                """,
            diagnostic: DiagnosticSpec(
                id: messageID(.provideIUOTypeUnsupported),
                message: "@Provide member 'service' cannot use an implicitly unwrapped optional type. Replace 'T!' with explicit 'T' or 'T?' so generated storage and sibling wiring have one unambiguous optionality contract.",
                line: 4,
                column: 18,
                fixIts: [FixItSpec(message: "Replace '!' with '?'")]
            ),
            applying: "Replace '!' with '?'",
            fixedSource: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    var service: ServiceImpl?
                }
                """
        )
    }

    @Test("Private container repair applies fileprivate and re-expands")
    func privateContainerRepairAppliesAndReexpands() {
        assertRepair(
            originalSource: """
                @DIContainer
                private struct AppContainer {
                    @Provide(.input)
                    var config: AppConfig
                }
                """,
            expandedSource: """
                private struct AppContainer {
                    var config: AppConfig
                }
                """,
            diagnostic: DiagnosticSpec(
                id: messageID(.containerPrivateAccessUnsupported),
                message: "@DIContainer 'AppContainer' cannot be declared private in InnoDI 5.0 because generated child-mount APIs would not be accessible to sibling containers. Use fileprivate for file-local mounting, or place a default-access container inside a private enclosing namespace.",
                line: 2,
                column: 1,
                fixIts: [
                    FixItSpec(message: "Replace 'private' with 'fileprivate'")
                ]
            ),
            applying: "Replace 'private' with 'fileprivate'",
            fixedSource: """
                @DIContainer
                fileprivate struct AppContainer {
                    @Provide(.input)
                    var config: AppConfig
                }
                """
        )
    }

    @Test("Duplicate @Provide repair removes one attribute and re-expands")
    func duplicateProvideRepairAppliesAndReexpands() {
        assertRepair(
            originalSource: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    /// Service dependency.
                    @Provide(.shared, factory: ServiceImpl())
                    var service: ServiceImpl
                }
                """,
            expandedSource: """
                struct AppContainer {
                    /// Service dependency.
                    var service: ServiceImpl
                }
                """,
            diagnostic: DiagnosticSpec(
                id: messageID(.provideDuplicateAttribute),
                message: "@Provide member 'service' declares @Provide more than once. Keep exactly one @Provide attribute on each dependency property.",
                line: 5,
                column: 5,
                fixIts: [
                    FixItSpec(message: "Remove the duplicate @Provide attribute")
                ]
            ),
            applying: "Remove the duplicate @Provide attribute",
            fixedSource: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    /// Service dependency.
                    var service: ServiceImpl
                }
                """
        )
    }

    @Test("Duplicate @SubContainer repair removes one attribute and re-expands")
    func duplicateSubContainerRepairAppliesAndReexpands() {
        assertRepair(
            originalSource: """
                @DIContainer
                struct AppContainer {
                    @SubContainer(scope: .shared)
                    @SubContainer(scope: .shared)
                    var feature: FeatureContainer
                }
                """,
            expandedSource: """
                struct AppContainer {
                    var feature: FeatureContainer
                }
                """,
            diagnostic: DiagnosticSpec(
                id: messageID(.subDuplicateAttribute),
                message: "@SubContainer member 'feature' declares @SubContainer more than once. Keep exactly one @SubContainer attribute on each child-container property.",
                line: 4,
                column: 5,
                fixIts: [
                    FixItSpec(
                        message: "Remove the duplicate @SubContainer attribute"
                    )
                ]
            ),
            applying: "Remove the duplicate @SubContainer attribute",
            fixedSource: """
                @DIContainer
                struct AppContainer {
                    @SubContainer(scope: .shared)
                    var feature: FeatureContainer
                }
                """
        )
    }

    private func assertRepair(
        originalSource: String,
        expandedSource: String,
        diagnostic: DiagnosticSpec,
        applying fixItMessage: String,
        fixedSource: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertMacroExpansionInline(
            originalSource,
            expandedSource: expandedSource,
            diagnostics: [diagnostic],
            macros: Self.macros,
            applyFixIts: [fixItMessage],
            fixedSource: fixedSource,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )

        let repaired = expandMacroSource(fixedSource, macros: Self.macros)
        #expect(
            repaired.diagnostics.isEmpty,
            "Repaired source emitted diagnostics: \(repaired.diagnostics)"
        )
    }

    private func messageID(_ code: InnoDIDiagnosticCode) -> MessageID {
        MessageID(
            domain: "InnoDI.\(code.category.rawValue)",
            id: code.rawValue
        )
    }
}
