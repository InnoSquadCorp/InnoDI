import Foundation
import InnoDIDependencyGraphCore
import InnoDIMigrationCore
import InnoDIWorkspaceAnalysis
import SwiftParser
import SwiftSyntax
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct DoctorDiagnostic: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable { case info, warning, error }

    public let id: String
    public let severity: Severity
    public let path: String?
    public let message: String
    public let recommendation: String
}

public struct DoctorVerification: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case notRun, unverified, passed, failed
    }

    public struct Step: Codable, Equatable, Sendable {
        public let status: Status
        public let command: String?
        public let exitCode: Int32?
        public let timedOut: Bool
        public let outputTail: String?
    }

    public let status: Status
    public let command: String?
    public let exitCode: Int32?
    public let generation: Step
    public let compilation: Step
}

public struct DoctorGraphVerification: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case unchanged
        case changed
        case unavailable
    }

    public let status: Status
    public let addedProviderIDs: [String]
    public let removedProviderIDs: [String]
    public let changedProviderIDs: [String]
    public let note: String?
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let root: String
    public let mode: String
    public let diagnostics: [DoctorDiagnostic]
    public let scannedSwiftFileCount: Int
    public let proposedChangePaths: [String]
    public let appliedChangePaths: [String]
    public let secondPassChangeCount: Int
    public let graphVerification: DoctorGraphVerification
    public let verification: DoctorVerification

    public var isHealthy: Bool {
        diagnostics.isEmpty
            && secondPassChangeCount == 0
            && verification.status != .failed
            && verification.status != .unverified
    }
}

public struct InnoDIDoctor: Sendable {
    public init() {}

    /// Performs source/config inspection without package resolution, builds,
    /// downloads, writes, cache deletion, or process termination.
    public func inspect(root: URL) throws -> DoctorReport {
        try run(root: root, apply: false, verify: false)
    }

