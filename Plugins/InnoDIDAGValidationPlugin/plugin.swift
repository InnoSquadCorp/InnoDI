import Foundation
import PackagePlugin
#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
#endif

@main
struct InnoDIDAGValidationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let primaryTarget = target as? any SourceModuleTarget else {
            return []
        }

        guard !buildValidationIsDisabled else {
            return []
        }

        let coordinator = try context.tool(named: "InnoDI-DAGValidationCoordinator")
        let outputDirectory = context.pluginWorkDirectoryURL
        let manifest = try WorkspaceAnalysisManifestProducer(
            rootPackage: context.package
        ).produce(primaryTarget: primaryTarget)
        return try makeBuildCommands(
            coordinator: coordinator,
            outputDirectory: outputDirectory,
            targetName: target.name,
            manifest: manifest,
            declaresOutputs: true
        )
    }

}

#if canImport(XcodeProjectPlugin)
extension InnoDIDAGValidationPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        guard !buildValidationIsDisabled else {
            return []
        }

        let coordinator = try context.tool(named: "InnoDI-DAGValidationCoordinator")
        let outputDirectory = context.pluginWorkDirectoryURL
        let manifest = try XcodeWorkspaceAnalysisManifestProducer(
            project: context.xcodeProject
        ).produce(primaryTarget: target)
        return try makeBuildCommands(
            coordinator: coordinator,
            outputDirectory: outputDirectory,
            targetName: target.displayName,
            manifest: manifest,
            declaresOutputs: false
        )
    }
}
#endif

// Opt-out hook for consumers that intentionally skip the build-time DAG gate
// (PoCs, fast iteration loops, or builds running on a shared volume that
// already runs validation in a separate CI job). Production CI must leave the
// variable unset so the gate runs.
private var buildValidationIsDisabled: Bool {
    guard let optOut = ProcessInfo.processInfo.environment[
        "INNODI_DISABLE_BUILD_VALIDATION"
    ] else {
        return false
    }
    return ["1", "true", "yes"].contains(
        optOut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    )
}

private func makeBuildCommands(
    coordinator: PluginContext.Tool,
    outputDirectory: URL,
    targetName: String,
    manifest: WorkspaceAnalysisManifestV1,
    declaresOutputs: Bool
) throws -> [Command] {
    let stateDirectory = outputDirectory.appending(
        path: "innodi-dag-validation-state",
        directoryHint: .isDirectory
    )
    let manifestURL = outputDirectory.appending(path: "workspace-analysis.json")
    try writeManifestIfChanged(manifest, to: manifestURL)

    return [
        .buildCommand(
            displayName: "Validate InnoDI DAG for \(targetName)",
            executable: coordinator.url,
            arguments: [
                "--analysis-manifest", manifestURL.path(percentEncoded: false),
                "--state-dir", stateDirectory.path(percentEncoded: false),
                "--output-dir", outputDirectory.path(percentEncoded: false),
            ],
            inputFiles: [manifestURL] + manifest.sourceFileURLs,
            // Xcode can build one multi-destination target for iOS and watchOS
            // in the same graph while assigning both variants the same plugin
            // work directory. Declaring identical outputs makes those valid
            // variant commands collide. The coordinator still writes its
            // diagnostics into the sandboxed work directory; Xcode variants
            // intentionally run as always-out-of-date validation gates.
            outputFiles: declaresOutputs ? [
                outputDirectory.appending(path: "dag-validation-stamp.txt"),
                outputDirectory.appending(path: "dag-validation-metrics.json"),
                outputDirectory.appending(path: "dag-validation-summary.md"),
            ] : []
        )
    ]
}

