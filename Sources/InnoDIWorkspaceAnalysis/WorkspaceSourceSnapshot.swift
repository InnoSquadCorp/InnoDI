import Dispatch
import Foundation
import SwiftParser
import SwiftSyntax

package let workspaceSourceSkipTokens = [
    "/.build/",
    "/Derived/",
    "/Tuist/Dependencies/",
    "/.tuist/",
    "/.git/",
    "/Pods/",
    "/Carthage/",
    "/.swiftpm/"
]

// Xcode bundle names include project-specific prefixes, such as Sample.xcodeproj.
private let workspaceSourceSkippedPathComponentSuffixes = [
    ".xcodeproj",
    ".xcworkspace"
]

package struct WorkspaceSourceFile {
    package let relativePath: String
    package let fileURL: URL
    package let syntax: SourceFileSyntax
    package let targetID: WorkspaceTargetID?
    package let origin: WorkspaceAnalysisSourceOrigin?

    package var filePath: String {
        fileURL.path(percentEncoded: false)
    }

    /// Stable target-qualified identity for manifest-backed analysis.
    ///
    /// Root-path callers retain their historical relative-path identity.
    package var sourceIdentity: String {
        guard let targetID else {
            return relativePath
        }
        return "\(targetID.rawValue)::\(relativePath)"
    }

    package init(
        relativePath: String,
        fileURL: URL,
        syntax: SourceFileSyntax,
        targetID: WorkspaceTargetID? = nil,
        origin: WorkspaceAnalysisSourceOrigin? = nil
    ) {
        self.relativePath = relativePath
        self.fileURL = fileURL
        self.syntax = syntax
        self.targetID = targetID
        self.origin = origin
    }
}

package struct WorkspaceSourceSnapshot {
    package let rootPath: String
    package let rootURL: URL
    package let files: [WorkspaceSourceFile]
    package let primaryTargetID: WorkspaceTargetID?
    /// Authoritative target topology for manifest-backed analysis.
    ///
    /// Root-path callers intentionally keep this `nil` so their historical
    /// workspace-wide resolution behavior remains unchanged.
    package let analysisManifest: WorkspaceAnalysisManifest?

    private let filesBySourceIdentity: [String: WorkspaceSourceFile]
    private let filesByRelativePath: [String: WorkspaceSourceFile]

    package init(
        rootPath: String,
        rootURL: URL,
        files: [WorkspaceSourceFile],
        primaryTargetID: WorkspaceTargetID? = nil,
        analysisManifest: WorkspaceAnalysisManifest? = nil
    ) {
        self.rootPath = rootPath
        self.rootURL = rootURL
        self.files = files
        self.primaryTargetID = primaryTargetID
        self.analysisManifest = analysisManifest
        self.filesBySourceIdentity = Dictionary(
            grouping: files,
            by: \.sourceIdentity
        ).compactMapValues { matches in
            matches.count == 1 ? matches[0] : nil
        }
        self.filesByRelativePath = Dictionary(grouping: files, by: \.relativePath)
            .compactMapValues { matches in
                matches.count == 1 ? matches[0] : nil
            }
    }

    /// Returns a source only when its logical path is unambiguous.
    ///
    /// Manifest-backed snapshots can contain the same package-relative path
    /// in multiple targets, so callers that need exact lookup should use
    /// `sourceFile(sourceIdentity:)`.
    package func sourceFile(relativePath: String) -> WorkspaceSourceFile? {
        filesByRelativePath[relativePath]
    }

    package func sourceFile(
        sourceIdentity: String
    ) -> WorkspaceSourceFile? {
        filesBySourceIdentity[sourceIdentity]
    }
}

package enum WorkspaceSourceSnapshotError: LocalizedError {
    case missingRoot(rootPath: String, rootURL: URL)
    case rootIsNotDirectory(rootPath: String, rootURL: URL)
    case unreadableRoot(rootPath: String, rootURL: URL)
    case failedToCreateEnumerator(rootPath: String, rootURL: URL)
    case enumerationFailed(rootPath: String, rootURL: URL, underlying: Error)

    package var errorDescription: String? {
        switch self {
        case .missingRoot(let rootPath, let rootURL):
            return "Workspace root does not exist: '\(rootPath)' (\(rootURL.path(percentEncoded: false)))."
        case .rootIsNotDirectory(let rootPath, let rootURL):
            return "Workspace root is not a directory: '\(rootPath)' (\(rootURL.path(percentEncoded: false)))."
        case .unreadableRoot(let rootPath, let rootURL):
            return "Workspace root is not readable: '\(rootPath)' (\(rootURL.path(percentEncoded: false)))."
        case .failedToCreateEnumerator(let rootPath, let rootURL):
            return "Failed to enumerate workspace root: '\(rootPath)' (\(rootURL.path(percentEncoded: false)))."
        case .enumerationFailed(let rootPath, let rootURL, let underlying):
            return "Failed to enumerate workspace source path '\(rootURL.path(percentEncoded: false))' under root '\(rootPath)': \(underlying)."
        }
    }
}

