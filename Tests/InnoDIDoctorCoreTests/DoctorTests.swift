import Foundation
import Testing

@testable import InnoDIDoctorCore

private let tuistIntegrationTestsAreAvailable = ProcessInfo.processInfo.environment["PATH"]?
    .split(separator: ":")
    .map(String.init)
    .contains { directory in
        FileManager.default.isExecutableFile(
            atPath: URL(fileURLWithPath: directory)
                .appendingPathComponent("tuist")
                .path
        )
    } == true

@Suite("InnoDI doctor", .serialized)
struct DoctorTests {
    @Test("read-only diagnosis reports toolchain, plugin, scope, and migration without writes")
    func readOnlyDiagnosis() throws {
        let root = try temporaryPackage(
            manifest: packageManifest(swiftVersion: "6.1"),
            source: "import InnoDI\n@DIContainer struct App { @Provide(.input) var value: Int }"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Sources/App/App.swift")
        let before = try Data(contentsOf: sourceURL)

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(Set(report.diagnostics.map(\.id)).isSuperset(of: [
            "doctor.toolchain.minimum", "doctor.plugin.missing",
        ]))
        #expect(report.proposedChangePaths == ["Sources/App/App.swift"])
        #expect(report.appliedChangePaths.isEmpty)
        #expect(try Data(contentsOf: sourceURL) == before)
        #expect(report.verification.status == .notRun)
        #expect(report.graphVerification.status == .unchanged)
    }

    @Test("explicit apply is idempotent and leaves verification separate")
    func applyAndSecondPass() throws {
        let root = try temporaryPackage(
            manifest: packageManifest(swiftVersion: "6.2", appHasPlugin: true),
            source: "import InnoDI\n@DIContainer struct App { @Provide(.input) var value: Int }"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().run(root: root, apply: true, verify: false)

        #expect(report.appliedChangePaths == ["Sources/App/App.swift"])
        #expect(report.secondPassChangeCount == 0)
        #expect(report.verification.status == .notRun)
        #expect(report.graphVerification.status == .unchanged)
        #expect(report.isHealthy)
        #expect(try String(contentsOf: root.appendingPathComponent("Sources/App/App.swift"), encoding: .utf8).contains("@Input"))
        #expect(DoctorCLI.run(arguments: ["--root", root.path, "--apply"]) == 0)
    }

    @Test("opt-in verification builds a healthy package")
    func verifiesBuildSeparately() throws {
        let root = try temporaryPackage(
            manifest: """
            // swift-tools-version: 6.2
            import PackageDescription
            let package = Package(
                name: "DoctorFixture",
                products: [.library(name: "App", targets: ["App"])],
                targets: [.target(name: "App")]
            )
            """,
            source: "public struct Value { public init() {} }"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().run(
            root: root,
            apply: false,
            verify: true
        )

        #expect(report.verification.status == .passed)
        #expect(report.verification.command == "swift build")
        #expect(report.verification.exitCode == 0)
        #expect(report.verification.generation.status == .notRun)
        #expect(report.verification.compilation.status == .passed)
        #expect(report.isHealthy)
    }

    @Test("Tuist verification reports generation and compilation separately")
    func verifiesTuistGenerationAndCompilation() throws {
        let root = try temporaryTuistProject(
            source: "public struct AppValue { public init() {} }"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = try fakeVerificationTools(xcodebuildExitCode: 0)
        defer { try? FileManager.default.removeItem(at: tools.root) }

        let report = try tools.doctor.run(
            root: root,
            apply: false,
            verify: true,
            tuistScheme: "App",
            destination: "platform=macOS"
        )

        #expect(report.verification.generation.status == .passed)
        #expect(report.verification.compilation.status == .passed)
        #expect(report.verification.compilation.command?.contains("xcodebuild") == true)
        #expect(report.verification.compilation.timedOut == false)
        #expect(report.verification.status == .passed)
        #expect(report.isHealthy)
    }

    @Test("Tuist generation without an explicit build selection remains unverified")
    func tuistRequiresExplicitBuildSelection() throws {
        let root = try temporaryTuistProject(
            source: "public struct AppValue { public init() {} }"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = try fakeVerificationTools(xcodebuildExitCode: 0)
        defer { try? FileManager.default.removeItem(at: tools.root) }

        let report = try tools.doctor.run(
            root: root,
            apply: false,
            verify: true
        )

        #expect(report.verification.generation.status == .passed)
        #expect(report.verification.compilation.status == .unverified)
        #expect(report.verification.status == .unverified)
        #expect(!report.isHealthy)
    }

    @Test("Tuist generation success cannot hide compilation failure")
    func tuistCompilationFailureFailsVerification() throws {
        let root = try temporaryTuistProject(
            source: "public let broken: String = 42"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = try fakeVerificationTools(xcodebuildExitCode: 1)
        defer { try? FileManager.default.removeItem(at: tools.root) }

        let report = try tools.doctor.run(
            root: root,
            apply: false,
            verify: true,
            tuistScheme: "App",
            destination: "platform=macOS"
        )

        #expect(report.verification.generation.status == .passed)
        #expect(report.verification.compilation.status == .failed)
        #expect(report.verification.compilation.exitCode != 0)
        #expect(report.verification.compilation.outputTail?.contains("error:") == true)
        #expect(report.verification.status == .failed)
        #expect(!report.isHealthy)
    }

    @Test(
        "Installed Tuist generates and compiles a real macOS workspace",
        .disabled(if: !tuistIntegrationTestsAreAvailable, "Tuist is not installed")
    )
    func realTuistIntegrationBuilds() throws {
        let root = try temporaryTuistProject(
            source: "public struct AppValue { public init() {} }"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().run(
            root: root,
            apply: false,
            verify: true,
            tuistScheme: "App",
            destination: "platform=macOS"
        )

        #expect(report.verification.status == .passed)
        #expect(report.verification.generation.status == .passed)
        #expect(report.verification.compilation.status == .passed)
    }

    @Test("Tuist workspaces use the nested dependency manifest and project plugin declaration")
    func diagnosesTuistWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "innodi-doctor-tuist-\(UUID().uuidString)",
                isDirectory: true
            )
        let sources = root.appendingPathComponent("Sources/App", isDirectory: true)
        let tuist = root.appendingPathComponent("Tuist", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sources,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tuist,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("// workspace marker\n".utf8).write(
            to: root.appendingPathComponent("Workspace.swift")
        )
        try Data("// InnoDIDAGValidationPlugin\n".utf8).write(
            to: root.appendingPathComponent("Project.swift")
        )
        try Data("// swift-tools-version: 6.2\nimport PackageDescription\n".utf8).write(
            to: tuist.appendingPathComponent("Package.swift")
        )
        try Data("import InnoDI\n@DIContainer struct App {}\n".utf8).write(
            to: sources.appendingPathComponent("App.swift")
        )

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(!report.diagnostics.map(\.id).contains("doctor.package-manifest.missing"))
        #expect(report.diagnostics.map(\.id).contains("doctor.plugin.analysis-incomplete"))
        #expect(report.scannedSwiftFileCount == 4)
        #expect(!report.isHealthy)
    }

    @Test("Tuist direct-package workspaces use Tuist.swift without a second package manifest")
    func diagnosesTuistDirectPackageWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "innodi-doctor-tuist-direct-\(UUID().uuidString)",
                isDirectory: true
            )
        let sources = root.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sources,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("// workspace marker\n".utf8).write(
            to: root.appendingPathComponent("Workspace.swift")
        )
        try Data("// InnoDIDAGValidationPlugin\n".utf8).write(
            to: root.appendingPathComponent("Project.swift")
        )
        try Data("let tuist = Tuist(project: .tuist(swiftVersion: \"6.3\"))\n".utf8).write(
            to: root.appendingPathComponent("Tuist.swift")
        )
        try Data("import InnoDI\n@DIContainer struct App {}\n".utf8).write(
            to: sources.appendingPathComponent("App.swift")
        )

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(!report.diagnostics.map(\.id).contains("doctor.package-manifest.missing"))
        #expect(!report.diagnostics.map(\.id).contains("doctor.toolchain.unknown"))
        #expect(report.diagnostics.map(\.id).contains("doctor.plugin.analysis-incomplete"))
        #expect(!report.isHealthy)
    }

    @Test("comments and another target plugin cannot hide a missing target attachment")
    func pluginRelationshipIsTargetScoped() throws {
        let root = try temporaryPackage(
            manifest: """
            // swift-tools-version: 6.2
            import PackageDescription
            // InnoDIDAGValidationPlugin is intentionally only a comment here.
            let package = Package(
                name: "DoctorFixture",
                targets: [
                    .target(name: "App"),
                    .target(
                        name: "Other",
                        plugins: [
                            .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
                        ]
                    )
                ]
            )
            """,
            source: "import InnoDI\n@DIContainer struct App {}"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        let missing = try #require(
            report.diagnostics.first { $0.id == "doctor.plugin.missing" }
        )
        #expect(missing.message.contains("Target 'App'"))
        #expect(!missing.message.contains("Other"))
        #expect(!report.isHealthy)
    }

    @Test("partial DIContainerRole migration applies and becomes healthy")
    func partialContainerRoleMigration() throws {
        let root = try temporaryPackage(
            manifest: packageManifest(swiftVersion: "6.2", appHasPlugin: true),
            source: """
            import InnoDI
            @DIContainerRole(role: ContainerRole.component)
            struct App {
                @Provide(.input) var value: Int
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().run(root: root, apply: true, verify: false)
        let migrated = try String(
            contentsOf: root.appendingPathComponent("Sources/App/App.swift"),
            encoding: .utf8
        )

        #expect(report.appliedChangePaths == ["Sources/App/App.swift"])
        #expect(report.secondPassChangeCount == 0)
        #expect(report.isHealthy)
        #expect(migrated.contains("@DIContainerRole"))
        #expect(migrated.contains("@Input var value"))
        #expect(!migrated.contains("@Provide(.input)"))
    }

    @Test("CLI validates arguments and supports text and JSON diagnosis")
    func cliContracts() throws {
        #expect(DoctorCLI.run(arguments: ["--help"]) == 0)
        #expect(DoctorCLI.run(arguments: []) == 64)
        #expect(DoctorCLI.run(arguments: ["--unknown"]) == 64)

        let root = try temporaryPackage(
            manifest: """
            // swift-tools-version: 6.2
            import PackageDescription
            let package = Package(
                name: "DoctorFixture",
                products: [.library(name: "App", targets: ["App"])],
                targets: [.target(name: "App")]
            )
            """,
            source: "public struct Value { public init() {} }"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(DoctorCLI.run(arguments: ["--root", root.path]) == 0)
        #expect(DoctorCLI.run(arguments: ["--root", root.path, "--json"]) == 0)
        #expect(
            DoctorCLI.run(arguments: [
                "--root", root.path, "--definitely-unknown",
            ]) == 64
        )
    }

    @Test("empty and malformed workspaces fail closed")
    func malformedWorkspaceDiagnostics() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-doctor-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("// malformed\n".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(report.diagnostics.map(\.id).contains("doctor.toolchain.unknown"))
        #expect(!report.isHealthy)
    }

    @Test("a missing manifest and source scope are both explicit")
    func missingWorkspaceInputs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-doctor-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().inspect(root: root)

        #expect(Set(report.diagnostics.map(\.id)).isSuperset(of: [
            "doctor.package-manifest.missing",
            "doctor.analysis.empty-scope",
        ]))
        #expect(report.graphVerification.status == .unchanged)
        #expect(!report.isHealthy)
    }

    private func temporaryPackage(manifest: String, source: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-doctor-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: root.appendingPathComponent("Package.swift"))
        try Data(source.utf8).write(to: sources.appendingPathComponent("App.swift"))
        return root
    }

    private func packageManifest(
        swiftVersion: String,
        appHasPlugin: Bool = false
    ) -> String {
        let plugins = appHasPlugin
            ? """
            ,
                        plugins: [
                            .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
                        ]
            """
            : ""
        return """
        // swift-tools-version: \(swiftVersion)
        import PackageDescription
        let package = Package(
            name: "DoctorFixture",
            targets: [
                .target(
                    name: "App"\(plugins)
                )
            ]
        )
        """
    }

    private func temporaryTuistProject(source: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "innodi-doctor-tuist-build-\(UUID().uuidString)",
            isDirectory: true
        )
        let sources = root.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Tuist", isDirectory: true),
            withIntermediateDirectories: true
        )
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
                    deploymentTargets: .macOS("13.0"),
                    infoPlist: .default,
                    sources: ["Sources/App/**"],
                    settings: .settings(base: ["SWIFT_VERSION": "6.2"])
                )
            ]
        )
        """
        try Data(project.utf8).write(to: root.appendingPathComponent("Project.swift"))
        try Data(source.utf8).write(to: sources.appendingPathComponent("App.swift"))
        return root
    }

    private struct FakeVerificationTools {
        let root: URL
        let doctor: InnoDIDoctor
    }

    private func fakeVerificationTools(
        xcodebuildExitCode: Int32
    ) throws -> FakeVerificationTools {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "innodi-doctor-tools-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let tuist = root.appendingPathComponent("tuist")
        let xcodebuild = root.appendingPathComponent("xcodebuild")
        try writeExecutable(
            """
            #!/bin/sh
            set -eu
            test "$1" = "generate"
            test "$2" = "--no-open"
            mkdir -p DoctorFixture.xcworkspace
            """,
            to: tuist
        )
        try writeExecutable(
            """
            #!/bin/sh
            echo "\(xcodebuildExitCode == 0 ? "fake xcodebuild success" : "error: fake xcodebuild failure")" >&2
            exit \(xcodebuildExitCode)
            """,
            to: xcodebuild
        )

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(root.path):/usr/bin:/bin"
        return FakeVerificationTools(
            root: root,
            doctor: InnoDIDoctor(verificationEnvironment: environment)
        )
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
