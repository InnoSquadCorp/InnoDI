import Foundation
import InnoDIMigrationCore
import Testing

@testable import InnoDIDoctorCore

/// Healthy projects that Doctor used to report as broken, each beside a
/// control that must keep its result.
@Suite("InnoDI doctor workspace boundaries", .serialized)
struct DoctorWorkspaceBoundaryTests {
    private static let healthyContainer = container("AppContainer")

    /// Distinct names keep the root-mode provider graph free of duplicate
    /// identities, which would be a separate graph diagnostic.
    private static func container(_ name: String) -> String {
        "import InnoDI\n@DIContainer struct \(name) { @Input var value: Int }\n"
    }

    private static func manifest(
        swiftVersion: String = "6.2",
        name: String = "App",
        path: String? = nil,
        plugin: Bool = true
    ) -> String {
        let pathArgument = path.map { ",\n            path: \"\($0)\"" } ?? ""
        let plugins = plugin
            ? ",\n            plugins: [.plugin(name: \"InnoDIDAGValidationPlugin\", package: \"InnoDI\")]"
            : ""
        return """
        // swift-tools-version: \(swiftVersion)
        import PackageDescription
        let package = Package(
            name: "\(name)",
            targets: [
                .target(
                    name: "\(name)"\(pathArgument)\(plugins)
                )
            ]
        )
        """
    }

    // MARK: D1 — SwiftUI import access choice

    @Test("A root migrated with an explicit SwiftUI import access is healthy when Doctor gets the same choice")
    func swiftUIImportAccessChoiceCarriesThrough() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            "Sources/App/Screen.swift": "import InnoDISwiftUI\n\nstruct Screen {}\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = root.appendingPathComponent("Sources/App/Screen.swift")