package func loadWorkspaceSourceSnapshot(
    rootPath: String,
    onFileReadError: ((String, URL, Error) -> Void)? = nil
) throws -> WorkspaceSourceSnapshot {
    let rootURL = try validatedWorkspaceRootURL(rootPath: rootPath)
    let sourceFiles = try discoverWorkspaceSourceFiles(rootPath: rootPath)
    let outcomes = try loadWorkspaceSourcesInParallel(count: sourceFiles.count) { index in
        let relativePath = sourceFiles[index]
        let fileURL = rootURL.appendingPathComponent(relativePath)
        do {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            return .parsed(
                WorkspaceSourceFile(
                    relativePath: relativePath,
                    fileURL: fileURL,
                    syntax: Parser.parse(source: source)
                )
            )
        } catch {
            return .readFailed(error)
        }
    }

    var files: [WorkspaceSourceFile] = []
    files.reserveCapacity(sourceFiles.count)
    // Read-error callbacks replay serially in discovery order so callers
    // never observe them from a concurrent context.
    for (index, outcome) in outcomes.enumerated() {
        switch outcome {
        case .parsed(let file):
            files.append(file)
        case .readFailed(let error):
            guard let onFileReadError else {
                throw error
            }
            let relativePath = sourceFiles[index]
            onFileReadError(relativePath, rootURL.appendingPathComponent(relativePath), error)
        }
    }

    return WorkspaceSourceSnapshot(rootPath: rootPath, rootURL: rootURL, files: files)
}

/// Loads exactly the sources SwiftPM declared visible to one primary target.
///
/// Unlike root-path discovery, this mode never skips unreadable files and
/// never broadens the scope when the manifest is incomplete or malformed.
package func loadWorkspaceSourceSnapshot(
    manifest: WorkspaceAnalysisManifest
) throws -> WorkspaceSourceSnapshot {
    try loadWorkspaceSourceSnapshot(
        validated: ValidatedWorkspaceAnalysisManifest(validating: manifest)
    )
}

/// `ValidatedWorkspaceAnalysisManifest` overload used by callers that already
/// proved the manifest contract, so the per-source availability stats in
/// `validated()` are not repeated per pipeline stage.
package func loadWorkspaceSourceSnapshot(
    validated: ValidatedWorkspaceAnalysisManifest
) throws -> WorkspaceSourceSnapshot {
    let manifest = validated.manifest
    let rootURL = URL(fileURLWithPath: manifest.rootPackageDirectory)
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let jobs = manifest.targets.flatMap { target in
        target.sources.map { source in (targetID: target.id, source: source) }
    }
    let outcomes = try loadWorkspaceSourcesInParallel(count: jobs.count) { index in
        let job = jobs[index]
        let fileURL = URL(fileURLWithPath: job.source.filePath)
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            return .parsed(
                WorkspaceSourceFile(
                    relativePath: job.source.logicalPath,
                    fileURL: fileURL,
                    syntax: Parser.parse(source: contents),
                    targetID: job.targetID,
                    origin: job.source.origin
                )
            )
        } catch {
            return .readFailed(error)
        }
    }

    var files: [WorkspaceSourceFile] = []
    files.reserveCapacity(jobs.count)
    for outcome in outcomes {
        switch outcome {
        case .parsed(let file):
            files.append(file)
        case .readFailed(let error):
            throw error
        }
    }

    return WorkspaceSourceSnapshot(
        rootPath: manifest.rootPackageDirectory,
        rootURL: rootURL,
        files: files,
        primaryTargetID: manifest.primaryTargetID,
        analysisManifest: manifest
    )
}

private enum WorkspaceSourceLoadOutcome {
    case parsed(WorkspaceSourceFile)
    case readFailed(Error)
}

private struct WorkspaceParallelSourceLoadError: LocalizedError {
    var errorDescription: String? {
        "Parallel workspace source loading finished without an outcome for every file; " +
        "this is an InnoDI internal inconsistency — please file a bug."
    }
}

/// Runs `load` for every index concurrently and returns outcomes in input
/// order.
///
/// Reading and parsing workspace sources is per-file independent and
/// CPU-bound, so cold snapshot loads scale with core count instead of running
/// serially. Determinism is preserved because callers consume outcomes by
/// input index: the surfaced error is always the first failing input, exactly
/// as the previous serial loop reported it.
private func loadWorkspaceSourcesInParallel(
    count: Int,
    load: @Sendable (Int) -> WorkspaceSourceLoadOutcome
) throws -> [WorkspaceSourceLoadOutcome] {
    guard count > 0 else {
        return []
    }

    var slots = [WorkspaceSourceLoadOutcome?](repeating: nil, count: count)
    slots.withUnsafeMutableBufferPointer { buffer in
        // Safety: every iteration writes exactly one distinct element, so no
        // two threads ever touch the same memory location, and
        // `concurrentPerform` joins all iterations before the buffer scope
        // ends.
        nonisolated(unsafe) let base = buffer.baseAddress
        DispatchQueue.concurrentPerform(iterations: count) { index in
            base?.advanced(by: index).pointee = load(index)
        }
    }

    let outcomes = slots.compactMap { $0 }
    guard outcomes.count == count else {
        // Every iteration writes exactly one slot, so this cannot happen; the
        // guard keeps the loaders fail-closed rather than silently narrowing
        // scope if that invariant is ever broken.
        throw WorkspaceParallelSourceLoadError()
    }
    return outcomes
}

