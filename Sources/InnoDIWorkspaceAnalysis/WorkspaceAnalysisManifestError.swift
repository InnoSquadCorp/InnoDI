import Foundation

package enum WorkspaceAnalysisManifestError: LocalizedError, Equatable {
    case decodingFailed(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedBuildSystem(String)
    case unsupportedAnalysisScope(String)
    case invalidPackageIdentity(String)
    case invalidPackageDisplayName(String)
    case invalidTargetName(String)
    case invalidModuleName(String)
    case nonAbsolutePath(String)
    case unavailablePackageDirectory(String)
    case invalidLogicalPath(String)
    case nonSwiftSource(String)
    case unavailableSource(String)
    case declaredSourceOutsidePackage(
        target: WorkspaceTargetID,
        filePath: String,
        packageDirectory: String
    )
    case declaredSourceLogicalPathMismatch(
        target: WorkspaceTargetID,
        expected: String,
        actual: String
    )
    case missingPrimaryTarget(WorkspaceTargetID)
    case invalidPrimaryTarget(WorkspaceTargetID)
    case primaryPackageMismatch(expected: String, actual: String)
    case primaryPackageDirectoryMismatch(expected: String, actual: String)
    case inconsistentPackageMetadata(String)
    case duplicateTargetID(WorkspaceTargetID)
    case unsupportedDependencyTargetKind(
        WorkspaceTargetID,
        WorkspaceAnalysisTargetKind
    )
    case nonCanonicalTargetID(
        actual: WorkspaceTargetID,
        expected: WorkspaceTargetID
    )
    case duplicateSourceIdentity(String)
    case duplicateSourcePath(WorkspaceTargetID, String)
    case duplicateSourceOwnership(
        filePath: String,
        firstTarget: WorkspaceTargetID,
        secondTarget: WorkspaceTargetID
    )
    case emptyDependency(WorkspaceTargetID, String)
    case invalidDependencyName(WorkspaceTargetID, String)
    case invalidDependencyPackageIdentity(WorkspaceTargetID, String)
    case invalidTargetDependencyCardinality(
        WorkspaceTargetID,
        String,
        Int
    )
    case duplicateDependencyTarget(WorkspaceTargetID, WorkspaceTargetID)
    case selfDependency(WorkspaceTargetID)
    case danglingDependency(WorkspaceTargetID, WorkspaceTargetID)
    case targetDependencyCycle([WorkspaceTargetID])
    case unreachableTarget(WorkspaceTargetID)

    package var errorDescription: String? {
        switch self {
        case .decodingFailed(let description):
            return "Workspace analysis manifest could not be decoded: \(description)"
        case .unsupportedSchemaVersion(let version):
            return "Workspace analysis manifest schema \(version) is unsupported; expected \(WorkspaceAnalysisManifest.currentSchemaVersion)."
        case .unsupportedBuildSystem(let buildSystem):
            return "Workspace analysis build system '\(buildSystem)' is unsupported."
        case .unsupportedAnalysisScope(let scope):
            return "Workspace analysis scope '\(scope)' is unsupported."
        case .invalidPackageIdentity(let identity):
            return "Workspace package identity '\(identity)' is not canonical."
        case .invalidPackageDisplayName(let name):
            return "Workspace package display name '\(name)' is not canonical."
        case .invalidTargetName(let name):
            return "Workspace target name '\(name)' is not canonical."
        case .invalidModuleName(let name):
            return "Workspace module name '\(name)' is not canonical."
        case .nonAbsolutePath(let path):
            return "Workspace analysis path must be absolute: '\(path)'."
        case .unavailablePackageDirectory(let path):
            return "Workspace package directory is missing, unreadable, or not a directory: '\(path)'."
        case .invalidLogicalPath(let path):
            return "Workspace logical source path is invalid: '\(path)'."
        case .nonSwiftSource(let path):
            return "Workspace analysis source is not a Swift file: '\(path)'."
        case .unavailableSource(let path):
            return "Workspace analysis source is missing, unreadable, or not a regular file: '\(path)'."
        case .declaredSourceOutsidePackage(
            let target,
            let filePath,
            let packageDirectory
        ):
            return "Workspace declared source '\(filePath)' for target '\(target.rawValue)' is outside package directory '\(packageDirectory)'."
        case .declaredSourceLogicalPathMismatch(
            let target,
            let expected,
            let actual
        ):
            return "Workspace declared source for target '\(target.rawValue)' has logical path '\(actual)', expected '\(expected)'."
        case .missingPrimaryTarget(let id):
            return "Workspace analysis manifest has no primary target '\(id.rawValue)'."
        case .invalidPrimaryTarget(let id):
            return "Workspace analysis manifest must contain exactly one primary role matching '\(id.rawValue)'."
        case .primaryPackageMismatch(let expected, let actual):
            return "Workspace primary target belongs to package '\(actual)', expected root package '\(expected)'."
        case .primaryPackageDirectoryMismatch(let expected, let actual):
            return "Workspace primary target uses package directory '\(actual)', expected root directory '\(expected)'."
        case .inconsistentPackageMetadata(let identity):
            return "Workspace package '\(identity)' has inconsistent display names or directories."
        case .duplicateTargetID(let id):
            return "Workspace analysis manifest repeats target ID '\(id.rawValue)'."
        case .unsupportedDependencyTargetKind(let id, let kind):
            return "Workspace dependency target '\(id.rawValue)' has unsupported kind '\(kind.rawValue)'; only generic library targets are source-visible."
        case .nonCanonicalTargetID(let actual, let expected):
            return "Workspace target ID '\(actual.rawValue)' is noncanonical; expected '\(expected.rawValue)'."
        case .duplicateSourceIdentity(let identity):
            return "Workspace analysis manifest repeats source identity '\(identity)'."
        case .duplicateSourcePath(let id, let filePath):
            return "Workspace target '\(id.rawValue)' repeats physical source '\(filePath)'."
        case .duplicateSourceOwnership(let filePath, let first, let second):
            return "Workspace source '\(filePath)' is owned by both '\(first.rawValue)' and '\(second.rawValue)'."
        case .emptyDependency(let source, let name):
            return "Workspace dependency '\(name)' on '\(source.rawValue)' resolves to no visible targets."
        case .invalidDependencyName(let source, let name):
            return "Workspace dependency name '\(name)' on '\(source.rawValue)' is not canonical."
        case .invalidDependencyPackageIdentity(let source, let identity):
            return "Workspace dependency package identity '\(identity)' on '\(source.rawValue)' is not canonical."
        case .invalidTargetDependencyCardinality(let source, let name, let count):
            return "Workspace target dependency '\(name)' on '\(source.rawValue)' resolves to \(count) targets; expected exactly one."
        case .duplicateDependencyTarget(let source, let target):
            return "Workspace target '\(source.rawValue)' repeats direct dependency '\(target.rawValue)'."
        case .selfDependency(let id):
            return "Workspace target '\(id.rawValue)' depends on itself."
        case .danglingDependency(let source, let target):
            return "Workspace target '\(source.rawValue)' depends on missing target '\(target.rawValue)'."
        case .targetDependencyCycle(let path):
            let description = path
                .map { "'\($0.rawValue)'" }
                .joined(separator: " -> ")
            return "Workspace target dependency cycle detected: \(description)."
        case .unreachableTarget(let id):
            return "Workspace target '\(id.rawValue)' is outside the primary target's visible dependency closure."
        }
    }
}
