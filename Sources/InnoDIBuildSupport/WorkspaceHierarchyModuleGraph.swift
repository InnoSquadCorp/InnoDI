import Foundation
import InnoDIWorkspaceAnalysis
import SwiftSyntax

struct WorkspaceModuleGraphSnapshot: Equatable, Sendable {
    let modules: [WorkspaceModuleRecord]
    let swiftPMProducts: [WorkspaceSwiftPMProductRecord]
    let modulesByID: [String: WorkspaceModuleRecord]

    private let moduleIDsByTargetLookup: [WorkspaceModuleTargetLookup: Set<String>]
    private let swiftPMProductsByLookup: [WorkspaceSwiftPMProductLookup: [WorkspaceSwiftPMProductRecord]]
    private let moduleIDByCachedFilePath: [String: String]

    init(
        modules: [WorkspaceModuleRecord],
        swiftPMProducts: [WorkspaceSwiftPMProductRecord],
        cachedFilePaths: [String] = []
    ) {
        var cached: [String: String] = [:]
        cached.reserveCapacity(cachedFilePaths.count)
        for filePath in cachedFilePaths {
            if let record = Self.bestModuleRecord(forFilePath: filePath, modules: modules) {
                cached[filePath] = record.moduleID
            }
        }
        self.init(
            modules: modules,
            swiftPMProducts: swiftPMProducts,
            moduleIDByCachedFilePath: cached
        )
    }

