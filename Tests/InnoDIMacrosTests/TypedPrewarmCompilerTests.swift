import Foundation
import InnoDITestSupport
import SwiftBasicFormat
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

/// Compile the actual emitted selection surface against plain Swift computed
/// properties. This checks Swift syntax, type namespaces, and executor bounds;
/// it intentionally does not emulate InnoDI storage, caching, or Apple APIs.
@Suite("Typed prewarm generated-surface compiler checks")
struct TypedPrewarmCompilerTests {
    @Test("Emitted selection declarations typecheck and reject off-actor calls")
    func emittedSurfaceTypechecks() throws {
        let names = ["some", "any", "actor", "nonisolated", "package", "서비스"]
        let plain = try emittedContainer(named: "CallerContainer", mainActor: false, names: names)
        let isolated = try emittedContainer(named: "ActorContainer", mainActor: true, names: names)
        let source = """
            public final class NonSendableValue {}
            \(plain)
            \(isolated)

            func warmOnCaller(_ container: CallerContainer) {
                let _: Void = container.prewarm(.some, .any, .actor, .nonisolated, .package, .서비스)
                container.prewarm()
                let _: Int = container.PrewarmProvider
                let _: Int = container.Swift
            }

            @MainActor
            func warmOnMainActor(_ container: ActorContainer) {
                let _: Void = container.prewarm(.some, .any, .actor, .nonisolated, .package, .서비스)
                container.prewarm()
            }

            func transferSelection() async -> ActorContainer._InnoDIPrewarmProvider {
                await Task.detached { ActorContainer._InnoDIPrewarmProvider.서비스 }.value
            }
            """

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-TypedPrewarm-Compiler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let positive = try typecheck(source, named: "valid.swift", in: directory)
        #expect(!positive.timedOut, Comment(rawValue: positive.combinedOutput))
        #expect(positive.exitCode == 0, Comment(rawValue: positive.combinedOutput))
        guard !positive.timedOut, positive.exitCode == 0 else { return }

        let negative = try typecheck(source + """

            nonisolated func invalidExecutor(_ container: ActorContainer) {
                container.prewarm(.some)
            }
            """, named: "invalid.swift", in: directory)
        #expect(!negative.timedOut, Comment(rawValue: negative.combinedOutput))
        #expect(negative.exitCode != 0)
        #expect(negative.combinedOutput.contains("main actor-isolated instance method 'prewarm'"),
                Comment(rawValue: negative.combinedOutput))
        #expect(!negative.combinedOutput.contains("Stack dump:"))
    }

    @Test("Generated tokens preserve global and nested payload types, including separate extensions")
    func payloadTypeIdentityIsPreserved() throws {
        let globalDeclarations = try generatedDeclarations(from: """
            @DIContainer public struct GlobalPayloadContainer {
                @Provide(.shared, initialization: .onDemand, factory: PrewarmProvider.service)
                var service: PrewarmProvider
            }
            """)
        let nestedDeclarations = try generatedDeclarations(from: """
            @DIContainer public struct NestedPayloadContainer {
                public enum PrewarmProvider { case service }
                @Provide(.shared, initialization: .onDemand, factory: PrewarmProvider.service)
                var service: PrewarmProvider
            }
            """)
        let source = """
            public enum PrewarmProvider { case service }
            public typealias OriginalGlobalPayload = PrewarmProvider

            public struct GlobalPayloadContainer {
                public var service: PrewarmProvider { .service }
                \(globalDeclarations)
            }
            public struct NestedPayloadContainer {
                public enum PrewarmProvider { case service }
                public var service: PrewarmProvider { .service }
                \(nestedDeclarations)
            }

            func verifyPayloadTypes(_ global: GlobalPayloadContainer, _ nested: NestedPayloadContainer) {
                // Both payloads and tokens deliberately have `service` cases.
                // Merely compiling the getter would miss silent type capture.
                let _: OriginalGlobalPayload = global.service
                let _: NestedPayloadContainer.PrewarmProvider = nested.service
                let _: OriginalGlobalPayload = global.extensionPayload
                let _: NestedPayloadContainer.PrewarmProvider = nested.extensionPayload
                global.prewarm(.service)
                nested.prewarm(.service)
            }
            """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-TypedPrewarm-Payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensions = directory.appendingPathComponent("PayloadExtensions.swift")
        try """
            extension GlobalPayloadContainer {
                public var extensionPayload: PrewarmProvider { .service }
            }
            extension NestedPayloadContainer {
                public var extensionPayload: PrewarmProvider { .service }
            }
            """.write(to: extensions, atomically: true, encoding: .utf8)
        let result = try typecheck(source, named: "Payloads.swift", in: directory, additionalFiles: [extensions])
        #expect(!result.timedOut, Comment(rawValue: result.combinedOutput))
        #expect(result.exitCode == 0, Comment(rawValue: result.combinedOutput))
    }

    private func emittedContainer(named name: String, mainActor: Bool, names: [String]) throws -> String {
        let members = names.map {
            "@Provide(.shared, initialization: .onDemand, factory: NonSendableValue()) var \($0): NonSendableValue"
        }.joined(separator: "\n")
        let attribute = mainActor
            ? "@DIContainerRole(role: ContainerRole.local, mainActor: true)"
            : "@DIContainer"
        let declarations = try generatedDeclarations(from: """
            \(attribute) public struct \(name) {
                @Input var PrewarmProvider: Int
                @Input var Swift: Int
                \(members)
            }
            """)
        let actorAttribute = mainActor ? "@_Concurrency.MainActor " : ""
        let properties = names.map {
            "\(actorAttribute)public var \($0): NonSendableValue { NonSendableValue() }"
        }.joined(separator: "\n")
        return """
            public struct \(name) {
                public var PrewarmProvider: Int { 7 }
                public var Swift: Int { 0 }
                \(properties)
                \(declarations)
            }
            """
    }

    private func generatedDeclarations(from source: String) throws -> String {
        let syntax = Parser.parse(source: source)
        let declaration = try #require(syntax.statements.first?.item.as(StructDeclSyntax.self))
        let context = TestMacroExpansionContext()
        let model = try #require(DIContainerParser.parse(declaration: declaration, context: context))
        #expect(context.diagnostics.isEmpty)
        let generated = makeTypedPrewarmDecls(model: model)
        #expect(generated.count == 2)
        return generated.map { $0.formatted().description }.joined(separator: "\n")
    }

    private func typecheck(
        _ source: String,
        named name: String,
        in directory: URL,
        additionalFiles: [URL] = []
    ) throws -> CapturedProcessResult {
        let file = directory.appendingPathComponent(name)
        try source.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-typecheck", "-swift-version", "6",
            "-strict-concurrency=complete", "-warnings-as-errors", file.path(percentEncoded: false),
        ] + additionalFiles.map { $0.path(percentEncoded: false) }
        return try runCapturedProcess(process, timeoutSeconds: 60)
    }
}