    /// Runs the explicit diagnose→review/apply→verify workflow. `apply` uses
    /// `InnoDIMigrator`'s stale-file, symlink, nested-repository, atomic-write,
    /// and rollback protections. `verify` is opt-in because it executes a build.
    public func run(
        root: URL,
        apply: Bool,
        verify: Bool,
        tuistScheme: String? = nil,
        destination: String? = nil
    ) throws -> DoctorReport {
        let canonicalRoot = root.standardizedFileURL
        var diagnostics: [DoctorDiagnostic] = []
        let workspace = doctorWorkspace(at: canonicalRoot)
        let manifestURL = workspace.manifestURL
        let manifest: String?
        if let manifestURL {
            do {
                manifest = try String(contentsOf: manifestURL, encoding: .utf8)
            } catch {
                manifest = nil
                diagnostics.append(.init(
                    id: "doctor.package-manifest.missing",
                    severity: .error,
                    path: workspace.manifestPath,
                    message: "\(workspace.manifestPath ?? "Package.swift") could not be read.",
                    recommendation: "Restore a readable UTF-8 package manifest before running the doctor."
                ))
            }
        } else {
            manifest = nil
            diagnostics.append(.init(
                id: "doctor.package-manifest.missing",
                severity: .error,
                path: "Package.swift",
                message: "Neither Package.swift nor Tuist/Package.swift could be read.",
                recommendation: "Run the doctor at a Swift package or Tuist workspace root."
            ))
        }

        if let manifest {
            if let version = declaredSwiftVersion(
                in: manifest,
                verificationKind: workspace.verificationKind
            ), version < (6, 2) {
                diagnostics.append(.init(
                    id: "doctor.toolchain.minimum",
                    severity: .error,
                    path: "\(workspace.manifestPath ?? "Package.swift"):1",
                    message: "The workspace declares Swift \(version.0).\(version.1), below InnoDI 6.0's Swift 6.2 floor.",
                    recommendation: "Upgrade the package toolchain deliberately before adopting InnoDI 6.0."
                ))
            } else if declaredSwiftVersion(
                in: manifest,
                verificationKind: workspace.verificationKind
            ) == nil {
                diagnostics.append(.init(
                    id: "doctor.toolchain.unknown",
                    severity: .error,
                    path: "\(workspace.manifestPath ?? "Package.swift"):1",
                    message: "The Swift tools or Tuist swiftVersion declaration is missing or malformed.",
                    recommendation: "Declare Swift 6.2 or newer in Package.swift or Tuist.swift."
                ))
            }
        }

        let plan = try InnoDIMigrator().plan(root: canonicalRoot)
        let graphBefore = try? graphFingerprint(root: canonicalRoot)
        diagnostics.append(contentsOf: plan.diagnostics.map {
            DoctorDiagnostic(
                id: $0.code,
                severity: .error,
                path: $0.path,
                message: $0.message,
                recommendation: "Resolve this safety boundary before applying migration changes."
            )
        })

        if plan.scannedFileCount == 0 {
            diagnostics.append(.init(
                id: "doctor.analysis.empty-scope",
                severity: .warning,
                path: nil,
                message: "No analyzable Swift sources were found.",
                recommendation: "Check the root and target source paths; unanalysed targets are not considered healthy."
            ))
        }

        diagnostics.append(contentsOf: try pluginDiagnostics(
            root: canonicalRoot,
            workspace: workspace
        ))

        let proposed = plan.changes.map(\.path).sorted()
        var applied: [String] = []
        if apply, plan.canWrite {
            _ = try InnoDIMigrator().run(root: canonicalRoot, mode: .write)
            applied = proposed
        }
        let secondPass = try InnoDIMigrator().plan(root: canonicalRoot)
        let graphAfter = try? graphFingerprint(root: canonicalRoot)
        let graphVerification = compareGraphs(before: graphBefore, after: graphAfter)
        if graphVerification.status == .unavailable {
            diagnostics.append(.init(
                id: "doctor.graph.incomplete",
                severity: .warning,
                path: nil,
                message: "The provider graph could not be analyzed completely.",
                recommendation: "Run the target-scoped dependency graph command and review its preflight diagnostics."
            ))
        }

        let verification: DoctorVerification
        if verify {
            let result = try runVerification(
                root: canonicalRoot,
                kind: workspace.verificationKind,
                tuistScheme: tuistScheme,
                destination: destination
            )
            verification = result
        } else {
            let notRun = DoctorVerification.Step(
                status: .notRun,
                command: nil,
                exitCode: nil,
                timedOut: false,
                outputTail: nil
            )
            verification = .init(
                status: .notRun,
                command: nil,
                exitCode: nil,
                generation: notRun,
                compilation: notRun
            )
        }

        return DoctorReport(
            schemaVersion: SelfReportSchema.version,
            root: canonicalRoot.path,
            mode: apply ? (verify ? "apply-and-verify" : "apply") : (verify ? "diagnose-and-verify" : "diagnose"),
            diagnostics: diagnostics.sorted { ($0.id, $0.path ?? "") < ($1.id, $1.path ?? "") },
            scannedSwiftFileCount: plan.scannedFileCount,
            proposedChangePaths: proposed,
            appliedChangePaths: applied,
            secondPassChangeCount: secondPass.changes.count,
            graphVerification: graphVerification,
            verification: verification
        )
    }
}

private enum DoctorVerificationKind {
    case swiftPackage
    case tuist
}

private struct DoctorWorkspace {
    let manifestURL: URL?
    let manifestPath: String?
    let verificationKind: DoctorVerificationKind
}

private func doctorWorkspace(at root: URL) -> DoctorWorkspace {
    let fileManager = FileManager.default
    let packageURL = root.appendingPathComponent("Package.swift")
    let tuistPackageURL = root.appendingPathComponent("Tuist/Package.swift")
    let tuistConfigurationURL = root.appendingPathComponent("Tuist.swift")
    let workspaceURL = root.appendingPathComponent("Workspace.swift")
    let projectURL = root.appendingPathComponent("Project.swift")
    let hasTuistWorkspace = fileManager.fileExists(
        atPath: workspaceURL.path
    ) || fileManager.fileExists(
        atPath: projectURL.path
    )

    if fileManager.isReadableFile(atPath: packageURL.path) {
        return DoctorWorkspace(
            manifestURL: packageURL,
            manifestPath: "Package.swift",
            verificationKind: hasTuistWorkspace ? .tuist : .swiftPackage
        )
    }
    if fileManager.isReadableFile(atPath: tuistPackageURL.path) {
        return DoctorWorkspace(
            manifestURL: tuistPackageURL,
            manifestPath: "Tuist/Package.swift",
            verificationKind: .tuist
        )
    }
    if hasTuistWorkspace {
        let configurationURL: URL
        let configurationPath: String
        if fileManager.isReadableFile(atPath: tuistConfigurationURL.path) {
            configurationURL = tuistConfigurationURL
            configurationPath = "Tuist.swift"
        } else if fileManager.isReadableFile(atPath: workspaceURL.path) {
            configurationURL = workspaceURL
            configurationPath = "Workspace.swift"
        } else {
            configurationURL = projectURL
            configurationPath = "Project.swift"
        }
        return DoctorWorkspace(
            manifestURL: configurationURL,
            manifestPath: configurationPath,
            verificationKind: .tuist
        )
    }
    return DoctorWorkspace(
        manifestURL: nil,
        manifestPath: nil,
        verificationKind: hasTuistWorkspace ? .tuist : .swiftPackage
    )
}