private func writeManifestIfChanged(
    _ manifest: WorkspaceAnalysisManifestV1,
    to url: URL
) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)

    if let existingData = try? Data(contentsOf: url), existingData == data {
        return
    }

    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private struct WorkspaceAnalysisManifestProducer {
    private let rootPackage: PackageMetadata
    private let catalog: PackageCatalog

    init(rootPackage: Package) throws {
        var catalog = PackageCatalog()
        try catalog.register(package: rootPackage)
        self.rootPackage = try catalog.metadata(for: rootPackage)
        self.catalog = catalog
    }

    func produce(
        primaryTarget: any SourceModuleTarget
    ) throws -> WorkspaceAnalysisManifestV1 {
        var collector = TargetCollector(catalog: catalog)
        try collector.collect(
            target: primaryTarget,
            package: rootPackage,
            role: .primary
        )
        let targets = try collector.validatedTargets()
        let primaryTargetID = stableTargetID(
            packageIdentity: rootPackage.identity,
            moduleName: primaryTarget.moduleName
        )

        return WorkspaceAnalysisManifestV1(
            schemaVersion: 1,
            buildSystem: "swiftpm",
            analysisScope: "primaryTargetWithVisibleDependencies",
            rootPackageIdentity: rootPackage.identity,
            rootPackageDirectory: rootPackage.directoryPath,
            primaryTargetID: primaryTargetID,
            targets: targets
        )
    }
}

#if canImport(XcodeProjectPlugin)
private struct XcodeWorkspaceAnalysisManifestProducer {
    private let project: XcodeProject
    private let projectIdentity: String
    private let analysisRoot: URL
    private let tuistWorkspaceRoot: URL?

    init(project: XcodeProject) {
        self.project = project
        self.projectIdentity = xcodeProjectIdentity(project.displayName)
        let workspaceRoot = findTuistWorkspaceRoot(
            startingAt: project.directoryURL
        )
        self.tuistWorkspaceRoot = workspaceRoot
        self.analysisRoot = workspaceRoot ?? xcodeAnalysisRoot(project: project)
    }

    func produce(
        primaryTarget: XcodeTarget
    ) throws -> WorkspaceAnalysisManifestV1 {
        let primaryTargetID = xcodeStableTargetID(
            projectIdentity: projectIdentity,
            moduleName: xcodeModuleName(primaryTarget.displayName)
        )
        let targets: [WorkspaceAnalysisTargetV1]
        if let tuistWorkspaceRoot {
            // XcodeProjectPlugin does not expose Tuist's cross-project target
            // dependency graph. Preserve the full workspace source snapshot so
            // declaration and source-level DAG checks remain complete, while
            // leaving module-edge hierarchy validation to a topology-aware CI
            // invocation.
            targets = [
                WorkspaceAnalysisTargetV1(
                    id: primaryTargetID,
                    packageIdentity: projectIdentity,
                    packageDisplayName: project.displayName,
                    packageDirectory: tuistWorkspaceRoot.path(
                        percentEncoded: false
                    ),
                    targetName: primaryTarget.displayName,
                    moduleName: xcodeModuleName(primaryTarget.displayName),
                    kind: xcodeAnalysisKind(of: primaryTarget.product?.kind),
                    role: .primary,
                    sources: try tuistWorkspaceSources(
                        under: tuistWorkspaceRoot
                    ),
                    dependencies: []
                )
            ]
        } else {
            var collector = XcodeTargetCollector(
                projectIdentity: projectIdentity,
                projectDisplayName: project.displayName,
                analysisRoot: analysisRoot
            )
            try collector.collect(target: primaryTarget, role: .primary)
            targets = try collector.validatedTargets()
        }

        return WorkspaceAnalysisManifestV1(
            schemaVersion: 1,
            buildSystem: "xcode",
            analysisScope: "primaryTargetWithVisibleDependencies",
            rootPackageIdentity: projectIdentity,
            rootPackageDirectory: analysisRoot.path(percentEncoded: false),
            primaryTargetID: primaryTargetID,
            targets: targets
        )
    }
}

private struct XcodeTargetCollector {
    let projectIdentity: String
    let projectDisplayName: String
    let analysisRoot: URL
    private var runtimeTargetIDByStableID: [String: XcodeTarget.ID] = [:]
    private var targetsByID: [String: WorkspaceAnalysisTargetV1] = [:]

    init(
        projectIdentity: String,
        projectDisplayName: String,
        analysisRoot: URL
    ) {
        self.projectIdentity = projectIdentity
        self.projectDisplayName = projectDisplayName
        self.analysisRoot = analysisRoot
    }

