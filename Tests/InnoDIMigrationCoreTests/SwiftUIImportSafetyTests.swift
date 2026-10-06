import Foundation
import InnoDITestSupport
@testable import InnoDIMigrationCore
import SwiftParser
import Testing

@Suite("SwiftUI import migration safety", .serialized)
struct SwiftUIImportSafetyTests {
    private func migrated(_ source: String, access: MigrationSwiftUIImportAccess? = nil) -> String {
        addingSwiftUIImportForInnoDISwiftUI(to: Parser.parse(source: source), access: access).description
    }

    @Test("An existing explicit internal import is not replaced with an ambiguous default",
          arguments: ["internal import SwiftUI", "@preconcurrency\ninternal import SwiftUI",
                      "internal /* keep */ import SwiftUI", "internal // keep\nimport SwiftUI"])
    func preservesExplicitInternalImport(_ existing: String) {
        let source = "import InnoDISwiftUI\n\(existing)\n"
        #expect(migrated(source) == source)
    }

    @Test("Raising access preserves attribute boundaries and modifier comments",
          arguments: ["@preconcurrency\ninternal /* keep */ import SwiftUI",
                      "@preconcurrency\nimport SwiftUI",
                      "@preconcurrency\r\ninternal // keep\r\nimport SwiftUI"])
    func preservesAttributeAndModifierTrivia(_ existing: String) {
        let source = "public import InnoDISwiftUI\n\(existing)\n"
        let expected = "public import InnoDISwiftUI\n\(existing.replacingOccurrences(of: "internal", with: "public"))\n"
        let output = migrated(source, access: .public)
        if existing.contains("internal") {
            #expect(output == expected)
        } else {
            #expect(output == "public import InnoDISwiftUI\n@preconcurrency\npublic import SwiftUI\n")
        }
        #expect(!Parser.parse(source: output).hasError)
        #expect(migrated(output, access: .public) == output)
    }

    @Test("Inserted imports copy indentation but not block comments")
    func doesNotCopyCommentsAsIndentation() {
        let source = "#if DEBUG\n    /* Keep once */ import InnoDISwiftUI\n#endif\n"
        let expected = "#if DEBUG\n    /* Keep once */ import InnoDISwiftUI\n    import SwiftUI\n#endif\n"
        #expect(migrated(source) == expected)
        #expect(migrated(expected) == expected)
    }