private struct DoctorGraphFingerprint {
    let providers: [String: String]
}

private func graphFingerprint(root: URL) throws -> DoctorGraphFingerprint {
    let snapshot = try loadWorkspaceSourceSnapshot(rootPath: root.path)
    let graph = collectDependencyGraph(snapshot: snapshot, validateDAG: false)
    guard graph.preflightFailure == nil else {
        throw CocoaError(.coderInvalidValue)
    }
    return DoctorGraphFingerprint(
        providers: Dictionary(uniqueKeysWithValues: graph.providers.map { provider in
            let semantic = [
                provider.containerID,
                provider.name,
                provider.type,
                provider.role.rawValue,
                provider.lifetime.rawValue,
                provider.initialization.rawValue,
                provider.isolation.rawValue,
                provider.effect.rawValue,
                provider.inputKind?.rawValue ?? "none",
                provider.dependencies.joined(separator: ","),
            ].joined(separator: "|")
            return (provider.id, semantic)
        })
    )
}

private func compareGraphs(
    before: DoctorGraphFingerprint?,
    after: DoctorGraphFingerprint?
) -> DoctorGraphVerification {
    guard let before, let after else {
        return DoctorGraphVerification(
            status: .unavailable,
            addedProviderIDs: [],
            removedProviderIDs: [],
            changedProviderIDs: [],
            note: "Source graph analysis was incomplete; no unchanged claim was made."
        )
    }
    let beforeIDs = Set(before.providers.keys)
    let afterIDs = Set(after.providers.keys)
    let added = afterIDs.subtracting(beforeIDs).sorted()
    let removed = beforeIDs.subtracting(afterIDs).sorted()
    let changed = beforeIDs.intersection(afterIDs).filter {
        before.providers[$0] != after.providers[$0]
    }.sorted()
    return DoctorGraphVerification(
        status: added.isEmpty && removed.isEmpty && changed.isEmpty ? .unchanged : .changed,
        addedProviderIDs: added,
        removedProviderIDs: removed,
        changedProviderIDs: changed,
        note: nil
    )
}

private enum SelfReportSchema { static let version = DoctorReport.currentSchemaVersion }

private func toolsVersion(in manifest: String) -> (Int, Int)? {
    guard let first = manifest.split(separator: "\n", maxSplits: 1).first,
          let marker = first.range(of: "swift-tools-version:") else { return nil }
    let pieces = first[marker.upperBound...].trimmingCharacters(in: .whitespaces)
        .split(separator: ".")
    guard pieces.count >= 2, let major = Int(pieces[0]), let minor = Int(pieces[1]) else {
        return nil
    }
    return (major, minor)
}

private func declaredSwiftVersion(
    in configuration: String,
    verificationKind: DoctorVerificationKind
) -> (Int, Int)? {
    if let version = toolsVersion(in: configuration) {
        return version
    }
    guard case .tuist = verificationKind else { return nil }

    for line in configuration.split(separator: "\n") {
        let text = String(line)
        guard text.contains("swiftVersion") || text.contains("SWIFT_VERSION") else {
            continue
        }
        let quoted = text.split(separator: "\"")
        for candidate in quoted where candidate.contains(".") {
            let pieces = candidate.split(separator: ".")
            if pieces.count >= 2,
               let major = Int(pieces[0]),
               let minor = Int(pieces[1]) {
                return (major, minor)
            }
        }
    }
    return nil
}

private func swiftSourceURLs(root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }
    var urls: [URL] = []
    for case let url as URL in enumerator {
        if [".build", "Derived", "InnoDI.xcodeproj"].contains(url.lastPathComponent) {
            enumerator.skipDescendants()
            continue
        }
        guard url.pathExtension == "swift",
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              !["Package.swift", "Package@swift-6.swift"].contains(url.lastPathComponent)
        else { continue }
        urls.append(url)
    }
    return urls.sorted { $0.path < $1.path }
}

private struct DoctorPackageTarget {
    let name: String
    let sourceRoot: String
    let pluginStatus: DoctorPluginStatus
}

private enum DoctorPluginStatus { case attached, missing, unknown }