    mutating func collect(
        target: XcodeTarget,
        role: WorkspaceAnalysisTargetRoleV1
    ) throws {
        let moduleName = xcodeModuleName(target.displayName)
        let targetID = xcodeStableTargetID(
            projectIdentity: projectIdentity,
            moduleName: moduleName
        )
        if let existingRuntimeID = runtimeTargetIDByStableID[targetID] {
            guard existingRuntimeID == target.id else {
                throw WorkspaceManifestProductionError.stableTargetIDCollision(
                    targetID
                )
            }
            return
        }
        runtimeTargetIDByStableID[targetID] = target.id

        let dependencyCollection = try dependencies(of: target)
        for child in dependencyCollection.children {
            try collect(target: child, role: .dependency)
        }

        targetsByID[targetID] = WorkspaceAnalysisTargetV1(
            id: targetID,
            packageIdentity: projectIdentity,
            packageDisplayName: projectDisplayName,
            packageDirectory: analysisRoot.path(percentEncoded: false),
            targetName: target.displayName,
            moduleName: moduleName,
            kind: xcodeAnalysisKind(of: target.product?.kind),
            role: role,
            sources: try sources(of: target),
            dependencies: dependencyCollection.dependencies
        )
    }

    func validatedTargets() throws -> [WorkspaceAnalysisTargetV1] {
        let targets = targetsByID.values.sorted { $0.id < $1.id }
        var sourceOwnerByCanonicalPath: [String: String] = [:]

        for target in targets {
            for source in target.sources {
                let canonicalPath = URL(fileURLWithPath: source.filePath)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                    .path
                if let existingTargetID = sourceOwnerByCanonicalPath[canonicalPath] {
                    throw WorkspaceManifestProductionError.duplicateSourceOwnership(
                        path: source.filePath,
                        firstTargetID: existingTargetID,
                        secondTargetID: target.id
                    )
                }
                sourceOwnerByCanonicalPath[canonicalPath] = target.id
            }
        }
        return targets
    }

    private func dependencies(
        of target: XcodeTarget
    ) throws -> XcodeDependencyCollection {
        var dependencies: [WorkspaceAnalysisDependencyV1] = []
        var childrenByID: [String: XcodeTarget] = [:]

        for dependency in target.dependencies {
            switch dependency {
            case .target(let dependencyTarget):
                guard xcodeAnalysisKind(of: dependencyTarget.product?.kind) == .generic else {
                    continue
                }
                let moduleName = xcodeModuleName(dependencyTarget.displayName)
                let targetID = xcodeStableTargetID(
                    projectIdentity: projectIdentity,
                    moduleName: moduleName
                )
                if let existing = childrenByID[targetID],
                   existing.id != dependencyTarget.id {
                    throw WorkspaceManifestProductionError.stableTargetIDCollision(
                        targetID
                    )
                }
                childrenByID[targetID] = dependencyTarget
                dependencies.append(
                    WorkspaceAnalysisDependencyV1(
                        kind: .target,
                        name: dependencyTarget.displayName,
                        packageIdentity: nil,
                        targetIDs: [targetID]
                    )
                )

            case .product:
                // Xcode's plugin API exposes the package product but not the
                // package graph that owns it. Those modules are compiled as
                // package dependencies and do not provide source ownership to
                // the Xcode target plugin, so they are intentionally omitted.
                continue

            @unknown default:
                continue
            }
        }

        return XcodeDependencyCollection(
            dependencies: dependenciesWithUniqueTargets(
                dependencies.sorted(by: dependencyPrecedes)
            ),
            children: childrenByID
                .sorted { $0.key < $1.key }
                .map(\.value)
        )
    }

    private func sources(
        of target: XcodeTarget
    ) throws -> [WorkspaceAnalysisSourceV1] {
        try target.inputFiles
            .filter { file in
                file.url.pathExtension == "swift"
                    && (file.type == .source || file.type == .unknown)
            }
            .map { file in
                WorkspaceAnalysisSourceV1(
                    filePath: file.url.standardizedFileURL.path,
                    logicalPath: try packageRelativePath(
                        of: file.url,
                        packageDirectory: analysisRoot
                    ),
                    origin: .declared
                )
            }
            .sorted(by: sourcePrecedes)
    }
}

private struct XcodeDependencyCollection {
    let dependencies: [WorkspaceAnalysisDependencyV1]
    let children: [XcodeTarget]
}
#endif

