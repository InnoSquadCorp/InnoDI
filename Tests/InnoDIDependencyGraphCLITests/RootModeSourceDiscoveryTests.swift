import Foundation
import InnoDIWorkspaceAnalysis
import Testing

/// `--root` discovery: symbolic links, Xcode derived-data and package
/// checkout directories, and links that leave the root. Each defect shape
/// runs beside a control the CLI already handled.
@Suite("Root-mode source discovery")
struct RootModeSourceDiscoveryTests {
    private static let sharedContainer = """
    import InnoDI

    @DIContainer
    struct SharedContainer {
        @Provide(.shared, factory: 1)
        var value: Int
    }
    """

    // MARK: Symbolic link inside the root (analyzed once, no trap)

    @Test("A file linked from another directory inside the root is analyzed once")
    func inRootSymlinkIsAnalyzedOnce() throws {
        let root = try makeDiscoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Self.sharedContainer, to: root, "Sources/Shared/Shared.swift")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/AppA", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Sources/AppA/Shared.swift").path,
            withDestinationPath: "../Shared/Shared.swift"
        )

        #expect(
            try discoverWorkspaceSourceFiles(rootPath: root.path)
                == ["Sources/Shared/Shared.swift"]
        )
        let snapshot = try loadWorkspaceSourceSnapshot(rootPath: root.path)
        #expect(snapshot.files.map(\.relativePath) == ["Sources/Shared/Shared.swift"])
        #expect(snapshot.externalSourceLinks.isEmpty)

        let validation = try runCLI(["--root", root.path, "--validate-dag"])
        #expect(validation.exitCode == 0)
        #expect(validation.stdout == "DAG validation passed.\n")
        #expect(validation.stderr.isEmpty)

        let rendered = try runCLI(["--root", root.path, "--root-pruning", "all"])
        #expect(rendered.exitCode == 0)
        #expect(rendered.stdout.contains("    N0[\"SharedContainer\"]\n"))
        #expect(!rendered.stdout.contains("N1"))
    }

    @Test("Control: the same tree without the link, or with a physical copy")
    func inRootSymlinkControls() throws {
        for withCopy in [false, true] {
            let root = try makeDiscoveryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            try write(Self.sharedContainer, to: root, "Sources/Shared/Shared.swift")
            if withCopy {
                try write(Self.sharedContainer, to: root, "Sources/AppA/Shared.swift")
            }

            let validation = try runCLI(["--root", root.path, "--validate-dag"])
            #expect(validation.exitCode == 0)
            #expect(validation.stdout == "DAG validation passed.\n")
            #expect(
                try discoverWorkspaceSourceFiles(rootPath: root.path).count
                    == (withCopy ? 2 : 1)
            )
        }
    }

    @Test("The deferred-alias scan lists an alias reached through an in-root link once")
    func aliasScanDeduplicatesLinkedFile() throws {
        let root = try makeDiscoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            "import InnoDI\ntypealias LazyInt = Lazy<Int>\n",
            to: root,
            "Sources/Shared/Aliases.swift"
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/AppA", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Sources/AppA/Aliases.swift").path,
            withDestinationPath: "../Shared/Aliases.swift"
        )

        let findings = scanDeferredWrapperAliases(
            in: try loadWorkspaceSourceSnapshot(rootPath: root.path)
        )

        #expect(findings.map(\.aliasName) == ["LazyInt"])
        #expect(findings.map(\.relativePath) == ["Sources/Shared/Aliases.swift"])
    }

    // MARK: Xcode derived data and package checkouts inside the root

    private static let appSource = """
    import InnoDI

    @DIContainerRole(role: ContainerRole.root)
    struct AppContainer {
        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: 1)
        var value: Int
    }
    """

    /// A dependency checkout that declares its own `FeatureContainer`, as
    /// InnoDI's own `Examples` do.
    private static let checkoutSource = """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: 2)
        var other: Int
    }
    """

    @Test(
        "Xcode derived-data and package checkout directories are skipped",
        arguments: [
            "DerivedData/App/SourcePackages/checkouts/Dependency/Examples/Feature.swift",
            "SourcePackages/checkouts/Dependency/Examples/Feature.swift",
            "Nested/DerivedData/Build/Feature.swift",
        ]
    )
    func xcodeDirectoriesAreSkipped(checkoutPath: String) throws {
        let root = try makeDiscoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Self.appSource, to: root, "App/App.swift")
        try write(Self.checkoutSource, to: root, checkoutPath)

        #expect(try discoverWorkspaceSourceFiles(rootPath: root.path) == ["App/App.swift"])
        let validation = try runCLI(["--root", root.path, "--validate-dag"])
        #expect(validation.exitCode == 0)
        #expect(validation.stdout == "DAG validation passed.\n")
        #expect(!validation.stderr.contains("graph.ambiguous-container-reference"))
    }

    @Test("Control: SwiftPM checkouts were already skipped; similar names are not")
    func xcodeSkipControls() throws {
        let root = try makeDiscoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Self.appSource, to: root, "App/App.swift")
        try write(Self.checkoutSource, to: root, ".build/checkouts/Dependency/Feature.swift")
        try write("struct Kept {}\n", to: root, "Sources/MyDerivedDataTools/Kept.swift")
        try write("struct Kept2 {}\n", to: root, "Sources/SourcePackagesKit/Kept2.swift")

        #expect(
            try discoverWorkspaceSourceFiles(rootPath: root.path) == [
                "App/App.swift",
                "Sources/MyDerivedDataTools/Kept.swift",
                "Sources/SourcePackagesKit/Kept2.swift",
            ]
        )
        let validation = try runCLI(["--root", root.path, "--validate-dag"])
        #expect(validation.exitCode == 0)
    }

    // MARK: Swift source linked from outside the root

    private static let appContainer = """
    import InnoDI
    @DIContainer
    struct AppContainer {
        @Provide(.shared, factory: 42)
        var value: Int
    }
    """

    private static let externalContainer = """
    import InnoDI
    @DIContainer struct Ext { @Provide(.shared, factory: AppContainer()) var a: AppContainer }
    """

    @Test("A source linked from outside the root is named on stderr; output and exit code are unchanged")
    func externalSymlinkIsReported() throws {
        let root = try makeDiscoveryRoot()
        let outside = try makeDiscoveryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try write(Self.appContainer, to: root, "Sources/App/App.swift")
        try write(Self.externalContainer, to: outside, "Ext.swift")
        let destination = outside.appendingPathComponent("Ext.swift").path
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Sources/App/Ext.swift").path,
            withDestinationPath: destination
        )

        let discovery = try discoverWorkspaceSources(rootPath: root.path)
        #expect(discovery.relativePaths == ["Sources/App/App.swift"])
        let link = try #require(discovery.externalSourceLinks.first)
        #expect(discovery.externalSourceLinks.count == 1)
        #expect(link.relativePath == "Sources/App/Ext.swift")
        #expect(link.destinationPath.hasSuffix("/Ext.swift"))
        #expect(
            URL(fileURLWithPath: link.destinationPath).resolvingSymlinksInPath()
                == URL(fileURLWithPath: destination).resolvingSymlinksInPath()
        )

        let withoutLink = try makeDiscoveryRoot()
        defer { try? FileManager.default.removeItem(at: withoutLink) }
        try write(Self.appContainer, to: withoutLink, "Sources/App/App.swift")

        for arguments in [["--validate-dag"], ["--root-pruning", "all"]] {
            let result = try runCLI(["--root", root.path] + arguments)
            let control = try runCLI(["--root", withoutLink.path] + arguments)

            #expect(result.exitCode == 0)
            #expect(result.stdout == control.stdout)
            #expect(control.stderr.isEmpty)
            #expect(
                result.stderr
                    == "warning: skipped 'Sources/App/Ext.swift': the symbolic link "
                    + "resolves outside the workspace root to '\(link.destinationPath)', "
                    + "so its declarations are not analyzed.\n"
            )
        }
    }

    @Test("Control: a physical copy of the outside file is analyzed")
    func externalCopyIsAnalyzed() throws {
        let root = try makeDiscoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Self.appContainer, to: root, "Sources/App/App.swift")
        try write(Self.externalContainer, to: root, "Sources/App/Ext.swift")

        let rendered = try runCLI(["--root", root.path, "--root-pruning", "all"])

        #expect(rendered.exitCode == 0)
        #expect(rendered.stderr.isEmpty)
        #expect(rendered.stdout.contains("N1[\"Ext\"]"))
        #expect(rendered.stdout.contains("N1 --> N0"))
        #expect(try discoverWorkspaceSources(rootPath: root.path).externalSourceLinks.isEmpty)
    }

    @Test("Control: links to outside directories and dangling links are not reported")
    func externalNonSourceLinksAreNotReported() throws {
        let root = try makeDiscoveryRoot()
        let outside = try makeDiscoveryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try write(Self.appContainer, to: root, "Sources/App/App.swift")
        try write("struct Elsewhere {}\n", to: outside, "Vendor/Elsewhere.swift")
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Sources/Vendor").path,
            withDestinationPath: outside.appendingPathComponent("Vendor").path
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Sources/App/Dangling.swift").path,
            withDestinationPath: outside.appendingPathComponent("Missing.swift").path
        )

        let discovery = try discoverWorkspaceSources(rootPath: root.path)

        #expect(discovery.relativePaths == ["Sources/App/App.swift"])
        #expect(discovery.externalSourceLinks.isEmpty)
    }
}

private func makeDiscoveryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-RootDiscovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ contents: String, to root: URL, _ relativePath: String) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