        // The documented write, then the documented checks.
        #expect(MigrationCLI.run(arguments: [
            "--root", root.path, "--write", "--swiftui-import-access", "internal",
        ]) == 0)
        #expect(try String(contentsOf: screen, encoding: .utf8)
            == "import InnoDISwiftUI\ninternal import SwiftUI\n\nstruct Screen {}\n")
        #expect(MigrationCLI.run(arguments: [
            "--root", root.path, "--check", "--swiftui-import-access", "internal",
        ]) == 0)
        let chosen = try InnoDIDoctor(swiftUIImportAccess: .internal).inspect(root: root)
        #expect(chosen.diagnostics.isEmpty)
        #expect(chosen.isHealthy)
        #expect(DoctorCLI.run(arguments: [
            "--root", root.path, "--swiftui-import-access", "internal",
        ]) == 0)

        // Source alone still cannot tell this file from an unmigrated one
        // that wrote `internal import SwiftUI` itself, so a check without
        // the choice keeps refusing to guess and names how to recheck.
        #expect(MigrationCLI.run(arguments: ["--root", root.path, "--check"]) == 2)
        let unchosen = try InnoDIDoctor().inspect(root: root)
        let ambiguity = try #require(unchosen.diagnostics.first {
            $0.id == "migrate.swiftui-import-access-ambiguous"
        })
        #expect(ambiguity.message.contains("rechecked with the same choice"))
        #expect(!unchosen.isHealthy)
    }

    @Test("Doctor apply uses the SwiftUI import access choice and rechecks with it")
    func doctorApplyCarriesSwiftUIImportAccess() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            "Sources/App/Screen.swift": "import InnoDISwiftUI\n\nstruct Screen {}\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor(swiftUIImportAccess: .package).run(
            root: root, apply: true, verify: false
        )

        #expect(report.appliedChangePaths == ["Sources/App/Screen.swift"])
        #expect(report.secondPassChangeCount == 0)
        #expect(report.isHealthy)
        #expect(try String(
            contentsOf: root.appendingPathComponent("Sources/App/Screen.swift"),
            encoding: .utf8
        ).contains("package import SwiftUI"))
    }

    @Test("Control: a root migrated without a choice rechecks clean without one")
    func swiftUIImportWithoutChoiceRechecksClean() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            "Sources/App/Screen.swift": "import InnoDISwiftUI\n\nstruct Screen {}\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(MigrationCLI.run(arguments: ["--root", root.path, "--write"]) == 0)
        #expect(MigrationCLI.run(arguments: ["--root", root.path, "--check"]) == 0)
        #expect(try InnoDIDoctor().inspect(root: root).isHealthy)
        #expect(DoctorCLI.run(arguments: ["--root", root.path]) == 0)
    }

    // MARK: D2 — nested packages and nested Git repositories

    @Test("A container in a nested package is judged against that package's manifest")
    func nestedPackageUsesItsOwnManifest() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            "Examples/Demo/Package.swift": Self.manifest(name: "Demo"),
            "Examples/Demo/Sources/Demo/DemoContainer.swift": Self.container("DemoContainer"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(report.diagnostics.isEmpty)
        #expect(report.isHealthy)
    }

    @Test("A nested package without the plugin is still reported, against its own manifest")
    func nestedPackageMissingPluginIsReported() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            "Examples/Demo/Package.swift": Self.manifest(name: "Demo", plugin: false),
            "Examples/Demo/Sources/Demo/DemoContainer.swift": Self.container("DemoContainer"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        let missing = try #require(report.diagnostics.first { $0.id == "doctor.plugin.missing" })
        #expect(missing.path == "Examples/Demo/Package.swift")
        #expect(missing.message.contains("Target 'Demo'"))
        #expect(missing.message.contains("Examples/Demo/Sources/Demo/DemoContainer.swift"))
        #expect(!report.diagnostics.map(\.id).contains("doctor.plugin.analysis-incomplete"))
        #expect(!report.isHealthy)
    }

    @Test(
        "A nested Git repository is left out of the root's plugin check",
        arguments: [true, false]
    )
    func nestedRepositoryIsSkipped(submoduleFile: Bool) throws {
        var files = [
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            // Without the plugin: a judged nested package would be reported.
            "Vendor/Dependency/Package.swift": Self.manifest(name: "Dependency", plugin: false),
            "Vendor/Dependency/Sources/Dependency/Container.swift": Self.container("DependencyContainer"),
        ]
        if submoduleFile {
            files["Vendor/Dependency/.git"] = "gitdir: ../../.git/modules/Dependency\n"
        } else {
            files["Vendor/Dependency/.git/HEAD"] = "ref: refs/heads/main\n"
        }
        let root = try makeWorkspace(files)
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(report.diagnostics.isEmpty)
        #expect(report.isHealthy)
    }

    @Test("Control: a container outside every target of the root package is still unmappable")
    func unmappedRootContainerIsStillReported() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            "Examples/Demo/DemoContainer.swift": Self.container("DemoContainer"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        let incomplete = try #require(report.diagnostics.first {
            $0.id == "doctor.plugin.analysis-incomplete"
        })
        #expect(incomplete.path == "Examples/Demo/DemoContainer.swift")
        #expect(!report.isHealthy)
    }

    // MARK: D3 — package-root target path

    @Test("A literal target path naming the package directory maps its sources", arguments: [".", "./"])
    func packageRootTargetPath(path: String) throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(path: path),
            "AppContainer.swift": Self.healthyContainer,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(report.diagnostics.isEmpty)
        #expect(report.isHealthy)
    }

    @Test("Control: Sources and ./Sources/App target paths keep mapping")
    func explicitTargetPaths() throws {
        for (path, source) in [("Sources", "Sources/AppContainer.swift"), ("./Sources/App", "Sources/App/AppContainer.swift")] {
            let root = try makeWorkspace([
                "Package.swift": Self.manifest(path: path),
                source: Self.healthyContainer,
            ])
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(try InnoDIDoctor().inspect(root: root).isHealthy)
        }
    }

    @Test("A more specific target wins over a package-root target, and two root targets stay ambiguous")
    func packageRootTargetPrecedence() throws {
        let specific = try makeWorkspace([
            "Package.swift": """
            // swift-tools-version: 6.2
            import PackageDescription
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Root", path: ".", exclude: ["Feature"]),
                    .target(
                        name: "Feature",
                        path: "Feature",
                        plugins: [.plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")]
                    ),
                ]
            )
            """,
            "Feature/FeatureContainer.swift": Self.healthyContainer,
        ])
        defer { try? FileManager.default.removeItem(at: specific) }
        #expect(try InnoDIDoctor().inspect(root: specific).isHealthy)

        let ambiguous = try makeWorkspace([
            "Package.swift": """
            // swift-tools-version: 6.2
            import PackageDescription
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "One", path: "."),
                    .target(name: "Two", path: "./"),
                ]
            )
            """,
            "AppContainer.swift": Self.healthyContainer,
        ])
        defer { try? FileManager.default.removeItem(at: ambiguous) }
        let report = try InnoDIDoctor().inspect(root: ambiguous)
        #expect(report.diagnostics.map(\.id).contains("doctor.plugin.analysis-incomplete"))
    }

    // MARK: D4 — CRLF configuration files

    @Test("A CRLF package manifest declares its tools version")
    func crlfPackageManifest() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest().replacingOccurrences(of: "\n", with: "\r\n"),
            "Sources/App/App.swift": Self.healthyContainer,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(report.diagnostics.isEmpty)
        #expect(report.isHealthy)
    }

    @Test("An old tools version is reported in CRLF manifests as in LF ones (control)", arguments: ["\n", "\r\n"])
    func oldToolsVersionIsReported(lineEnding: String) throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(swiftVersion: "6.1")
                .replacingOccurrences(of: "\n", with: lineEnding),
            "Sources/App/App.swift": Self.healthyContainer,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let ids = try InnoDIDoctor().inspect(root: root).diagnostics.map(\.id)

        #expect(ids.contains("doctor.toolchain.minimum"))
        #expect(!ids.contains("doctor.toolchain.unknown"))
    }

    @Test("A CRLF Tuist project reads SWIFT_VERSION from its own line, as an LF one does (control)", arguments: ["\n", "\r\n"])
    func crlfTuistProject(lineEnding: String) throws {
        let project = """
        import ProjectDescription

        let project = Project(
            name: "DoctorFixture",
            targets: [
                .target(
                    name: "App",
                    destinations: [.mac],
                    product: .framework,
                    bundleId: "dev.innosquad.doctorfixture",
                    deploymentTargets: .macOS("14.0"),
                    sources: ["Sources/App/**"],
                    settings: .settings(base: ["SWIFT_VERSION": "6.1"])
                )
            ]
        )
        """
        let root = try makeWorkspace([
            "Project.swift": project.replacingOccurrences(of: "\n", with: lineEnding),
            "Sources/App/App.swift": Self.healthyContainer,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let ids = try InnoDIDoctor().inspect(root: root).diagnostics.map(\.id)

        // A CRLF file used to be one "line", so `"14.0"` was read as the
        // Swift version and the old toolchain went unreported.
        #expect(ids.contains("doctor.toolchain.minimum"))
    }

    // MARK: Directory links

    @Test("A directory link to a scanned in-root directory does not stop diagnosis")
    func inRootDirectoryLinkIsCovered() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
            "Vendor/Lib.framework/Versions/A/Headers/Lib.h": "// header\n",
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

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(report.isHealthy)
    }

    // MARK: Command line

    @Test("CLI rejects unknown options, positional arguments, missing values, and repeated options")
    func strictArguments() throws {
        let root = try makeWorkspace([
            "Package.swift": Self.manifest(),
            "Sources/App/App.swift": Self.healthyContainer,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(DoctorCLI.run(arguments: ["--root", root.path]) == 0)
        for extra in [
            ["-x"], ["apply"], ["--scheme"], ["--destination", "--json"], ["--root", root.path],
            ["--json", "--json"], ["--swiftui-import-access"], ["--swiftui-import-access", "open"],
            ["--swiftui-import-access", "internal", "--swiftui-import-access", "public"],
        ] {
            #expect(DoctorCLI.run(arguments: ["--root", root.path] + extra) == 64, "\(extra)")
        }
        #expect(DoctorCLI.run(arguments: ["--root", ""]) == 64)
        #expect(DoctorCLI.parse([
            "--root", "R", "--trust-module", "A", "--trust-module", "B",
            "--swiftui-import-access", "public", "--json",
        ]) == .options(.init(
            rootPath: "R",
            json: true,
            trustedModules: ["A", "B"],
            swiftUIImportAccess: .public
        )))
    }

    private func makeWorkspace(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-doctor-boundary-\(UUID().uuidString)", isDirectory: true)
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