private struct TargetCollector {
    let catalog: PackageCatalog
    private var runtimeTargetIDByStableID: [String: Target.ID] = [:]
    private var targetsByID: [String: WorkspaceAnalysisTargetV1] = [:]

    init(catalog: PackageCatalog) {
        self.catalog = catalog
    }

    mutating func collect(
        target: any SourceModuleTarget,
        package: PackageMetadata,
        role: WorkspaceAnalysisTargetRoleV1
    ) throws {
        let targetID = stableTargetID(
            packageIdentity: package.identity,
            moduleName: target.moduleName
        )
        if let existingRuntimeID = runtimeTargetIDByStableID[targetID] {
            guard existingRuntimeID == target.id else {
                throw WorkspaceManifestProductionError.stableTargetIDCollision(
                    targetID
                )
            }
            return
        }
        runtimeTargetIDByStableID[targetID] = target.id

        let dependencyCollection = try dependencies(of: target)
        for child in dependencyCollection.children {
            try collect(
                target: child.target,
                package: child.package,
                role: .dependency
            )
        }

        targetsByID[targetID] = WorkspaceAnalysisTargetV1(
            id: targetID,
            packageIdentity: package.identity,
            packageDisplayName: package.displayName,
            packageDirectory: package.directoryPath,
            targetName: target.name,
            moduleName: target.moduleName,
            kind: try analysisKind(of: target.kind),
            role: role,
            sources: try sources(of: target, in: package),
            dependencies: dependencyCollection.dependencies
        )
    }

    func validatedTargets() throws -> [WorkspaceAnalysisTargetV1] {
        let targets = targetsByID.values.sorted { $0.id < $1.id }
        var sourceOwnerByCanonicalPath: [String: String] = [:]

        for target in targets {
            for source in target.sources {
                let canonicalPath = URL(fileURLWithPath: source.filePath)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                    .path
                if let existingTargetID = sourceOwnerByCanonicalPath[canonicalPath] {
                    throw WorkspaceManifestProductionError.duplicateSourceOwnership(
                        path: source.filePath,
                        firstTargetID: existingTargetID,
                        secondTargetID: target.id
                    )
                }
                sourceOwnerByCanonicalPath[canonicalPath] = target.id
            }
        }
        return targets
    }

    private func dependencies(
        of target: any SourceModuleTarget
    ) throws -> DependencyCollection {
        var dependencies: [WorkspaceAnalysisDependencyV1] = []
        var childrenByID: [String: VisibleTarget] = [:]

        for dependency in target.dependencies {
            switch dependency {
            case .target(let dependencyTarget):
                guard let sourceTarget = dependencyTarget as? any SourceModuleTarget,
                      sourceTarget.kind == .generic else {
                    continue
                }
                let package = try catalog.metadata(for: dependencyTarget)
                let targetID = stableTargetID(
                    packageIdentity: package.identity,
                    moduleName: sourceTarget.moduleName
                )
                try insertChild(
                    VisibleTarget(target: sourceTarget, package: package),
                    id: targetID,
                    into: &childrenByID
                )
                dependencies.append(
                    WorkspaceAnalysisDependencyV1(
                        kind: .target,
                        name: dependencyTarget.name,
                        packageIdentity: nil,
                        targetIDs: [targetID]
                    )
                )

            case .product(let product):
                let productPackage = try catalog.metadata(for: product)
                var productTargetsByID: [String: VisibleTarget] = [:]
                for productTarget in product.targets {
                    guard let sourceTarget = productTarget as? any SourceModuleTarget,
                          sourceTarget.kind == .generic else {
                        continue
                    }
                    let targetPackage = try catalog.metadata(for: productTarget)
                    guard targetPackage.identity == productPackage.identity else {
                        throw WorkspaceManifestProductionError.productTargetPackageMismatch(
                            product: product.name,
                            target: productTarget.name
                        )
                    }
                    let targetID = stableTargetID(
                        packageIdentity: targetPackage.identity,
                        moduleName: sourceTarget.moduleName
                    )
                    try insertChild(
                        VisibleTarget(target: sourceTarget, package: targetPackage),
                        id: targetID,
                        into: &productTargetsByID
                    )
                }

                guard !productTargetsByID.isEmpty else {
                    continue
                }
                for (targetID, child) in productTargetsByID {
                    try insertChild(child, id: targetID, into: &childrenByID)
                }
                dependencies.append(
                    WorkspaceAnalysisDependencyV1(
                        kind: .product,
                        name: product.name,
                        packageIdentity: productPackage.identity,
                        targetIDs: productTargetsByID.keys.sorted()
                    )
                )

            @unknown default:
                continue
            }
        }

        let canonicalDependencies = dependenciesWithUniqueTargets(
            dependencies.sorted(by: dependencyPrecedes)
        )
        return DependencyCollection(
            dependencies: canonicalDependencies,
            children: childrenByID
                .sorted { $0.key < $1.key }
                .map(\.value)
        )
    }