    /// Designated initializer taking precomputed file→module ownership.
    ///
    /// Manifest-mode callers already know exact, uniquely-owned file paths
    /// per target (the validated manifest rejects duplicate source
    /// ownership), so they pass the ownership map directly instead of
    /// paying the per-file glob-specificity scan across every module.
    init(
        modules: [WorkspaceModuleRecord],
        swiftPMProducts: [WorkspaceSwiftPMProductRecord],
        moduleIDByCachedFilePath: [String: String]
    ) {
        self.modules = modules
        self.swiftPMProducts = swiftPMProducts
        self.modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.moduleID, $0) })
        self.moduleIDsByTargetLookup = Self.buildTargetLookup(modules: modules)
        self.swiftPMProductsByLookup = Dictionary(grouping: swiftPMProducts) {
            WorkspaceSwiftPMProductLookup(
                manifestPath: $0.manifestPath,
                productName: $0.productName
            )
        }
        self.moduleIDByCachedFilePath = moduleIDByCachedFilePath
    }

    func cachingPathMatches(for filePaths: [String]) -> WorkspaceModuleGraphSnapshot {
        var cached = moduleIDByCachedFilePath
        for filePath in filePaths.sorted() where cached[filePath] == nil {
            if let record = Self.bestModuleRecord(forFilePath: filePath, modules: modules) {
                cached[filePath] = record.moduleID
            }
        }
        return WorkspaceModuleGraphSnapshot(
            modules: modules,
            swiftPMProducts: swiftPMProducts,
            moduleIDByCachedFilePath: cached
        )
    }

    func moduleRecord(forFilePath filePath: String) -> WorkspaceModuleRecord? {
        if let cachedModuleID = moduleIDByCachedFilePath[filePath] {
            return modulesByID[cachedModuleID]
        }
        return Self.bestModuleRecord(forFilePath: filePath, modules: modules)
    }

    func moduleRecord(moduleID: String) -> WorkspaceModuleRecord? {
        modulesByID[moduleID]
    }

    func declaresDependencyEdge(from parent: WorkspaceModuleRecord, to child: WorkspaceModuleRecord) -> Bool? {
        if let directDependencyModuleIDs = parent.directDependencyModuleIDs {
            return directDependencyModuleIDs.contains(child.moduleID)
        }

        var sawAmbiguousResolution = false

        for dependencyRef in parent.dependencyRefs {
            switch resolvedDependencyModuleIDs(for: dependencyRef, parent: parent) {
            case .resolved(let moduleIDs):
                if moduleIDs.contains(child.moduleID) {
                    return true
                }
            case .ambiguous, .unknown:
                sawAmbiguousResolution = true
            }
        }

        return sawAmbiguousResolution ? nil : false
    }

    private func resolvedDependencyModuleIDs(
        for dependencyRef: WorkspaceModuleDependencyRef,
        parent: WorkspaceModuleRecord
    ) -> DependencyResolutionResult {
        switch dependencyRef.kind {
        case .localTarget:
            return .resolved(localTargetModuleIDs(for: dependencyRef, parent: parent))

        case .unqualifiedSwiftPMDependency:
            let localTargetModuleIDs = localTargetModuleIDs(for: dependencyRef, parent: parent)
            if !localTargetModuleIDs.isEmpty {
                return .resolved(localTargetModuleIDs)
            }
            return resolveSwiftPMProductModuleIDs(
                productName: dependencyRef.targetName,
                packageReference: dependencyRef.packageReference,
                parent: parent
            )

        case .swiftPMProduct:
            return resolveSwiftPMProductModuleIDs(
                productName: dependencyRef.targetName,
                packageReference: dependencyRef.packageReference,
                parent: parent
            )

        case .tuistProject:
            guard let manifestPath = dependencyRef.manifestPath else {
                return .resolved([])
            }
            return .resolved(
                moduleIDsByTargetLookup[
                    WorkspaceModuleTargetLookup(
                        buildSystem: "tuist",
                        manifestPath: manifestPath,
                        name: dependencyRef.targetName
                    )
                ] ?? []
            )
        }
    }

    private func localTargetModuleIDs(
        for dependencyRef: WorkspaceModuleDependencyRef,
        parent: WorkspaceModuleRecord
    ) -> Set<String> {
        let manifestPath = dependencyRef.manifestPath ?? parent.manifestPath
        return moduleIDsByTargetLookup[
            WorkspaceModuleTargetLookup(
                buildSystem: parent.buildSystem,
                manifestPath: manifestPath,
                name: dependencyRef.targetName
            )
        ] ?? []
    }

    private func resolveSwiftPMProductModuleIDs(
        productName: String,
        packageReference: String?,
        parent: WorkspaceModuleRecord
    ) -> DependencyResolutionResult {
        guard parent.buildSystem == "swiftpm" else {
            return .resolved([])
        }

        let candidateManifestPaths: Set<String>
        if let packageReference {
            let matchingDependencies = parent.swiftPMPackageDependencies.filter { dependency in
                dependency.matches(reference: packageReference)
            }
            if matchingDependencies.isEmpty {
                return .unknown
            }

            let resolvedManifestPaths = Set(matchingDependencies.compactMap(\.resolvedManifestPath))
            if resolvedManifestPaths.isEmpty {
                return .unknown
            }
            if resolvedManifestPaths.count > 1 {
                return .ambiguous
            }
            candidateManifestPaths = resolvedManifestPaths
        } else {
            candidateManifestPaths = Set(parent.swiftPMPackageDependencies.compactMap(\.resolvedManifestPath))
        }

        let matchingProducts = candidateManifestPaths.sorted().flatMap { manifestPath in
            swiftPMProductsByLookup[
                WorkspaceSwiftPMProductLookup(
                    manifestPath: manifestPath,
                    productName: productName
                )
            ] ?? []
        }
        if matchingProducts.count > 1 {
            return .ambiguous
        }
        guard let product = matchingProducts.first else {
            return .resolved([])
        }

        return .resolved(Set(product.exportedModuleIDs))
    }

    private static func buildTargetLookup(modules: [WorkspaceModuleRecord]) -> [WorkspaceModuleTargetLookup: Set<String>] {
        var lookup: [WorkspaceModuleTargetLookup: Set<String>] = [:]
        for module in modules {
            lookup[
                WorkspaceModuleTargetLookup(
                    buildSystem: module.buildSystem,
                    manifestPath: module.manifestPath,
                    name: module.name
                ),
                default: []
            ].insert(module.moduleID)
        }
        return lookup
    }

    private static func bestModuleRecord(
        forFilePath filePath: String,
        modules: [WorkspaceModuleRecord]
    ) -> WorkspaceModuleRecord? {
        var bestRecord: WorkspaceModuleRecord?
        var bestSpecificity = -1
        for module in modules {
            let specificity = module.matchSpecificity(for: filePath)
            guard specificity > bestSpecificity else {
                continue
            }
            guard specificity > 0 || module.matches(filePath: filePath) else {
                continue
            }
            bestRecord = module
            bestSpecificity = specificity
        }
        return bestRecord
    }
}

private enum DependencyResolutionResult: Equatable {
    case resolved(Set<String>)
    case ambiguous
    case unknown
}

private struct WorkspaceModuleTargetLookup: Hashable, Sendable {
    let buildSystem: String
    let manifestPath: String
    let name: String
}

private struct WorkspaceSwiftPMProductLookup: Hashable, Sendable {
    let manifestPath: String
    let productName: String
}