private final class DoctorPackageManifestCollector: SyntaxVisitor {
    private(set) var targets: [DoctorPackageTarget] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.base == nil,
              ["target", "executableTarget", "testTarget"].contains(
                member.declName.baseName.text
              ),
              let name = stringArgument("name", in: node.arguments) else {
            return .visitChildren
        }
        let kind = member.declName.baseName.text
        let defaultRoot = kind == "testTarget" ? "Tests/\(name)" : "Sources/\(name)"
        let sourceRoot = stringArgument("path", in: node.arguments) ?? defaultRoot
        let plugins = node.arguments.first { $0.label?.text == "plugins" }?.expression
        targets.append(DoctorPackageTarget(
            name: name,
            sourceRoot: standardizedRelativePath(sourceRoot),
            pluginStatus: pluginStatus(plugins)
        ))
        return .skipChildren
    }

    private func pluginStatus(_ expression: ExprSyntax?) -> DoctorPluginStatus {
        guard let expression else { return .missing }
        guard let array = expression.as(ArrayExprSyntax.self) else { return .unknown }
        for element in array.elements {
            guard let call = element.expression.as(FunctionCallExprSyntax.self),
                  let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  member.declName.baseName.text == "plugin" else { continue }
            if stringArgument("name", in: call.arguments) == "InnoDIDAGValidationPlugin" {
                return .attached
            }
        }
        return .missing
    }

    private func stringArgument(
        _ label: String,
        in arguments: LabeledExprListSyntax
    ) -> String? {
        guard let expression = arguments.first(where: { $0.label?.text == label })?.expression,
              let literal = expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              case .stringSegment(let segment) = literal.segments.first else {
            return nil
        }
        return segment.content.text
    }
}

private final class DoctorContainerCollector: SyntaxVisitor {
    private(set) var containsContainer = false

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.attributeName.trimmedDescription
        if name == "DIContainer" || name.hasSuffix(".DIContainer")
            || name == "DIContainerRole" || name.hasSuffix(".DIContainerRole") {
            containsContainer = true
        }
        return .skipChildren
    }
}

private func standardizedRelativePath(_ path: String) -> String {
    NSString(string: path).standardizingPath.trimmingCharacters(
        in: CharacterSet(charactersIn: "/")
    )
}

private func pluginDiagnostics(
    root: URL,
    workspace: DoctorWorkspace
) throws -> [DoctorDiagnostic] {
    let containerPaths = try swiftSourceURLs(root: root).compactMap { url -> String? in
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let collector = DoctorContainerCollector()
        collector.walk(Parser.parse(source: source))
        guard collector.containsContainer else { return nil }
        let canonicalRootPath = root.resolvingSymlinksInPath().path
        let canonicalFilePath = url.resolvingSymlinksInPath().path
        guard canonicalFilePath.hasPrefix(canonicalRootPath + "/") else {
            return nil
        }
        return standardizedRelativePath(
            String(canonicalFilePath.dropFirst(canonicalRootPath.count + 1))
        )
    }
    guard !containerPaths.isEmpty else { return [] }

    guard case .swiftPackage = workspace.verificationKind,
          let manifestURL = workspace.manifestURL,
          manifestURL.lastPathComponent == "Package.swift",
          let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
        return [.init(
            id: "doctor.plugin.analysis-incomplete",
            severity: .error,
            path: workspace.manifestPath,
            message: "Container-owning targets could not be mapped to literal plugin declarations.",
            recommendation: "Use a literal target/plugin declaration or verify every container-owning target manually."
        )]
    }

    let collector = DoctorPackageManifestCollector()
    collector.walk(Parser.parse(source: manifest))
    var diagnostics: [DoctorDiagnostic] = []
    for path in containerPaths {
        let matches = collector.targets.filter {
            path == $0.sourceRoot || path.hasPrefix($0.sourceRoot + "/")
        }.sorted { $0.sourceRoot.count > $1.sourceRoot.count }
        guard let target = matches.first,
              matches.dropFirst().first?.sourceRoot.count != target.sourceRoot.count else {
            diagnostics.append(.init(
                id: "doctor.plugin.analysis-incomplete",
                severity: .error,
                path: path,
                message: "The container source could not be mapped to exactly one literal package target.",
                recommendation: "Use literal target name/path declarations, then rerun Doctor."
            ))
            continue
        }
        switch target.pluginStatus {
        case .attached:
            break
        case .missing:
            diagnostics.append(.init(
                id: "doctor.plugin.missing",
                severity: .warning,
                path: workspace.manifestPath ?? "Package.swift",
                message: "Target '\(target.name)' owns container source '\(path)' but does not attach InnoDIDAGValidationPlugin.",
                recommendation: "Attach InnoDIDAGValidationPlugin to target '\(target.name)'."
            ))
        case .unknown:
            diagnostics.append(.init(
                id: "doctor.plugin.analysis-incomplete",
                severity: .error,
                path: workspace.manifestPath ?? "Package.swift",
                message: "Target '\(target.name)' uses a non-literal plugin declaration that Doctor cannot prove.",
                recommendation: "Use a literal plugins array or verify the target manually."
            ))
        }
    }
    return diagnostics
}

