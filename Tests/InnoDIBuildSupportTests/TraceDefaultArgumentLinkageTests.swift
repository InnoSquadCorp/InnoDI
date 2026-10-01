import Foundation
import InnoDITestSupport
import Testing

/// Generated initializers and `withOverrides` overloads end with
/// `_innoDITrace: DITraceContext = .disabled`. Swift emits a default argument
/// into the calling module, so a caller that referenced an InnoDI symbol for
/// it had to link InnoDI. An Xcode test bundle that links a framework holding
/// containers, but not InnoDI, then failed to link.
@Suite("Trace default argument linkage", .serialized, .tags(.slow))
struct TraceDefaultArgumentLinkageTests {
    @Test("Calling a generated initializer's trace default references no InnoDI symbol")
    func traceDefaultNeedsNoInnoDISymbol() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-trace-default-linkage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtimeSources = try FileManager.default.contentsOfDirectory(
            at: packageRootURL().appendingPathComponent("Sources/InnoDI"),
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .map(\.path)
        .sorted()
        try #require(!runtimeSources.isEmpty)
        try compile(
            ["-module-name", "InnoDI", "-suppress-warnings"]
                + moduleOutput(named: "InnoDI", in: directory)
                + runtimeSources,
            in: directory
        )
        // The same trailing parameter the container macros generate, plus a
        // control whose default reads an ordinary stored static property.
        try compile(
            ["-module-name", "Feature"] + moduleOutput(named: "Feature", in: directory),
            source: """
                import InnoDI

                public struct FeatureContainer {
                    public init(_innoDITrace: DITraceContext = .disabled) {}
                    public init(control: Void, owner: _InnoDITraceOwner = .disabled) {}
                }
                """,
            named: "Feature.swift",
            in: directory
        )
        let caller = try objectFile(
            named: "Caller",
            source: "import Feature\npublic func make() -> FeatureContainer { FeatureContainer() }",
            in: directory
        )
        let control = try objectFile(
            named: "Control",
            source: "import Feature\npublic func make() -> FeatureContainer { FeatureContainer(control: ()) }",
            in: directory
        )

        // A mangled symbol that InnoDI defines starts with `$s6InnoDI`.
        let controlReferences = try innoDIReferences(in: control)
        #expect(!controlReferences.isEmpty, "the control should reference InnoDI")
        let callerReferences = try innoDIReferences(in: caller)
        #expect(callerReferences.isEmpty, "\(callerReferences)")
    }

    private func moduleOutput(named name: String, in directory: URL) -> [String] {
        ["-emit-module", "-emit-module-path", directory.appendingPathComponent("\(name).swiftmodule").path]
    }

    private func objectFile(named name: String, source: String, in directory: URL) throws -> URL {
        let object = directory.appendingPathComponent("\(name).o")
        try compile(
            ["-module-name", name, "-c", "-o", object.path],
            source: source,
            named: "\(name).swift",
            in: directory
        )
        return object
    }

    private func compile(
        _ arguments: [String],
        source: String,
        named fileName: String,
        in directory: URL
    ) throws {
        let file = directory.appendingPathComponent(fileName)
        try source.write(to: file, atomically: true, encoding: .utf8)
        try compile(arguments + [file.path], in: directory)
    }

    private func compile(_ arguments: [String], in directory: URL) throws {
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        compiler.currentDirectoryURL = directory
        compiler.arguments = ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6", "-I", directory.path]
            + arguments
        let result = try runCapturedProcess(compiler, timeoutSeconds: 120)
        try #require(!result.timedOut && result.exitCode == 0, "\(result.stderr)")
    }

    private func innoDIReferences(in object: URL) throws -> [String] {
        let nm = Process()
        nm.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        nm.arguments = ["xcrun", "nm", "-u", object.path]
        let result = try runCapturedProcess(nm, timeoutSeconds: 30)
        try #require(!result.timedOut && result.exitCode == 0, "\(result.stderr)")
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("_$s6InnoDI") }
    }
}