/// Discovers Swift source files that participate in workspace-wide validation.
///
/// The returned paths are relative to `rootPath` and sorted so callers can
/// build deterministic signatures or diagnostics independent of filesystem
/// enumeration order.
package func discoverWorkspaceSourceFiles(rootPath: String) throws -> [String] {
    let fileManager = FileManager.default
    let rootURL = try validatedWorkspaceRootURL(rootPath: rootPath)
    let rootPrefix = rootURL.path(percentEncoded: false).hasSuffix("/")
        ? rootURL.path(percentEncoded: false)
        : rootURL.path(percentEncoded: false) + "/"
    var enumerationError: WorkspaceSourceSnapshotError?

    guard let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: nil,
        options: [],
        errorHandler: { url, error in
            enumerationError = .enumerationFailed(rootPath: rootPath, rootURL: url, underlying: error)
            return false
        }
    ) else {
        throw WorkspaceSourceSnapshotError.failedToCreateEnumerator(rootPath: rootPath, rootURL: rootURL)
    }

    var sourceFiles: [String] = []

    while let itemURL = enumerator.nextObject() as? URL {
        if let enumerationError {
            throw enumerationError
        }

        let itemPath = itemURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
        guard itemPath.hasPrefix(rootPrefix) else {
            continue
        }
        let relativePath = String(itemPath.dropFirst(rootPrefix.count))

        if workspacePathShouldPruneDescendants(relativePath) {
            enumerator.skipDescendants()
            continue
        }
        guard relativePath.hasSuffix(".swift") else { continue }
        sourceFiles.append(relativePath)
    }

    if let enumerationError {
        throw enumerationError
    }

    return sourceFiles.sorted()
}

package func workspacePathShouldPruneDescendants(_ path: String) -> Bool {
    workspacePathHasHiddenRootComponent(path) || workspacePathMatchesSkipToken(path)
}

package func workspaceRelativePath(of path: String, fromRoot rootPath: String) -> String {
    let rootURL = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().standardizedFileURL
    let pathURL = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL

    let root = rootURL.path(percentEncoded: false)
    let fullPath = pathURL.path(percentEncoded: false)

    if fullPath == root {
        return (fullPath as NSString).lastPathComponent
    }

    let rootPrefix = root.hasSuffix("/") ? root : root + "/"
    if fullPath.hasPrefix(rootPrefix) {
        return String(fullPath.dropFirst(rootPrefix.count))
    }

    let hash = stableWorkspacePathHash(fullPath)
    let parentName = pathURL.deletingLastPathComponent().lastPathComponent
    let fileName = pathURL.lastPathComponent
    if parentName.isEmpty {
        return "__external__/\(hash)/\(fileName)"
    }
    return "__external__/\(hash)/\(parentName)/\(fileName)"
}

package func parseWorkspaceSourceFile(at path: String) throws -> SourceFileSyntax {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    return Parser.parse(source: source)
}

private func validatedWorkspaceRootURL(rootPath: String) throws -> URL {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let rootFilePath = rootURL.path(percentEncoded: false)
    var isDirectory = ObjCBool(false)

    guard fileManager.fileExists(atPath: rootFilePath, isDirectory: &isDirectory) else {
        throw WorkspaceSourceSnapshotError.missingRoot(rootPath: rootPath, rootURL: rootURL)
    }
    guard isDirectory.boolValue else {
        throw WorkspaceSourceSnapshotError.rootIsNotDirectory(rootPath: rootPath, rootURL: rootURL)
    }
    guard fileManager.isReadableFile(atPath: rootFilePath) else {
        throw WorkspaceSourceSnapshotError.unreadableRoot(rootPath: rootPath, rootURL: rootURL)
    }

    return rootURL.resolvingSymlinksInPath().standardizedFileURL
}

private func workspacePathHasHiddenRootComponent(_ path: String) -> Bool {
    guard let firstComponent = path.split(separator: "/").first else {
        return false
    }
    return firstComponent.hasPrefix(".")
}

private func workspacePathMatchesSkipToken(_ path: String) -> Bool {
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let normalizedPath = "/\(trimmedPath)/"
    for token in workspaceSourceSkipTokens where normalizedPath.contains(token) {
        return true
    }
    let pathComponents = trimmedPath.split(separator: "/")
    for component in pathComponents {
        if workspaceSourceSkippedPathComponentSuffixes.contains(where: { component.hasSuffix($0) }) {
            return true
        }
    }
    return false
}

/// External-path identities are display/cache labels, not persisted contract
/// artifacts, so routing them through the shared `StableHasher` (a one-time
/// respelling of `__external__/<hash>/` prefixes) is safe.
private func stableWorkspacePathHash(_ path: String) -> String {
    var hasher = StableHasher()
    hasher.combine(path)
    return hasher.finalize()
}
