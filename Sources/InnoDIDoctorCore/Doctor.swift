import Foundation
import InnoDIDependencyGraphCore
import InnoDIMigrationCore
import InnoDIWorkspaceAnalysis

public struct DoctorDiagnostic: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable { case info, warning, error }

    public let id: String
    public let severity: Severity
    public let path: String?
    public let message: String
    public let recommendation: String
}

public struct DoctorVerification: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case notRun, passed, failed }

    public let status: Status
    public let command: String?
    public let exitCode: Int32?
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
    public static let currentSchemaVersion = 1

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
            && proposedChangePaths.isEmpty
            && verification.status != .failed
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
    public func run(root: URL, apply: Bool, verify: Bool) throws -> DoctorReport {
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
            if let version = toolsVersion(in: manifest), version < (6, 2) {
                diagnostics.append(.init(
                    id: "doctor.toolchain.minimum",
                    severity: .error,
                    path: "\(workspace.manifestPath ?? "Package.swift"):1",
                    message: "The package declares Swift tools \(version.0).\(version.1), below InnoDI 6.0's Swift 6.2 floor.",
                    recommendation: "Upgrade the package toolchain deliberately before adopting InnoDI 6.0."
                ))
            } else if toolsVersion(in: manifest) == nil {
                diagnostics.append(.init(
                    id: "doctor.toolchain.unknown",
                    severity: .error,
                    path: "\(workspace.manifestPath ?? "Package.swift"):1",
                    message: "The swift-tools-version declaration is missing or malformed.",
                    recommendation: "Declare // swift-tools-version: 6.2 or newer."
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

        let usesContainers = try sourceTreeContains("@DIContainer", root: canonicalRoot)
        let declaresPlugin = try sourceTreeContains(
            "InnoDIDAGValidationPlugin",
            root: canonicalRoot
        )
        if usesContainers, !declaresPlugin {
            diagnostics.append(.init(
                id: "doctor.plugin.missing",
                severity: .warning,
                path: workspace.manifestPath ?? "Package.swift",
                message: "@DIContainer sources were found but the DAG validation plugin is not declared.",
                recommendation: "Attach InnoDIDAGValidationPlugin to each container-owning target."
            ))
        }

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
                kind: workspace.verificationKind
            )
            verification = .init(
                status: result.exitCode == 0 ? .passed : .failed,
                command: result.command,
                exitCode: result.exitCode
            )
        } else {
            verification = .init(status: .notRun, command: nil, exitCode: nil)
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
    let hasTuistWorkspace = fileManager.fileExists(
        atPath: root.appendingPathComponent("Workspace.swift").path
    ) || fileManager.fileExists(
        atPath: root.appendingPathComponent("Project.swift").path
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

private func sourceTreeContains(_ needle: String, root: URL) throws -> Bool {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return false }
    for case let url as URL in enumerator {
        if [".build", "Derived", "InnoDI.xcodeproj"].contains(url.lastPathComponent) {
            enumerator.skipDescendants()
            continue
        }
        guard url.pathExtension == "swift",
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
        if source.contains(needle) { return true }
    }
    return false
}

private struct DoctorVerificationResult {
    let command: String
    let exitCode: Int32
}

private func runVerification(
    root: URL,
    kind: DoctorVerificationKind
) throws -> DoctorVerificationResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let arguments: [String]
    let command: String
    switch kind {
    case .swiftPackage:
        arguments = ["swift", "build"]
        command = "swift build"
    case .tuist:
        arguments = ["tuist", "generate", "--no-open"]
        command = "tuist generate --no-open"
    }
    process.arguments = arguments
    process.currentDirectoryURL = root
    process.standardOutput = FileHandle.standardError
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    return DoctorVerificationResult(
        command: command,
        exitCode: process.terminationStatus
    )
}