    @Test("Original and migrated imports compile with attributes and cross-file access")
    func compilerChecksSemanticOutput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-ImportSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let flags = ["-swift-version", "6", "-module-cache-path", root.appendingPathComponent("cache").path]
        for name in ["SwiftUI", "InnoDISwiftUI"] {
            let source = root.appendingPathComponent("\(name).swift")
            try "public struct ImportProbeValue {}\n".write(to: source, atomically: true, encoding: .utf8)
            try runCompiler(flags + ["-emit-module", "-module-name", name, source.path,
                                     "-emit-module-path", root.appendingPathComponent("\(name).swiftmodule").path], root: root)
        }
        let other = root.appendingPathComponent("Other.swift")
        try "internal import SwiftUI\n".write(to: other, atomically: true, encoding: .utf8)
        let cases: [(String, Bool, MigrationSwiftUIImportAccess)] = [
            ("import InnoDISwiftUI\ninternal import SwiftUI\n", true, .internal),
            ("public import InnoDISwiftUI\n@preconcurrency\ninternal import SwiftUI\n", false, .public),
            ("public import InnoDISwiftUI\n@preconcurrency\nimport SwiftUI\n", false, .public),
        ]
        for (source, includeOther, access) in cases {
            let file = root.appendingPathComponent("Consumer.swift")
            for text in [source, migrated(source, access: access)] {
                try text.write(to: file, atomically: true, encoding: .utf8)
                try runCompiler(flags + ["-typecheck", "-module-name", "Consumer", "-I", root.path, file.path]
                                + (includeOther ? [other.path] : []), root: root)
            }
        }
    }

    @Test("Ambiguous import access preserves the source and requires an explicit choice")
    func ambiguousAccessDoesNotGuess() {
        let cases = [
            "import InnoDISwiftUI\ninternal import SwiftUI\n",
            "public import InnoDISwiftUI\ninternal import SwiftUI\n",
            "public import InnoDISwiftUI\n",
            "package import InnoDISwiftUI\ninternal import SwiftUI\n",
            "package import InnoDISwiftUI\n",
        ]
        for source in cases {
            var messages: [String] = []
            let output = addingSwiftUIImportForInnoDISwiftUI(to: Parser.parse(source: source)) {
                messages.append($0)
            }.description
            #expect(output == source)
            #expect(messages.count == 1)
            #expect(messages.first?.contains("--swiftui-import-access internal") == true)
            #expect(messages.first?.contains("--swiftui-import-access public") == true)
        }
        let source = "import InnoDISwiftUI\n"
        var messages: [String] = []
        let output = addingSwiftUIImportForInnoDISwiftUI(
            to: Parser.parse(source: source), hasOtherExplicitSwiftUIImports: true
        ) { messages.append($0) }.description
        #expect(output == source)
        #expect(messages.count == 1)
    }

    @Test("An exported import is always explicitly public, including an internal override choice")
    func exportedImportRetainsPublicAccess() {
        let source = "@_exported import InnoDISwiftUI\ninternal /* keep */ import SwiftUI\n"
        let expected = "@_exported import InnoDISwiftUI\n@_exported public /* keep */ import SwiftUI\n"
        #expect(migrated(source) == expected)
        #expect(migrated(source, access: .internal) == expected)
        #expect(migrated(expected) == expected)
    }

    @Test("Explicit access preserves public API and re-export under both import defaults")
    func oldAndNewModuleContractsCompile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-ImportContract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let swiftUI = root.appendingPathComponent("SwiftUI.swift")
        try "public struct ImportProbeValue { public init() {} }\n".write(to: swiftUI, atomically: true, encoding: .utf8)
        let flags = ["-swift-version", "6", "-module-cache-path", root.appendingPathComponent("cache").path]
        try runCompiler(flags + ["-emit-module", "-module-name", "SwiftUI", swiftUI.path,
                                 "-emit-module-path", root.appendingPathComponent("SwiftUI.swiftmodule").path], root: root)
        let anchor = root.appendingPathComponent("InnoDISwiftUI.swift")
        let consumer = root.appendingPathComponent("Consumer.swift")
        let client = root.appendingPathComponent("Client.swift")
        let newAnchor = "public struct InnoDIProbe { public init() {} }\n"
        let oldAnchor = "@_exported public import SwiftUI\n" + newAnchor
        for upcoming in [false, true] {
            let mode = flags + (upcoming ? ["-enable-upcoming-feature", "InternalImportsByDefault"] : [])
            for exported in [false, true] {
                let prefix = exported ? "@_exported " : ""
                let original = "\(prefix)public import InnoDISwiftUI\ninternal import SwiftUI\npublic func make() -> ImportProbeValue { .init() }\npublic func own() -> InnoDIProbe { .init() }\n"
                for (moduleSource, text) in [(oldAnchor, original), (newAnchor, migrated(original, access: .public))] {
                    try moduleSource.write(to: anchor, atomically: true, encoding: .utf8)
                    try runCompiler(mode + ["-emit-module", "-module-name", "InnoDISwiftUI", "-I", root.path, anchor.path,
                                            "-emit-module-path", root.appendingPathComponent("InnoDISwiftUI.swiftmodule").path], root: root)
                    try text.write(to: consumer, atomically: true, encoding: .utf8)
                    try runCompiler(mode + ["-warnings-as-errors", "-emit-module", "-module-name", "Consumer", "-I", root.path,
                                            consumer.path, "-emit-module-path", root.appendingPathComponent("Consumer.swiftmodule").path], root: root)
                    if exported {
                        try "import Consumer\nfunc value() -> ImportProbeValue { make() }\n".write(to: client, atomically: true, encoding: .utf8)
                        try runCompiler(mode + ["-warnings-as-errors", "-typecheck", "-I", root.path, client.path], root: root)
                    }
                }
            }
            let internalSource = "import InnoDISwiftUI\nfunc make() -> ImportProbeValue { .init() }\n"
            let other = root.appendingPathComponent("Other.swift")
            try "internal import SwiftUI\n".write(to: other, atomically: true, encoding: .utf8)
            for (moduleSource, text) in [(oldAnchor, internalSource), (newAnchor, migrated(internalSource, access: .internal))] {
                try moduleSource.write(to: anchor, atomically: true, encoding: .utf8)
                try runCompiler(mode + ["-emit-module", "-module-name", "InnoDISwiftUI", "-I", root.path, anchor.path,
                                        "-emit-module-path", root.appendingPathComponent("InnoDISwiftUI.swiftmodule").path], root: root)
                try text.write(to: consumer, atomically: true, encoding: .utf8)
                try runCompiler(mode + ["-warnings-as-errors", "-typecheck", "-module-name", "Consumer", "-I", root.path,
                                        consumer.path, other.path], root: root)
            }
            let packageMode = mode + ["-package-name", "MigrationProbe"]
            for access in [MigrationSwiftUIImportAccess.internal, .package] {
                let visibility = access == .package ? "package " : ""
                let packageSource = "package import InnoDISwiftUI\ninternal import SwiftUI\n\(visibility)func make() -> ImportProbeValue { .init() }\npackage func own() -> InnoDIProbe { .init() }\n"
                for (moduleSource, text) in [(oldAnchor, packageSource), (newAnchor, migrated(packageSource, access: access))] {
                    try moduleSource.write(to: anchor, atomically: true, encoding: .utf8)
                    try runCompiler(packageMode + ["-emit-module", "-module-name", "InnoDISwiftUI", "-I", root.path, anchor.path,
                                                   "-emit-module-path", root.appendingPathComponent("InnoDISwiftUI.swiftmodule").path], root: root)
                    try text.write(to: consumer, atomically: true, encoding: .utf8)
                    try runCompiler(packageMode + ["-warnings-as-errors", "-typecheck", "-module-name", "Consumer", "-I", root.path,
                                                   consumer.path], root: root)
                }
            }
        }
    }

    @Test("Normalized mixed-file imports compile before and after re-export removal in both default modes")
    func normalizedMixedFileImportsCompile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-MixedImportCompiler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let swiftUI = root.appendingPathComponent("SwiftUI.swift")
        let anchor = root.appendingPathComponent("InnoDISwiftUI.swift")
        let consumer = root.appendingPathComponent("Consumer.swift")
        let peer = root.appendingPathComponent("Peer.swift")
        try "public struct ImportValue { public init() {} }\n".write(to: swiftUI, atomically: true, encoding: .utf8)
        let source = "internal import InnoDISwiftUI\nfunc own() -> AnchorValue { .init() }\nfunc make() -> ImportValue { .init() }\n"
        let normalizedPeer = "internal import SwiftUI\nfunc peer() -> ImportValue { .init() }\n"
        let flags = ["-swift-version", "6", "-module-cache-path", root.appendingPathComponent("cache").path]
        for internalDefault in [false, true] {
            let mode = flags + (internalDefault ? ["-enable-upcoming-feature", "InternalImportsByDefault"] : [])
            try runCompiler(mode + ["-emit-module", "-module-name", "SwiftUI", swiftUI.path,
                                    "-emit-module-path", root.appendingPathComponent("SwiftUI.swiftmodule").path], root: root)
            for migratedVersion in [false, true] {
                let reexport = migratedVersion ? "" : "@_exported public import SwiftUI\n"
                try (reexport + "public struct AnchorValue { public init() {} }\n")
                    .write(to: anchor, atomically: true, encoding: .utf8)
                try runCompiler(mode + ["-emit-module", "-module-name", "InnoDISwiftUI", "-I", root.path, anchor.path,
                                        "-emit-module-path", root.appendingPathComponent("InnoDISwiftUI.swiftmodule").path], root: root)
                let text = migratedVersion ? migrated(source, access: .internal) : source
                try text.write(to: consumer, atomically: true, encoding: .utf8)
                try normalizedPeer.write(to: peer, atomically: true, encoding: .utf8)
                try runCompiler(mode + ["-warnings-as-errors", "-typecheck", "-module-name", "Consumer", "-I", root.path,
                                        consumer.path, peer.path], root: root)
            }
        }
    }

    private func runCompiler(_ arguments: [String], root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        process.currentDirectoryURL = root
        let result = try runCapturedProcess(process, timeoutSeconds: 60)
        #expect(!result.timedOut)
        #expect(result.exitCode == 0, Comment(rawValue: result.combinedOutput))
    }
}
