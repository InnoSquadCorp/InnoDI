import Foundation
@testable import InnoDIMigrationCore
import Testing

/// Command-line and root-walk boundaries reported by the 7.1 review, each
/// beside a control that keeps its result.
@Suite("Migration root boundaries", .serialized)
struct MigrationRootBoundaryTests {
    private static let legacy = """
    import InnoDI
    @DIContainer
    struct Container {
        @Provide(.shared, factory: Service(), concrete: true)
        var service: Service
    }
    """

    // MARK: SwiftUI import access recheck

    @Test(
        "A root written with a SwiftUI import access rechecks clean with the same access",
        arguments: [
            // (InnoDISwiftUI import, choice, a check without the choice is clean)
            ("import InnoDISwiftUI", MigrationSwiftUIImportAccess.internal, false),
            ("import InnoDISwiftUI", .package, false),
            ("import InnoDISwiftUI", .public, true),
            ("package import InnoDISwiftUI", .internal, false),
            ("package import InnoDISwiftUI", .package, true),
            ("public import InnoDISwiftUI", .internal, false),
            ("public import InnoDISwiftUI", .public, true),
            ("@_exported import InnoDISwiftUI", .internal, true),
            ("#if DEBUG\nimport InnoDISwiftUI\n#endif", .internal, false),
        ]
    )
    func accessChoiceRechecksClean(
        anchor: String,
        access: MigrationSwiftUIImportAccess,
        cleanWithoutChoice: Bool
    ) throws {
        let root = try makeTree(["Sources/App/Screen.swift": "\(anchor)\n\nstruct Screen {}\n"])
        defer { try? FileManager.default.removeItem(at: root) }

        let written = try InnoDIMigrator(swiftUIImportAccess: access).run(root: root, mode: .write)
        #expect(written.diagnostics.isEmpty)
        #expect(written.changes.map(\.path) == ["Sources/App/Screen.swift"])

        let sameChoice = try InnoDIMigrator(swiftUIImportAccess: access).plan(root: root)
        #expect(sameChoice.diagnostics.isEmpty)
        #expect(sameChoice.changes.isEmpty)

        // Without the choice, an explicit import below the InnoDISwiftUI
        // import's own visibility looks exactly like an unmigrated file that
        // relied on the re-export, so the check still refuses to guess.
        let noChoice = try InnoDIMigrator().plan(root: root)
        #expect(noChoice.changes.isEmpty)
        if cleanWithoutChoice {
            #expect(noChoice.diagnostics.isEmpty)
        } else {
            #expect(noChoice.diagnostics.map(\.code) == ["migrate.swiftui-import-access-ambiguous"])
            #expect(noChoice.diagnostics.first?.message.contains("rechecked with the same choice") == true)
        }
        #expect(MigrationCLI.run(arguments: ["--root", root.path, "--check", "--swiftui-import-access", access.rawValue]) == 0)
        #expect(MigrationCLI.run(arguments: ["--root", root.path, "--check"]) == (cleanWithoutChoice ? 0 : 2))
    }

    // MARK: Missing root

    @Test("A missing root is reported as an invalid root in every mode", arguments: [
        MigrationMode.check, .report, .write,
    ])
    func missingRootIsInvalid(mode: MigrationMode) throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-MissingRoot-\(UUID().uuidString)", isDirectory: true)

        let error = #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(root: missing, mode: mode)
        }
        #expect(error.map(isInvalidRoot) == true)
        #expect(MigrationCLI.run(arguments: ["--root", missing.path, "--check"]) == 2)
    }

    @Test("A file root is reported as an invalid root, not as an anchoring failure")
    func fileRootIsInvalid() throws {
        let root = try makeTree(["Only.swift": "struct Only {}\n"])
        defer { try? FileManager.default.removeItem(at: root) }

        let error = #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(root: root.appendingPathComponent("Only.swift"), mode: .check)
        }
        #expect(error.map(isInvalidRoot) == true)
    }

    // MARK: Directory links

    @Test("A link to a scanned in-root directory is not followed and does not block writes")
    func coveredDirectoryLinkDoesNotBlock() throws {
        let root = try makeTree([
            "Sources/App/App.swift": Self.legacy,
            "Vendor/Lib.framework/Versions/A/Headers/Lib.h": "// header\n",
            "Tools/Product/Package.swift": "// swift-tools-version: 6.2\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let framework = root.appendingPathComponent("Vendor/Lib.framework")
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Versions/Current").path,
            withDestinationPath: "A"
        )
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Headers").path,
            withDestinationPath: "Versions/Current/Headers"
        )
        // A product-test package that links back to a scanned source folder,
        // and a link to the root itself.
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Tools/Product/AppSources").path,
            withDestinationPath: "../../Sources/App"
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Tools/RootAlias").path,
            withDestinationPath: ".."
        )

        let plan = try InnoDIMigrator().run(root: root, mode: .write)

        #expect(plan.diagnostics.isEmpty)
        // Each file is planned once, through its real path.
        #expect(plan.changes.map(\.path) == ["Sources/App/App.swift"])
        #expect(try InnoDIMigrator().plan(root: root).changes.isEmpty)
        #expect(MigrationCLI.run(arguments: ["--root", root.path, "--check"]) == 0)
    }

    @Test(
        "A directory link the walk does not cover still blocks before any write",
        arguments: ["external", "build", "nested-repository", "nested-git-directory"]
    )
    func uncoveredDirectoryLinkBlocks(kind: String) throws {
        let root = try makeTree([
            "Safe.swift": Self.legacy,
            ".build/checkouts/Dependency/Generated.swift": Self.legacy,
            "Vendor/Dependency/.git": "gitdir: ../../.git/modules/Dependency\n",
            "Vendor/Dependency/Sources/Legacy.swift": Self.legacy,
            "Vendor/Other/.git/HEAD": "ref: refs/heads/main\n",
            "Vendor/Other/Sources/Legacy.swift": Self.legacy,
        ])
        let external = try makeTree(["External.swift": Self.legacy])
        defer { try? FileManager.default.removeItem(at: root) }
        defer { try? FileManager.default.removeItem(at: external) }
        let destination = switch kind {
        case "external": external.path
        case "build": root.appendingPathComponent(".build/checkouts/Dependency").path
        case "nested-repository": root.appendingPathComponent("Vendor/Dependency/Sources").path
        default: root.appendingPathComponent("Vendor/Other").path
        }
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("SourcesAlias").path,
            withDestinationPath: destination
        )

        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().plan(root: root)
        }
        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().run(root: root, mode: .write)
        }
        #expect(try String(contentsOf: root.appendingPathComponent("Safe.swift"), encoding: .utf8) == Self.legacy)
    }

    @Test("Control: a Swift file link to a scanned in-root source still blocks")
    func swiftFileLinkStillBlocks() throws {
        let root = try makeTree(["Safe.swift": Self.legacy, "Targets/Target.swift": Self.legacy])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Linked.swift").path,
            withDestinationPath: "Targets/Target.swift"
        )

        #expect(throws: MigrationError.self) {
            try InnoDIMigrator().plan(root: root)
        }
    }

    private func isInvalidRoot(_ error: MigrationError) -> Bool {
        if case .invalidRoot = error { return true }
        return false
    }

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-RootBoundary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }
        return root
    }
}