private func runVerification(
    root: URL,
    kind: DoctorVerificationKind,
    tuistScheme: String?,
    destination: String?
) throws -> DoctorVerification {
    let notRun = DoctorVerification.Step(
        status: .notRun,
        command: nil,
        exitCode: nil,
        timedOut: false,
        outputTail: nil
    )
    switch kind {
    case .swiftPackage:
        let compilation = try runVerificationStep(
            arguments: ["swift", "build"],
            command: "swift build",
            root: root
        )
        return DoctorVerification(
            status: compilation.status,
            command: compilation.command,
            exitCode: compilation.exitCode,
            generation: notRun,
            compilation: compilation
        )
    case .tuist:
        let generation = try runVerificationStep(
            arguments: ["tuist", "generate", "--no-open"],
            command: "tuist generate --no-open",
            root: root
        )
        guard generation.status == .passed else {
            return DoctorVerification(
                status: .failed,
                command: generation.command,
                exitCode: generation.exitCode,
                generation: generation,
                compilation: notRun
            )
        }
        guard let tuistScheme, !tuistScheme.isEmpty,
              let destination, !destination.isEmpty else {
            let compilation = DoctorVerification.Step(
                status: .unverified,
                command: nil,
                exitCode: nil,
                timedOut: false,
                outputTail: "Tuist compilation requires explicit --scheme and --destination values."
            )
            return DoctorVerification(
                status: .unverified,
                command: generation.command,
                exitCode: nil,
                generation: generation,
                compilation: compilation
            )
        }
        let workspaces = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "xcworkspace" }
        guard workspaces.count == 1, let workspace = workspaces.first else {
            let compilation = DoctorVerification.Step(
                status: .unverified,
                command: nil,
                exitCode: nil,
                timedOut: false,
                outputTail: "Expected exactly one generated .xcworkspace; found \(workspaces.count)."
            )
            return DoctorVerification(
                status: .unverified,
                command: generation.command,
                exitCode: nil,
                generation: generation,
                compilation: compilation
            )
        }
        let derivedData = FileManager.default.temporaryDirectory.appendingPathComponent(
            "innodi-doctor-derived-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: derivedData) }
        let command = "xcodebuild -workspace \(workspace.lastPathComponent) -scheme \(tuistScheme) -destination \(destination) build"
        let compilation = try runVerificationStep(
            arguments: [
                "xcodebuild", "-workspace", workspace.path,
                "-scheme", tuistScheme,
                "-destination", destination,
                "-derivedDataPath", derivedData.path,
                "build",
            ],
            command: command,
            root: root
        )
        return DoctorVerification(
            status: compilation.status,
            command: command,
            exitCode: compilation.exitCode,
            generation: generation,
            compilation: compilation
        )
    }
}

private func runVerificationStep(
    arguments: [String],
    command: String,
    root: URL,
    timeout: TimeInterval = 300
) throws -> DoctorVerification.Step {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = root
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "innodi-doctor-log-\(UUID().uuidString)"
    )
    _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
    let log = try FileHandle(forWritingTo: logURL)
    defer {
        try? log.close()
        try? FileManager.default.removeItem(at: logURL)
    }
    process.standardOutput = log
    process.standardError = log
    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    let timedOut = process.isRunning
    if timedOut {
        process.terminate()
        Thread.sleep(forTimeInterval: 0.2)
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
        }
    }
    process.waitUntilExit()
    try log.synchronize()
    let data = (try? Data(contentsOf: logURL)) ?? Data()
    let tail = data.suffix(16_384)
    return DoctorVerification.Step(
        status: !timedOut && process.terminationStatus == 0 ? .passed : .failed,
        command: command,
        exitCode: process.terminationStatus,
        timedOut: timedOut,
        outputTail: tail.isEmpty ? nil : String(decoding: tail, as: UTF8.self)
    )
}