    private func insertChild(
        _ child: VisibleTarget,
        id: String,
        into childrenByID: inout [String: VisibleTarget]
    ) throws {
        if let existing = childrenByID[id] {
            guard existing.target.id == child.target.id else {
                throw WorkspaceManifestProductionError.stableTargetIDCollision(id)
            }
            return
        }
        childrenByID[id] = child
    }

    private func sources(
        of target: any SourceModuleTarget,
        in package: PackageMetadata
    ) throws -> [WorkspaceAnalysisSourceV1] {
        let declaredSources = try target.sourceFiles
            .map(\.url)
            .filter { $0.pathExtension == "swift" }
            .map { sourceURL in
                WorkspaceAnalysisSourceV1(
                    filePath: sourceURL.standardizedFileURL.path,
                    logicalPath: try packageRelativePath(
                        of: sourceURL,
                        packageDirectory: package.directoryURL
                    ),
                    origin: .declared
                )
            }

        let generatedSourceURLs = target.pluginGeneratedSources
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
        var generatedPathByBasename: [String: String] = [:]
        let generatedSources = try generatedSourceURLs.map { sourceURL in
            let basename = sourceURL.lastPathComponent
            if let existingPath = generatedPathByBasename[basename] {
                throw WorkspaceManifestProductionError.generatedSourceBasenameCollision(
                    target: target.name,
                    basename: basename,
                    firstPath: existingPath,
                    secondPath: sourceURL.path(percentEncoded: false)
                )
            }
            generatedPathByBasename[basename] = sourceURL.path(percentEncoded: false)
            return WorkspaceAnalysisSourceV1(
                filePath: sourceURL.standardizedFileURL.path,
                logicalPath: "__generated__/\(basename)",
                origin: .generated
            )
        }

        return (declaredSources + generatedSources).sorted(by: sourcePrecedes)
    }
}

private struct PackageCatalog {
    private var packageByIdentity: [Package.ID: PackageMetadata] = [:]
    private var packageByRuntimeTargetID: [Target.ID: PackageMetadata] = [:]
    private var packageByRuntimeProductID: [Product.ID: PackageMetadata] = [:]

    mutating func register(package: Package) throws {
        let metadata = PackageMetadata(
            identity: package.id,
            displayName: package.displayName,
            directoryURL: package.directoryURL.standardizedFileURL
        )
        if let existing = packageByIdentity[package.id] {
            guard existing == metadata else {
                throw WorkspaceManifestProductionError.inconsistentPackageMetadata(
                    package.id
                )
            }
            return
        }
        packageByIdentity[package.id] = metadata

        for target in package.targets {
            try Self.register(
                metadata,
                runtimeID: target.id,
                name: target.name,
                in: &packageByRuntimeTargetID
            )
        }
        for product in package.products {
            try Self.register(
                metadata,
                runtimeID: product.id,
                name: product.name,
                in: &packageByRuntimeProductID
            )
        }
        for dependency in package.dependencies.sorted(by: {
            $0.package.id < $1.package.id
        }) {
            try register(package: dependency.package)
        }
    }

    func metadata(for package: Package) throws -> PackageMetadata {
        guard let metadata = packageByIdentity[package.id] else {
            throw WorkspaceManifestProductionError.unknownPackage(package.id)
        }
        return metadata
    }

