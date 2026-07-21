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

    package static func xcode(
        projectIdentity: String,
        moduleName: String
    ) -> Self {
        Self(rawValue: "xcode:\(projectIdentity):\(moduleName)")
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

    func normalized() -> Self {
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

    func normalized() -> Self {
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

/// Constant-time target lookup built once for a validated manifest or source
/// snapshot. Duplicate IDs are omitted so unvalidated test fixtures fail
/// closed instead of selecting an arbitrary target.
package struct WorkspaceAnalysisTargetIndex: Equatable, Sendable {
    private let targetsByID: [WorkspaceTargetID: WorkspaceAnalysisTarget]

    package init(targets: [WorkspaceAnalysisTarget]) {
        targetsByID = Dictionary(grouping: targets, by: \.id)
            .compactMapValues { matches in
                matches.count == 1 ? matches[0] : nil
            }
    }

    package func target(
        id: WorkspaceTargetID
    ) -> WorkspaceAnalysisTarget? {
        targetsByID[id]
    }
}

/// Proof token that a manifest passed the full `validated()` contract.
///
/// `validated()` stats every declared source file and re-runs target-cycle
/// and reachability checks, so the pipeline should prove the contract once
/// per coordinator invocation. APIs that accept this type trust the proof
/// and skip re-validation; the only way to construct it is the throwing
/// validating initializer.
package struct ValidatedWorkspaceAnalysisManifest: Equatable, Sendable {
    /// The canonicalized manifest returned by `validated()`.
    package let manifest: WorkspaceAnalysisManifest
    package let targetIndex: WorkspaceAnalysisTargetIndex

    package init(
        validating manifest: WorkspaceAnalysisManifest,
        validateSourceAvailability: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        let canonicalManifest = try manifest.validated(
            validateSourceAvailability: validateSourceAvailability,
            fileManager: fileManager
        )
        self.manifest = canonicalManifest
        self.targetIndex = WorkspaceAnalysisTargetIndex(
            targets: canonicalManifest.targets
        )
    }
}

package struct WorkspaceAnalysisManifest: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 1
    package static let swiftPMBuildSystem = "swiftpm"
    package static let xcodeBuildSystem = "xcode"
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

    package var sourceIdentities: [String] {
        targets.flatMap { target in
            target.sources.map { $0.identity(in: target.id) }
        }
        .sorted()
    }
}