struct WorkspaceModuleRecord: Equatable, Sendable {
    let moduleID: String
    let name: String
    let manifestPath: String
    let packageDisplayName: String?
    let packageIdentity: String?
    let sourcePatterns: [String]
    let dependencyRefs: [WorkspaceModuleDependencyRef]
    let swiftPMPackageDependencies: [WorkspaceSwiftPMPackageDependencyRecord]
    let buildSystem: String
    let directDependencyModuleIDs: Set<String>?

    init(
        moduleID: String,
        name: String,
        manifestPath: String,
        packageDisplayName: String?,
        packageIdentity: String?,
        sourcePatterns: [String],
        dependencyRefs: [WorkspaceModuleDependencyRef],
        swiftPMPackageDependencies: [WorkspaceSwiftPMPackageDependencyRecord],
        buildSystem: String,
        directDependencyModuleIDs: Set<String>? = nil
    ) {
        self.moduleID = moduleID
        self.name = name
        self.manifestPath = manifestPath
        self.packageDisplayName = packageDisplayName
        self.packageIdentity = packageIdentity
        self.sourcePatterns = sourcePatterns
        self.dependencyRefs = dependencyRefs
        self.swiftPMPackageDependencies = swiftPMPackageDependencies
        self.buildSystem = buildSystem
        self.directDependencyModuleIDs = directDependencyModuleIDs
    }

    fileprivate func matches(filePath: String) -> Bool {
        sourcePatterns.contains { glob in
            globMatch(glob, filePath: filePath)
        }
    }

    fileprivate func matchSpecificity(for filePath: String) -> Int {
        sourcePatterns
            .filter { globMatch($0, filePath: filePath) }
            .map { $0.replacingOccurrences(of: "*", with: "").count }
            .max() ?? 0
    }
}

struct WorkspaceSwiftPMPackageDependencyRecord: Equatable, Sendable {
    let referenceNames: [String]
    let resolvedManifestPath: String?

    fileprivate func matches(reference: String) -> Bool {
        let normalizedReference = normalizePackageIdentity(reference)
        return referenceNames.contains(normalizedReference)
    }
}

struct WorkspaceSwiftPMProductRecord: Equatable, Sendable {
    let productID: String
    let productName: String
    let manifestPath: String
    let packageDisplayName: String?
    let packageIdentity: String
    let exportedModuleIDs: [String]
}

struct WorkspaceModuleDependencyRef: Equatable, Sendable {
    enum Kind: String, Sendable {
        case localTarget
        case unqualifiedSwiftPMDependency
        case swiftPMProduct
        case tuistProject
    }

    let kind: Kind
    let targetName: String
    let packageReference: String?
    let manifestPath: String?
}

enum ModuleGraphProvider {
    /// Builds an authoritative module graph from SwiftPM's resolved target
    /// topology instead of re-parsing package manifests.
    static func snapshot(
        manifest: WorkspaceAnalysisManifest
    ) throws -> WorkspaceModuleGraphSnapshot {
        try snapshot(
            validated: ValidatedWorkspaceAnalysisManifest(validating: manifest)
        )
    }

    /// `ValidatedWorkspaceAnalysisManifest` overload used by callers that
    /// already proved the manifest contract once for this invocation.
    static func snapshot(
        validated: ValidatedWorkspaceAnalysisManifest
    ) throws -> WorkspaceModuleGraphSnapshot {
        let manifest = validated.manifest
        let modules = manifest.targets.map { target in
            WorkspaceModuleRecord(
                moduleID: target.id.rawValue,
                name: target.targetName,
                manifestPath: URL(
                    fileURLWithPath: target.packageDirectory
                )
                .appendingPathComponent("Package.swift")
                .path(percentEncoded: false),
                packageDisplayName: target.packageDisplayName,
                packageIdentity: target.packageIdentity,
                sourcePatterns: target.sources.map(\.filePath),
                dependencyRefs: [],
                swiftPMPackageDependencies: [],
                buildSystem: manifest.buildSystem,
                directDependencyModuleIDs: Set(
                    target.directDependencyTargetIDs.map(\.rawValue)
                )
            )
        }
        .sorted { $0.moduleID < $1.moduleID }

        var ownership: [String: String] = [:]
        for target in manifest.targets {
            for source in target.sources {
                ownership[source.filePath] = target.id.rawValue
            }
        }

        return WorkspaceModuleGraphSnapshot(
            modules: modules,
            swiftPMProducts: [],
            moduleIDByCachedFilePath: ownership
        )
    }