    func metadata(for target: any Target) throws -> PackageMetadata {
        guard let metadata = packageByRuntimeTargetID[target.id] else {
            throw WorkspaceManifestProductionError.unknownTarget(target.name)
        }
        return metadata
    }

    func metadata(for product: any Product) throws -> PackageMetadata {
        guard let metadata = packageByRuntimeProductID[product.id] else {
            throw WorkspaceManifestProductionError.unknownProduct(product.name)
        }
        return metadata
    }

    private static func register<Key: Hashable>(
        _ metadata: PackageMetadata,
        runtimeID: Key,
        name: String,
        in owners: inout [Key: PackageMetadata]
    ) throws {
        if let existing = owners[runtimeID], existing != metadata {
            throw WorkspaceManifestProductionError.runtimeIdentityCollision(name)
        }
        owners[runtimeID] = metadata
    }
}

private struct PackageMetadata: Equatable {
    let identity: String
    let displayName: String
    let directoryURL: URL

    var directoryPath: String {
        directoryURL.path(percentEncoded: false)
    }
}

private struct VisibleTarget {
    let target: any SourceModuleTarget
    let package: PackageMetadata
}

private struct DependencyCollection {
    let dependencies: [WorkspaceAnalysisDependencyV1]
    let children: [VisibleTarget]
}

private struct WorkspaceAnalysisManifestV1: Encodable {
    let schemaVersion: Int
    let buildSystem: String
    let analysisScope: String
    let rootPackageIdentity: String
    let rootPackageDirectory: String
    let primaryTargetID: String
    let targets: [WorkspaceAnalysisTargetV1]

    var sourceFileURLs: [URL] {
        targets
            .flatMap(\.sources)
            .map { URL(fileURLWithPath: $0.filePath) }
            .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }
}

private struct WorkspaceAnalysisTargetV1: Encodable {
    let id: String
    let packageIdentity: String
    let packageDisplayName: String
    let packageDirectory: String
    let targetName: String
    let moduleName: String
    let kind: WorkspaceAnalysisTargetKindV1
    let role: WorkspaceAnalysisTargetRoleV1
    let sources: [WorkspaceAnalysisSourceV1]
    let dependencies: [WorkspaceAnalysisDependencyV1]
}

private enum WorkspaceAnalysisTargetKindV1: String, Encodable, Equatable {
    case generic
    case executable
    case snippet
    case macro
    case test
}

private enum WorkspaceAnalysisTargetRoleV1: String, Encodable {
    case primary
    case dependency
}

private struct WorkspaceAnalysisSourceV1: Encodable {
    let filePath: String
    let logicalPath: String
    let origin: WorkspaceAnalysisSourceOriginV1
}

private enum WorkspaceAnalysisSourceOriginV1: String, Encodable {
    case declared
    case generated
}

private struct WorkspaceAnalysisDependencyV1: Encodable {
    let kind: WorkspaceAnalysisDependencyKindV1
    let name: String
    let packageIdentity: String?
    let targetIDs: [String]
}

private enum WorkspaceAnalysisDependencyKindV1: String, Encodable {
    case target
    case product
}

private enum WorkspaceManifestProductionError: LocalizedError {
    case unknownPackage(String)
    case unknownTarget(String)
    case unknownProduct(String)
    case inconsistentPackageMetadata(String)
    case runtimeIdentityCollision(String)
    case stableTargetIDCollision(String)
    case productTargetPackageMismatch(product: String, target: String)
    case sourceOutsidePackage(source: String, package: String)
    case generatedSourceBasenameCollision(
        target: String,
        basename: String,
        firstPath: String,
        secondPath: String
    )
    case duplicateSourceOwnership(
        path: String,
        firstTargetID: String,
        secondTargetID: String
    )
    case unsupportedPrimaryTargetKind(String)

