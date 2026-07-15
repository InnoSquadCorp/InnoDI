import Foundation

/// Stable module identity shared by build validation and graph rendering.
///
/// SwiftPM's `Target.id` is scoped to one plugin invocation, so it must never
/// escape into a cache or public graph artifact. InnoDI instead derives the
/// identity from SwiftPM's resolved package identity and Swift module name.
package struct WorkspaceTargetID:
    RawRepresentable,
    Codable,
    Hashable,
    Comparable,
    Sendable
{
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    package static func swiftPM(
        packageIdentity: String,
        moduleName: String
    ) -> Self {
        Self(rawValue: "swiftpm:\(packageIdentity):\(moduleName)")
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

package enum WorkspaceAnalysisTargetKind: String, Codable, Sendable {
    case generic
    case executable
    case snippet
    case macro
    case test
}

package enum WorkspaceAnalysisTargetRole: String, Codable, Sendable {
    case primary
    case dependency
}

package enum WorkspaceAnalysisSourceOrigin: String, Codable, Sendable {
    case declared
    case generated
}

package enum WorkspaceAnalysisDependencyKind: String, Codable, Sendable {
    case target
    case product
}

package struct WorkspaceAnalysisSource: Codable, Equatable, Sendable {
    package let filePath: String
    package let logicalPath: String
    package let origin: WorkspaceAnalysisSourceOrigin

    package init(
        filePath: String,
        logicalPath: String,
        origin: WorkspaceAnalysisSourceOrigin
    ) {
        self.filePath = filePath
        self.logicalPath = logicalPath
        self.origin = origin
    }

    package func identity(in targetID: WorkspaceTargetID) -> String {
        "\(targetID.rawValue)::\(logicalPath)"
    }
}

package struct WorkspaceAnalysisDependency: Codable, Equatable, Sendable {
    package let kind: WorkspaceAnalysisDependencyKind
    package let name: String
    package let packageIdentity: String?
    package let targetIDs: [WorkspaceTargetID]

    package init(
        kind: WorkspaceAnalysisDependencyKind,
        name: String,
        packageIdentity: String? = nil,
        targetIDs: [WorkspaceTargetID]
    ) {
        self.kind = kind
        self.name = name
        self.packageIdentity = packageIdentity
        self.targetIDs = targetIDs
    }

    fileprivate func normalized() -> Self {
        Self(
            kind: kind,
            name: name,
            packageIdentity: packageIdentity,
            targetIDs: targetIDs.sorted()
        )
    }
}

package struct WorkspaceAnalysisTarget: Codable, Equatable, Sendable {
    package let id: WorkspaceTargetID
    package let packageIdentity: String
    package let packageDisplayName: String
    package let packageDirectory: String
    package let targetName: String
    package let moduleName: String
    package let kind: WorkspaceAnalysisTargetKind
    package let role: WorkspaceAnalysisTargetRole
    package let sources: [WorkspaceAnalysisSource]
    package let dependencies: [WorkspaceAnalysisDependency]

    package init(
        id: WorkspaceTargetID,
        packageIdentity: String,
        packageDisplayName: String,
        packageDirectory: String,
        targetName: String,
        moduleName: String,
        kind: WorkspaceAnalysisTargetKind,
        role: WorkspaceAnalysisTargetRole,
        sources: [WorkspaceAnalysisSource],
        dependencies: [WorkspaceAnalysisDependency]
    ) {
        self.id = id
        self.packageIdentity = packageIdentity
        self.packageDisplayName = packageDisplayName
        self.packageDirectory = packageDirectory
        self.targetName = targetName
        self.moduleName = moduleName
        self.kind = kind
        self.role = role
        self.sources = sources
        self.dependencies = dependencies
    }

    package var directDependencyTargetIDs: [WorkspaceTargetID] {
        Array(Set(dependencies.flatMap(\.targetIDs))).sorted()
    }

    fileprivate func normalized() -> Self {
        Self(
            id: id,
            packageIdentity: packageIdentity,
            packageDisplayName: packageDisplayName,
            packageDirectory: packageDirectory,
            targetName: targetName,
            moduleName: moduleName,
            kind: kind,
            role: role,
            sources: sources.sorted {
                if $0.logicalPath != $1.logicalPath {
                    return $0.logicalPath < $1.logicalPath
                }
                if $0.origin != $1.origin {
                    return $0.origin.rawValue < $1.origin.rawValue
                }
                return $0.filePath < $1.filePath
            },
            dependencies: dependencies
                .map { $0.normalized() }
                .sorted {
                    if $0.kind != $1.kind {
                        return $0.kind.rawValue < $1.kind.rawValue
                    }
                    if $0.name != $1.name {
                        return $0.name < $1.name
                    }
                    if $0.packageIdentity != $1.packageIdentity {
                        return ($0.packageIdentity ?? "") < ($1.packageIdentity ?? "")
                    }
                    return $0.targetIDs.lexicographicallyPrecedes($1.targetIDs)
                }
        )
    }
}

package struct WorkspaceAnalysisManifest: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 1
    package static let swiftPMBuildSystem = "swiftpm"
    package static let targetVisibleDependencyScope =
        "primaryTargetWithVisibleDependencies"

    package let schemaVersion: Int
    package let buildSystem: String
    package let analysisScope: String
    package let rootPackageIdentity: String
    package let rootPackageDirectory: String
    package let primaryTargetID: WorkspaceTargetID
    package let targets: [WorkspaceAnalysisTarget]

    package init(
        schemaVersion: Int = currentSchemaVersion,
        buildSystem: String = swiftPMBuildSystem,
        analysisScope: String = targetVisibleDependencyScope,
        rootPackageIdentity: String,
        rootPackageDirectory: String,
        primaryTargetID: WorkspaceTargetID,
        targets: [WorkspaceAnalysisTarget]
    ) {
        self.schemaVersion = schemaVersion
        self.buildSystem = buildSystem
        self.analysisScope = analysisScope
        self.rootPackageIdentity = rootPackageIdentity
        self.rootPackageDirectory = rootPackageDirectory
        self.primaryTargetID = primaryTargetID
        self.targets = targets
    }

    package var primaryTarget: WorkspaceAnalysisTarget? {
        targets.first { $0.id == primaryTargetID }
    }

    package func target(
        id: WorkspaceTargetID
    ) -> WorkspaceAnalysisTarget? {
        targets.first { $0.id == id }
    }

    package var sourceIdentities: [String] {
        targets.flatMap { target in
            target.sources.map { $0.identity(in: target.id) }
        }
        .sorted()
    }

    /// Validates the authoritative plugin contract and returns canonical order.
    ///
    /// `validateSourceAvailability` is disabled only by model-level tests. The
    /// build-plugin path keeps it enabled so a missing file cannot yield a
    /// partial green validation run.
    package func validated(
        validateSourceAvailability: Bool = true,
        fileManager: FileManager = .default
    ) throws -> Self {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw WorkspaceAnalysisManifestError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        guard buildSystem == Self.swiftPMBuildSystem else {
            throw WorkspaceAnalysisManifestError.unsupportedBuildSystem(
                buildSystem
            )
        }
        guard analysisScope == Self.targetVisibleDependencyScope else {
            throw WorkspaceAnalysisManifestError.unsupportedAnalysisScope(
                analysisScope
            )
        }
        guard isCanonicalManifestAtom(rootPackageIdentity) else {
            throw WorkspaceAnalysisManifestError.invalidPackageIdentity(
                rootPackageIdentity
            )
        }
        guard isAbsoluteManifestPath(rootPackageDirectory) else {
            throw WorkspaceAnalysisManifestError.nonAbsolutePath(
                rootPackageDirectory
            )
        }
        if validateSourceAvailability {
            try validateAvailablePackageDirectory(
                rootPackageDirectory,
                fileManager: fileManager
            )
        }
        guard !targets.isEmpty else {
            throw WorkspaceAnalysisManifestError.missingPrimaryTarget(
                primaryTargetID
            )
        }

        let groupedTargets = Dictionary(grouping: targets, by: \.id)
        if let duplicate = groupedTargets
            .filter({ $0.value.count > 1 })
            .map(\.key)
            .sorted()
            .first {
            throw WorkspaceAnalysisManifestError.duplicateTargetID(duplicate)
        }

        let canonicalTargets = targets
            .map { $0.normalized() }
            .sorted { $0.id < $1.id }
        let primaryRoleTargets = canonicalTargets.filter {
            $0.role == .primary
        }
        guard primaryRoleTargets.count == 1,
              primaryRoleTargets[0].id == primaryTargetID,
              let primaryTarget = canonicalTargets.first(where: {
                  $0.id == primaryTargetID
              }) else {
            throw WorkspaceAnalysisManifestError.invalidPrimaryTarget(
                primaryTargetID
            )
        }
        guard primaryTarget.packageIdentity == rootPackageIdentity else {
            throw WorkspaceAnalysisManifestError.primaryPackageMismatch(
                expected: rootPackageIdentity,
                actual: primaryTarget.packageIdentity
            )
        }
        guard canonicalManifestPath(primaryTarget.packageDirectory)
                == canonicalManifestPath(rootPackageDirectory) else {
            throw WorkspaceAnalysisManifestError
                .primaryPackageDirectoryMismatch(
                    expected: rootPackageDirectory,
                    actual: primaryTarget.packageDirectory
                )
        }

        let knownTargetIDs = Set(canonicalTargets.map(\.id))
        var ownedFilePaths: [String: WorkspaceTargetID] = [:]
        var packageMetadata: [String: WorkspacePackageMetadata] = [:]
        for target in canonicalTargets {
            let metadata = WorkspacePackageMetadata(
                displayName: target.packageDisplayName,
                canonicalDirectory: canonicalManifestPath(
                    target.packageDirectory
                )
            )
            if let existing = packageMetadata[target.packageIdentity],
               existing != metadata {
                throw WorkspaceAnalysisManifestError
                    .inconsistentPackageMetadata(target.packageIdentity)
            }
            packageMetadata[target.packageIdentity] = metadata

            try validateTarget(
                target,
                knownTargetIDs: knownTargetIDs,
                validateSourceAvailability: validateSourceAvailability,
                fileManager: fileManager,
                ownedFilePaths: &ownedFilePaths
            )
        }

        if let cycle = targetDependencyCycle(
            from: primaryTargetID,
            targets: canonicalTargets
        ) {
            throw WorkspaceAnalysisManifestError.targetDependencyCycle(cycle)
        }

        let reachableTargetIDs = reachableTargets(
            from: primaryTargetID,
            targets: canonicalTargets
        )
        if let unrelated = knownTargetIDs
            .subtracting(reachableTargetIDs)
            .sorted()
            .first {
            throw WorkspaceAnalysisManifestError.unreachableTarget(unrelated)
        }

        return Self(
            schemaVersion: schemaVersion,
            buildSystem: buildSystem,
            analysisScope: analysisScope,
            rootPackageIdentity: rootPackageIdentity,
            rootPackageDirectory: rootPackageDirectory,
            primaryTargetID: primaryTargetID,
            targets: canonicalTargets
        )
    }
}

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

package func loadWorkspaceAnalysisManifest(
    at url: URL,
    validateSourceAvailability: Bool = true,
    fileManager: FileManager = .default
) throws -> WorkspaceAnalysisManifest {
    do {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(
            WorkspaceAnalysisManifest.self,
            from: data
        )
        return try manifest.validated(
            validateSourceAvailability: validateSourceAvailability,
            fileManager: fileManager
        )
    } catch let error as WorkspaceAnalysisManifestError {
        throw error
    } catch {
        throw WorkspaceAnalysisManifestError.decodingFailed(
            String(describing: error)
        )
    }
}

package func encodeWorkspaceAnalysisManifest(
    _ manifest: WorkspaceAnalysisManifest,
    validateSourceAvailability: Bool = true,
    fileManager: FileManager = .default
) throws -> Data {
    let normalized = try manifest.validated(
        validateSourceAvailability: validateSourceAvailability,
        fileManager: fileManager
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(normalized)
}

private func validateTarget(
    _ target: WorkspaceAnalysisTarget,
    knownTargetIDs: Set<WorkspaceTargetID>,
    validateSourceAvailability: Bool,
    fileManager: FileManager,
    ownedFilePaths: inout [String: WorkspaceTargetID]
) throws {
    guard isCanonicalManifestAtom(target.packageIdentity) else {
        throw WorkspaceAnalysisManifestError.invalidPackageIdentity(
            target.packageIdentity
        )
    }
    guard isCanonicalManifestName(target.packageDisplayName) else {
        throw WorkspaceAnalysisManifestError.invalidPackageDisplayName(
            target.packageDisplayName
        )
    }
    guard isCanonicalManifestName(target.targetName) else {
        throw WorkspaceAnalysisManifestError.invalidTargetName(
            target.targetName
        )
    }
    guard isCanonicalManifestAtom(target.moduleName) else {
        throw WorkspaceAnalysisManifestError.invalidModuleName(
            target.moduleName
        )
    }
    let expectedID = WorkspaceTargetID.swiftPM(
        packageIdentity: target.packageIdentity,
        moduleName: target.moduleName
    )
    guard target.id == expectedID else {
        throw WorkspaceAnalysisManifestError.nonCanonicalTargetID(
            actual: target.id,
            expected: expectedID
        )
    }
    guard isAbsoluteManifestPath(target.packageDirectory) else {
        throw WorkspaceAnalysisManifestError.nonAbsolutePath(
            target.packageDirectory
        )
    }
    if validateSourceAvailability {
        try validateAvailablePackageDirectory(
            target.packageDirectory,
            fileManager: fileManager
        )
    }
    if target.role == .dependency, target.kind != .generic {
        throw WorkspaceAnalysisManifestError.unsupportedDependencyTargetKind(
            target.id,
            target.kind
        )
    }

    var sourceIdentities = Set<String>()
    for source in target.sources {
        guard isAbsoluteManifestPath(source.filePath) else {
            throw WorkspaceAnalysisManifestError.nonAbsolutePath(
                source.filePath
            )
        }
        guard isCanonicalLogicalPath(source.logicalPath) else {
            throw WorkspaceAnalysisManifestError.invalidLogicalPath(
                source.logicalPath
            )
        }
        guard source.filePath.hasSuffix(".swift"),
              source.logicalPath.hasSuffix(".swift") else {
            throw WorkspaceAnalysisManifestError.nonSwiftSource(
                source.filePath
            )
        }
        let identity = source.identity(in: target.id)
        guard sourceIdentities.insert(identity).inserted else {
            throw WorkspaceAnalysisManifestError.duplicateSourceIdentity(
                identity
            )
        }
        let ownedPath = canonicalManifestPath(source.filePath)
        if let firstTarget = ownedFilePaths[ownedPath] {
            if firstTarget == target.id {
                throw WorkspaceAnalysisManifestError.duplicateSourcePath(
                    target.id,
                    source.filePath
                )
            } else {
                throw WorkspaceAnalysisManifestError.duplicateSourceOwnership(
                    filePath: source.filePath,
                    firstTarget: firstTarget,
                    secondTarget: target.id
                )
            }
        }
        ownedFilePaths[ownedPath] = target.id

        if validateSourceAvailability {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(
                atPath: source.filePath,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue,
            fileManager.isReadableFile(atPath: source.filePath) else {
                throw WorkspaceAnalysisManifestError.unavailableSource(
                    source.filePath
                )
            }
        }
    }

    var directTargets = Set<WorkspaceTargetID>()
    for dependency in target.dependencies {
        guard isCanonicalManifestName(dependency.name) else {
            throw WorkspaceAnalysisManifestError.invalidDependencyName(
                target.id,
                dependency.name
            )
        }
        if let packageIdentity = dependency.packageIdentity,
           !isCanonicalManifestAtom(packageIdentity) {
            throw WorkspaceAnalysisManifestError
                .invalidDependencyPackageIdentity(
                    target.id,
                    packageIdentity
                )
        }
        guard !dependency.targetIDs.isEmpty else {
            throw WorkspaceAnalysisManifestError.emptyDependency(
                target.id,
                dependency.name
            )
        }
        if dependency.kind == .target,
           dependency.targetIDs.count != 1 {
            throw WorkspaceAnalysisManifestError
                .invalidTargetDependencyCardinality(
                    target.id,
                    dependency.name,
                    dependency.targetIDs.count
                )
        }
        for dependencyTargetID in dependency.targetIDs {
            guard dependencyTargetID != target.id else {
                throw WorkspaceAnalysisManifestError.selfDependency(target.id)
            }
            guard knownTargetIDs.contains(dependencyTargetID) else {
                throw WorkspaceAnalysisManifestError.danglingDependency(
                    target.id,
                    dependencyTargetID
                )
            }
            guard directTargets.insert(dependencyTargetID).inserted else {
                throw WorkspaceAnalysisManifestError.duplicateDependencyTarget(
                    target.id,
                    dependencyTargetID
                )
            }
        }
    }
}

private func reachableTargets(
    from primaryTargetID: WorkspaceTargetID,
    targets: [WorkspaceAnalysisTarget]
) -> Set<WorkspaceTargetID> {
    var result: Set<WorkspaceTargetID> = [primaryTargetID]
    var pending = [primaryTargetID]

    while let current = pending.popLast() {
        guard let target = targets.first(where: { $0.id == current }) else {
            continue
        }
        for dependencyID in target.directDependencyTargetIDs
        where result.insert(dependencyID).inserted {
            pending.append(dependencyID)
        }
    }
    return result
}

/// Returns one stable, closed cycle path before reachability validation.
///
/// The primary target anchors a cycle when it participates in one. Other
/// cycles are rotated to their lexicographically smallest stable target ID.
private func targetDependencyCycle(
    from primaryTargetID: WorkspaceTargetID,
    targets: [WorkspaceAnalysisTarget]
) -> [WorkspaceTargetID]? {
    let dependenciesByTarget = Dictionary(
        uniqueKeysWithValues: targets.map {
            ($0.id, $0.directDependencyTargetIDs)
        }
    )
    var completed = Set<WorkspaceTargetID>()
    var activePath: [WorkspaceTargetID] = []
    var activeIndices: [WorkspaceTargetID: Int] = [:]

    func visit(_ targetID: WorkspaceTargetID) -> [WorkspaceTargetID]? {
        if let cycleStart = activeIndices[targetID] {
            let cycle = Array(activePath[cycleStart...]) + [targetID]
            return canonicalTargetDependencyCycle(
                cycle,
                primaryTargetID: primaryTargetID
            )
        }
        guard !completed.contains(targetID) else {
            return nil
        }

        activeIndices[targetID] = activePath.count
        activePath.append(targetID)
        for dependencyID in dependenciesByTarget[targetID, default: []] {
            if let cycle = visit(dependencyID) {
                return cycle
            }
        }
        activePath.removeLast()
        activeIndices[targetID] = nil
        completed.insert(targetID)
        return nil
    }

    let traversalRoots = [primaryTargetID]
        + targets.map(\.id).filter { $0 != primaryTargetID }.sorted()
    for targetID in traversalRoots where !completed.contains(targetID) {
        if let cycle = visit(targetID) {
            return cycle
        }
    }
    return nil
}

private func canonicalTargetDependencyCycle(
    _ closedPath: [WorkspaceTargetID],
    primaryTargetID: WorkspaceTargetID
) -> [WorkspaceTargetID] {
    let cycle = Array(closedPath.dropLast())
    guard !cycle.isEmpty else {
        return closedPath
    }
    let startIndex = cycle.firstIndex(of: primaryTargetID)
        ?? cycle.indices.min { cycle[$0] < cycle[$1] }
        ?? cycle.startIndex
    let rotated = Array(cycle[startIndex...]) + Array(cycle[..<startIndex])
    return rotated + [rotated[0]]
}

private func isCanonicalManifestAtom(_ value: String) -> Bool {
    isCanonicalManifestName(value) && !value.contains(":")
}

private func isCanonicalManifestName(_ value: String) -> Bool {
    !value.isEmpty
        && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        && value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
}

private func isAbsoluteManifestPath(_ path: String) -> Bool {
    path.hasPrefix("/")
}

private func canonicalManifestPath(_ path: String) -> String {
    URL(fileURLWithPath: path)
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
}

private func validateAvailablePackageDirectory(
    _ path: String,
    fileManager: FileManager
) throws {
    var isDirectory = ObjCBool(false)
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
          isDirectory.boolValue,
          fileManager.isReadableFile(atPath: path) else {
        throw WorkspaceAnalysisManifestError.unavailablePackageDirectory(path)
    }
}

private func isCanonicalLogicalPath(_ path: String) -> Bool {
    guard !path.isEmpty,
          !path.hasPrefix("/"),
          path.unicodeScalars.allSatisfy({
              !CharacterSet.controlCharacters.contains($0)
          }) else {
        return false
    }
    return !path.split(separator: "/", omittingEmptySubsequences: false)
        .contains { $0.isEmpty || $0 == "." || $0 == ".." }
}

private struct WorkspacePackageMetadata: Equatable {
    let displayName: String
    let canonicalDirectory: String
}
