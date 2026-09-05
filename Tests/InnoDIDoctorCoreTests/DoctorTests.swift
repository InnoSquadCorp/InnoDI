import Foundation
import Testing

@testable import InnoDIDoctorCore

@Suite("InnoDI doctor")
struct DoctorTests {
    @Test("read-only diagnosis reports toolchain, plugin, scope, and migration without writes")
    func readOnlyDiagnosis() throws {
        let root = try temporaryPackage(
            manifest: "// swift-tools-version: 6.1\nimport PackageDescription\n",
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
            manifest: "// swift-tools-version: 6.2\n// InnoDIDAGValidationPlugin\nimport PackageDescription\n",
            source: "import InnoDI\n@DIContainer struct App { @Provide(.input) var value: Int }"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try InnoDIDoctor().run(root: root, apply: true, verify: false)

        #expect(report.appliedChangePaths == ["Sources/App/App.swift"])
        #expect(report.secondPassChangeCount == 0)
        #expect(report.verification.status == .notRun)
        #expect(report.graphVerification.status == .unchanged)
        #expect(try String(contentsOf: root.appendingPathComponent("Sources/App/App.swift"), encoding: .utf8).contains("@Input"))
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
        #expect(report.isHealthy)
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
        #expect(!report.diagnostics.map(\.id).contains("doctor.plugin.missing"))
        #expect(report.scannedSwiftFileCount == 4)
        #expect(report.isHealthy)
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
        #expect(!report.diagnostics.map(\.id).contains("doctor.plugin.missing"))
        #expect(report.isHealthy)
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
}