    var errorDescription: String? {
        switch self {
        case .unknownPackage(let identity):
            return "Workspace analysis could not resolve package '\(identity)'."
        case .unknownTarget(let name):
            return "Workspace analysis could not resolve the package owning target '\(name)'."
        case .unknownProduct(let name):
            return "Workspace analysis could not resolve the package owning product '\(name)'."
        case .inconsistentPackageMetadata(let identity):
            return "Workspace package '\(identity)' has inconsistent metadata."
        case .runtimeIdentityCollision(let name):
            return "SwiftPM reused an invocation-local identity while resolving '\(name)'."
        case .stableTargetIDCollision(let id):
            return "Workspace analysis target ID '\(id)' resolves to multiple SwiftPM targets."
        case .productTargetPackageMismatch(let product, let target):
            return "SwiftPM product '\(product)' exposes target '\(target)' from another package."
        case .sourceOutsidePackage(let source, let package):
            return "Declared Swift source '\(source)' is outside package '\(package)'."
        case .generatedSourceBasenameCollision(
            let target,
            let basename,
            let firstPath,
            let secondPath
        ):
            return "Generated Swift sources for target '\(target)' share basename '\(basename)': '\(firstPath)' and '\(secondPath)'."
        case .duplicateSourceOwnership(let path, let first, let second):
            return "Swift source '\(path)' is owned by both '\(first)' and '\(second)'."
        case .unsupportedPrimaryTargetKind(let kind):
            return "Workspace analysis does not recognize primary target kind '\(kind)'."
        }
    }
}

private func stableTargetID(
    packageIdentity: String,
    moduleName: String
) -> String {
    "swiftpm:\(packageIdentity):\(moduleName)"
}

#if canImport(XcodeProjectPlugin)
private func xcodeStableTargetID(
    projectIdentity: String,
    moduleName: String
) -> String {
    "xcode:\(projectIdentity):\(moduleName)"
}

private func xcodeProjectIdentity(_ displayName: String) -> String {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let sanitizedScalars = trimmed.unicodeScalars.map { scalar -> String in
        if CharacterSet.controlCharacters.contains(scalar) || scalar == ":" {
            return "-"
        }
        return String(scalar)
    }
    let identity = sanitizedScalars.joined()
    return identity.isEmpty ? "xcode-project" : identity
}

private func xcodeModuleName(_ targetName: String) -> String {
    let scalars = targetName.unicodeScalars.map { scalar -> String in
        if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
            return String(scalar)
        }
        return "_"
    }
    var moduleName = scalars.joined()
    if moduleName.isEmpty {
        moduleName = "_"
    }
    if let first = moduleName.unicodeScalars.first,
       CharacterSet.decimalDigits.contains(first) {
        moduleName.insert("_", at: moduleName.startIndex)
    }
    return moduleName
}

private func xcodeAnalysisKind(
    of kind: XcodeProduct.Kind?
) -> WorkspaceAnalysisTargetKindV1 {
    guard let kind else {
        return .generic
    }
    switch kind {
    case .application, .executable:
        return .executable
    case .framework, .library, .other:
        return .generic
    @unknown default:
        return .generic
    }
}

private func xcodeAnalysisRoot(project: XcodeProject) -> URL {
    let projectDirectory = project.directoryURL.standardizedFileURL
    let sourceURLs = project.targets.flatMap { target in
        target.inputFiles
            .map(\.url)
            .filter { $0.pathExtension == "swift" }
    }
    let paths = [projectDirectory] + sourceURLs.map(\.standardizedFileURL)
    var commonComponents = projectDirectory.pathComponents

    for path in paths.dropFirst() {
        let components = path.pathComponents
        let count = zip(commonComponents, components)
            .prefix { $0 == $1 }
            .count
        commonComponents = Array(commonComponents.prefix(count))
    }

    guard !commonComponents.isEmpty else {
        return projectDirectory
    }
    return URL(
        fileURLWithPath: NSString.path(withComponents: commonComponents),
        isDirectory: true
    ).standardizedFileURL
}

