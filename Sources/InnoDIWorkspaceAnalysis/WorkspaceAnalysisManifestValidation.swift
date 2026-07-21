import Foundation

extension WorkspaceAnalysisManifest {
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
        let canonicalTargetsByID = Dictionary(
            uniqueKeysWithValues: canonicalTargets.map { ($0.id, $0) }
        )
        let primaryRoleTargets = canonicalTargets.filter {
            $0.role == .primary
        }
        guard primaryRoleTargets.count == 1,
              primaryRoleTargets[0].id == primaryTargetID,
              let primaryTarget = canonicalTargetsByID[primaryTargetID] else {
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
            targetsByID: canonicalTargetsByID
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

        if source.origin == .declared {
            guard let expectedLogicalPath = packageRelativeManifestPath(
                source.filePath,
                packageDirectory: target.packageDirectory
            ) else {
                throw WorkspaceAnalysisManifestError
                    .declaredSourceOutsidePackage(
                        target: target.id,
                        filePath: source.filePath,
                        packageDirectory: target.packageDirectory
                    )
            }
            guard source.logicalPath == expectedLogicalPath else {
                throw WorkspaceAnalysisManifestError
                    .declaredSourceLogicalPathMismatch(
                        target: target.id,
                        expected: expectedLogicalPath,
                        actual: source.logicalPath
                    )
            }
        }

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
    targetsByID: [WorkspaceTargetID: WorkspaceAnalysisTarget]
) -> Set<WorkspaceTargetID> {
    var result: Set<WorkspaceTargetID> = [primaryTargetID]
    var pending = [primaryTargetID]

    while let current = pending.popLast() {
        guard let target = targetsByID[current] else {
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

private func packageRelativeManifestPath(
    _ filePath: String,
    packageDirectory: String
) -> String? {
    let fileComponents = URL(fileURLWithPath: canonicalManifestPath(filePath))
        .pathComponents
    let packageComponents = URL(
        fileURLWithPath: canonicalManifestPath(packageDirectory),
        isDirectory: true
    ).pathComponents
    guard fileComponents.count > packageComponents.count,
          fileComponents.starts(with: packageComponents) else {
        return nil
    }
    return fileComponents.dropFirst(packageComponents.count)
        .joined(separator: "/")
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
