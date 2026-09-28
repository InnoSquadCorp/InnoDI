import Foundation
import InnoDIDependencyGraphCore
import InnoDITestSupport
import InnoDIWorkspaceAnalysis
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
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
        "Input": ProvideMacro.self,
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
                message: "@DIContainer 'AppContainer' cannot be declared private in InnoDI 6.0 because generated child-mount APIs would not be accessible to sibling containers. Use fileprivate for file-local mounting, or place a default-access container inside a private enclosing namespace.",
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

    @Test("Unique binding repair applies, compiles, graphs, and is idempotent")
    func uniqueBindingRepairBuildsAndGraphs() throws {
        let original = """
        struct Service {
            init(baseURL: String) {}
        }

        @DIContainer
        struct AppContainer {
            @Input
            var baseURL: String

            @Provide(.shared, Service.self, with: [\\Self.base_url])
            var service: Service
        }
        """
        let repaired = try applyUniqueBindingFixIt(to: original)
        #expect(repaired.contains("with: [\\Self.baseURL]"))
        #expect(try applyUniqueBindingFixIt(to: repaired) == repaired)

        let expansion = expandMacroSource(repaired, macros: Self.macros)
        #expect(expansion.diagnostics.isEmpty)

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(
            "innodi-binding-fixit-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sources = fixture.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = """
        // swift-tools-version: 6.2
        import PackageDescription
        let package = Package(
            name: "FixItFixture",
            platforms: [.macOS(.v13)],
            dependencies: [.package(name: "InnoDI", path: "\(packageRoot.path)")],
            targets: [
                .target(
                    name: "App",
                    dependencies: [.product(name: "InnoDI", package: "InnoDI")],
                    plugins: [.plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")]
                )
            ]
        )
        """
        try Data(manifest.utf8).write(to: fixture.appendingPathComponent("Package.swift"))
        try Data("import InnoDI\n\(repaired)\n".utf8).write(
            to: sources.appendingPathComponent("App.swift")
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "build", "--package-path", fixture.path,
            "--scratch-path", fixture.appendingPathComponent("build").path,
            "--jobs", "1",
            // SwiftPM 6.3.3 can schedule a nested local-package target before
            // its experimental SwiftSyntax prebuilt is materialized when the
            // outer test process is using the same package graph. This fixture
            // validates the applied source edit, not prebuilt selection, so a
            // deterministic source build is the appropriate contract here.
            "--disable-experimental-prebuilts",
            "-Xswiftc", "-strict-concurrency=complete",
            "-Xswiftc", "-warnings-as-errors",
        ]
        // A cold SwiftSyntax source build on the slowest supported hosted
        // runner can take longer than three minutes. Keep a bounded timeout,
        // but leave enough headroom for the deterministic source-build path.
        let build = try runCapturedProcess(process, timeoutSeconds: 360)
        #expect(build.exitCode == 0, Comment(rawValue: build.combinedOutput))

        let snapshot = try loadWorkspaceSourceSnapshot(rootPath: fixture.path)
        let graph = collectDependencyGraph(snapshot: snapshot, validateDAG: true)
        #expect(graph.preflightFailure == nil)
        #expect(Set(graph.providers.map(\.name)).isSuperset(of: ["baseURL", "service"]))
        let service = try #require(graph.providers.first { $0.name == "service" })
        #expect(service.dependencyBindings.count == 1)
        #expect(service.dependencyBindings.first?.parameter == "baseURL")
        #expect(service.dependencyBindings.first?.providerID.hasSuffix(".baseURL") == true)
    }

    private func applyUniqueBindingFixIt(to source: String) throws -> String {
        let parsed = Parser.parse(source: source)
        guard let declaration = parsed.statements.compactMap({
            $0.item.as(StructDeclSyntax.self)
        }).first(where: { declaration in
            declaration.attributes.contains { element in
                element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
                    == "DIContainer"
            }
        }),
              let attribute = declaration.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse fix-it container")
            return source
        }
        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(
            of: attribute,
            providingMembersOf: declaration,
            in: context
        )
        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(
                domain: "InnoDI.validation",
                id: "provide.unresolved-with-dependency"
            )
        }) else {
            return source
        }
        #expect(diagnostic.fixIts.count == 1)
        let fixIt = try #require(diagnostic.fixIts.first)
        #expect(fixIt.changes.count == 1)
        let change = try #require(fixIt.changes.first)
        guard case let .replaceText(range, replacement, _) = change else {
            Issue.record("Binding fix-it must be one textual replacement")
            return source
        }
        var bytes = Array(source.utf8)
        bytes.replaceSubrange(
            range.lowerBound.utf8Offset..<range.upperBound.utf8Offset,
            with: replacement.utf8
        )
        return String(decoding: bytes, as: UTF8.self)
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