private func findTuistWorkspaceRoot(startingAt directory: URL) -> URL? {
    let fileManager = FileManager.default
    var candidate = directory.standardizedFileURL

    while candidate.path != "/" {
        let workspaceManifest = candidate.appending(path: "Workspace.swift")
        let tuistManifest = candidate.appending(path: "Tuist.swift")
        if fileManager.fileExists(atPath: workspaceManifest.path),
           fileManager.fileExists(atPath: tuistManifest.path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }
    return nil
}

private func tuistWorkspaceSources(
    under workspaceRoot: URL
) throws -> [WorkspaceAnalysisSourceV1] {
    let fileManager = FileManager.default
    let skippedDirectoryNames: Set<String> = [
        ".build",
        ".git",
        "Derived",
        "Tests",
        "Tuist",
        "UITests",
    ]
    guard let enumerator = fileManager.enumerator(
        at: workspaceRoot,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var sources: [WorkspaceAnalysisSourceV1] = []
    for case let fileURL as URL in enumerator {
        let resourceValues = try fileURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey]
        )
        if resourceValues.isDirectory == true {
            if skippedDirectoryNames.contains(fileURL.lastPathComponent)
                || fileURL.pathExtension == "xcodeproj"
                || fileURL.pathExtension == "xcworkspace" {
                enumerator.skipDescendants()
            }
            continue
        }
        guard resourceValues.isRegularFile == true,
              fileURL.pathExtension == "swift",
              !["Project.swift", "Tuist.swift", "Workspace.swift"].contains(
                  fileURL.lastPathComponent
              ) else {
            continue
        }
        sources.append(
            WorkspaceAnalysisSourceV1(
                filePath: fileURL.standardizedFileURL.path,
                logicalPath: try packageRelativePath(
                    of: fileURL,
                    packageDirectory: workspaceRoot
                ),
                origin: .declared
            )
        )
    }
    return sources.sorted(by: sourcePrecedes)
}
#endif

private func analysisKind(
    of kind: ModuleKind
) throws -> WorkspaceAnalysisTargetKindV1 {
    switch kind {
    case .generic:
        return .generic
    case .executable:
        return .executable
    case .snippet:
        return .snippet
    case .macro:
        return .macro
    case .test:
        return .test
    @unknown default:
        throw WorkspaceManifestProductionError.unsupportedPrimaryTargetKind(
            String(describing: kind)
        )
    }
}

private func packageRelativePath(
    of sourceURL: URL,
    packageDirectory: URL
) throws -> String {
    let sourceComponents = sourceURL.standardizedFileURL.pathComponents
    let packageComponents = packageDirectory.standardizedFileURL.pathComponents
    guard sourceComponents.count > packageComponents.count,
          sourceComponents.starts(with: packageComponents) else {
        throw WorkspaceManifestProductionError.sourceOutsidePackage(
            source: sourceURL.path(percentEncoded: false),
            package: packageDirectory.path(percentEncoded: false)
        )
    }
    return sourceComponents.dropFirst(packageComponents.count).joined(separator: "/")
}

private func sourcePrecedes(
    _ lhs: WorkspaceAnalysisSourceV1,
    _ rhs: WorkspaceAnalysisSourceV1
) -> Bool {
    if lhs.logicalPath != rhs.logicalPath {
        return lhs.logicalPath < rhs.logicalPath
    }
    if lhs.origin.rawValue != rhs.origin.rawValue {
        return lhs.origin.rawValue < rhs.origin.rawValue
    }
    return lhs.filePath < rhs.filePath
}

private func dependencyPrecedes(
    _ lhs: WorkspaceAnalysisDependencyV1,
    _ rhs: WorkspaceAnalysisDependencyV1
) -> Bool {
    if lhs.kind.rawValue != rhs.kind.rawValue {
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
    if lhs.name != rhs.name {
        return lhs.name < rhs.name
    }
    if lhs.packageIdentity != rhs.packageIdentity {
        return (lhs.packageIdentity ?? "") < (rhs.packageIdentity ?? "")
    }
    return lhs.targetIDs.lexicographicallyPrecedes(rhs.targetIDs)
}

private func dependenciesWithUniqueTargets(
    _ dependencies: [WorkspaceAnalysisDependencyV1]
) -> [WorkspaceAnalysisDependencyV1] {
    var assignedTargetIDs = Set<String>()
    return dependencies.compactMap { dependency in
        let targetIDs = dependency.targetIDs
            .sorted()
            .filter { assignedTargetIDs.insert($0).inserted }
        guard !targetIDs.isEmpty else {
            return nil
        }
        return WorkspaceAnalysisDependencyV1(
            kind: dependency.kind,
            name: dependency.name,
            packageIdentity: dependency.packageIdentity,
            targetIDs: targetIDs
        )
    }
}