    static func snapshot(rootPath: String) throws -> WorkspaceModuleGraphSnapshot {
        let manifestURLs = discoverManifestURLs(rootPath: rootPath)
        var modules: [WorkspaceModuleRecord] = []
        var swiftPMProducts: [WorkspaceSwiftPMProductRecord] = []

        for manifestURL in manifestURLs.packageManifests {
            let manifestSnapshot = try SwiftPMModuleGraphProvider.snapshot(from: manifestURL)
            modules.append(contentsOf: manifestSnapshot.modules)
            swiftPMProducts.append(contentsOf: manifestSnapshot.products)
        }
        for manifestURL in manifestURLs.tuistProjects {
            modules.append(contentsOf: try TuistModuleGraphProvider.modules(from: manifestURL))
        }

        let deduplicatedModules = Dictionary(grouping: modules, by: \.moduleID)
            .compactMap { _, candidates in
                candidates.max { lhs, rhs in
                    lhs.sourcePatterns.joined(separator: "|").count < rhs.sourcePatterns.joined(separator: "|").count
                }
            }
            .sorted { $0.name < $1.name }
        let deduplicatedProducts = Dictionary(grouping: swiftPMProducts, by: \.productID)
            .compactMap { _, candidates in candidates.first }
            .sorted { lhs, rhs in
                if lhs.productName != rhs.productName {
                    return lhs.productName < rhs.productName
                }
                return lhs.manifestPath < rhs.manifestPath
            }

        return WorkspaceModuleGraphSnapshot(
            modules: deduplicatedModules,
            swiftPMProducts: deduplicatedProducts
        )
    }
}

private struct ManifestURLs {
    let packageManifests: [URL]
    let tuistProjects: [URL]
}

private func discoverManifestURLs(rootPath: String) -> ManifestURLs {
    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: rootPath) else {
        return ManifestURLs(packageManifests: [], tuistProjects: [])
    }

    var packageManifests: [URL] = []
    var tuistProjects: [URL] = []

    while let item = enumerator.nextObject() as? String {
        if workspacePathShouldPruneDescendants(item) {
            enumerator.skipDescendants()
            continue
        }

        if item.hasSuffix("/Package.swift") || item == "Package.swift" {
            packageManifests.append(rootURL.appendingPathComponent(item))
        } else if item.hasSuffix("/Project.swift") || item == "Project.swift" {
            tuistProjects.append(rootURL.appendingPathComponent(item))
        }
    }

    return ManifestURLs(
        packageManifests: packageManifests.sorted(by: { $0.path < $1.path }),
        tuistProjects: tuistProjects.sorted(by: { $0.path < $1.path })
    )
}

func normalizeGlobPath(_ path: String, baseURL: URL) -> String {
    let candidate: String
    if path.contains("*") {
        candidate = baseURL.appendingPathComponent(path).path(percentEncoded: false)
    } else if path.hasSuffix(".swift") {
        candidate = baseURL.appendingPathComponent(path).path(percentEncoded: false)
    } else {
        candidate = baseURL.appendingPathComponent(path).appendingPathComponent("**").path(percentEncoded: false)
    }
    return NSString(string: candidate).standardizingPath
}

func labeledStringArgument(_ label: String, in arguments: LabeledExprListSyntax) -> String? {
    stringLiteralValue(labeledExpression(label, in: arguments))
}

func labeledExpression(_ label: String, in arguments: LabeledExprListSyntax) -> ExprSyntax? {
    arguments.first(where: { $0.label?.text == label })?.expression
}

func stringLiteralValue(_ expression: ExprSyntax?) -> String? {
    guard let expression else {
        return nil
    }

    let text = expression.trimmedDescription
    guard text.count >= 2, text.first == "\"", text.last == "\"" else {
        return nil
    }

    return String(text.dropFirst().dropLast())
}

func parseStringArray(from expression: ExprSyntax?) -> [String] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        if let literal = stringLiteralValue(element.expression) {
            return literal
        }

        if let call = element.expression.as(FunctionCallExprSyntax.self),
           let pattern = labeledStringArgument("pattern", in: call.arguments) {
            return pattern
        }

        return nil
    }
}

func workspaceModuleID(buildSystem: String, manifestPath: String, targetName: String) -> String {
    "\(buildSystem)|\(manifestPath)|\(targetName)"
}

func normalizePackageIdentity(_ raw: String) -> String {
    var identity = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if identity.hasSuffix(".git") {
        identity.removeLast(".git".count)
    }
    return identity
}

private func globMatch(_ glob: String, filePath: String) -> Bool {
    let pattern = "^" + NSRegularExpression.escapedPattern(for: NSString(string: glob).standardizingPath)
        .replacingOccurrences(of: "\\*\\*", with: ".*")
        .replacingOccurrences(of: "\\*", with: "[^/]*") + "$"

    return filePath.range(of: pattern, options: .regularExpression) != nil
}
