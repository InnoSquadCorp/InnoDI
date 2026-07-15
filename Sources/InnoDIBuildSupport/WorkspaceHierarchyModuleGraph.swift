import Foundation
import InnoDIWorkspaceAnalysis
import SwiftParser
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

        var cached: [String: String] = [:]
        cached.reserveCapacity(cachedFilePaths.count)
        for filePath in cachedFilePaths {
            if let record = Self.bestModuleRecord(forFilePath: filePath, modules: modules) {
                cached[filePath] = record.moduleID
            }
        }
        self.moduleIDByCachedFilePath = cached
    }

    func cachingPathMatches(for filePaths: [String]) -> WorkspaceModuleGraphSnapshot {
        WorkspaceModuleGraphSnapshot(
            modules: modules,
            swiftPMProducts: swiftPMProducts,
            cachedFilePaths: filePaths.sorted()
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
        let manifest = try manifest.validated()
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
                buildSystem: WorkspaceAnalysisManifest.swiftPMBuildSystem,
                directDependencyModuleIDs: Set(
                    target.directDependencyTargetIDs.map(\.rawValue)
                )
            )
        }
        .sorted { $0.moduleID < $1.moduleID }

        return WorkspaceModuleGraphSnapshot(
            modules: modules,
            swiftPMProducts: [],
            cachedFilePaths: manifest.targets.flatMap { target in
                target.sources.map(\.filePath)
            }
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

private enum SwiftPMModuleGraphProvider {
    static func snapshot(from manifestURL: URL) throws -> SwiftPMManifestSnapshot {
        let source = try String(contentsOf: manifestURL, encoding: .utf8)
        let syntax = Parser.parse(source: source)
        let collector = SwiftPMManifestCollector(manifestURL: manifestURL)
        collector.walk(syntax)
        return collector.snapshot
    }
}

private struct SwiftPMManifestSnapshot {
    let modules: [WorkspaceModuleRecord]
    let products: [WorkspaceSwiftPMProductRecord]
}

private enum TuistModuleGraphProvider {
    static func modules(from manifestURL: URL) throws -> [WorkspaceModuleRecord] {
        let source = try String(contentsOf: manifestURL, encoding: .utf8)
        let syntax = Parser.parse(source: source)
        let collector = TuistManifestCollector(manifestURL: manifestURL)
        collector.walk(syntax)
        return collector.modules
    }
}

private final class SwiftPMManifestCollector: SyntaxVisitor {
    private let manifestDirectoryURL: URL
    private let manifestPath: String
    private(set) var modules: [WorkspaceModuleRecord] = []
    private var packageDisplayName: String?
    private var packageIdentity: String
    private var packageDependencies: [WorkspaceSwiftPMPackageDependencyRecord] = []
    private var productBuilders: [SwiftPMProductBuilder] = []

    init(manifestURL: URL) {
        self.manifestDirectoryURL = manifestURL.deletingLastPathComponent()
        self.manifestPath = NSString(string: manifestURL.path(percentEncoded: false)).standardizingPath
        self.packageIdentity = normalizePackageIdentity(manifestURL.deletingLastPathComponent().lastPathComponent)
        super.init(viewMode: .sourceAccurate)
    }

    var snapshot: SwiftPMManifestSnapshot {
        let products = productBuilders.map { builder in
            WorkspaceSwiftPMProductRecord(
                productID: swiftPMProductID(manifestPath: manifestPath, productName: builder.productName),
                productName: builder.productName,
                manifestPath: manifestPath,
                packageDisplayName: packageDisplayName,
                packageIdentity: packageIdentity,
                exportedModuleIDs: builder.targetNames.map {
                    workspaceModuleID(buildSystem: "swiftpm", manifestPath: manifestPath, targetName: $0)
                }
            )
        }
        return SwiftPMManifestSnapshot(modules: modules, products: products)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let declReference = node.calledExpression.as(DeclReferenceExprSyntax.self),
           declReference.baseName.text == "Package" {
            packageDisplayName = labeledStringArgument("name", in: node.arguments)
            packageIdentity = normalizePackageIdentity(packageDisplayName ?? manifestDirectoryURL.lastPathComponent)
            packageDependencies = parseSwiftPMPackageDependencies(
                from: labeledExpression("dependencies", in: node.arguments),
                manifestDirectoryURL: manifestDirectoryURL
            )
            productBuilders = parseSwiftPMProducts(from: labeledExpression("products", in: node.arguments))
            return .visitChildren
        }

        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil else {
            return .visitChildren
        }

        let kind = memberAccess.declName.baseName.text
        guard ["target", "executableTarget", "macro", "testTarget"].contains(kind) else {
            return .visitChildren
        }

        guard let name = labeledStringArgument("name", in: node.arguments) else {
            return .visitChildren
        }

        let dependencies = parseSwiftPMDependencyRefs(
            from: labeledExpression("dependencies", in: node.arguments),
            manifestPath: manifestPath
        )
        let explicitSources = parseStringArray(from: labeledExpression("sources", in: node.arguments))
        let explicitPath = labeledStringArgument("path", in: node.arguments)
        let defaultDirectory = kind == "testTarget" ? "Tests/\(name)" : "Sources/\(name)"
        let targetDirectoryURL = manifestDirectoryURL.appendingPathComponent(explicitPath ?? defaultDirectory)

        let sourcePatterns: [String]
        if !explicitSources.isEmpty {
            sourcePatterns = explicitSources.map {
                normalizeGlobPath($0, baseURL: targetDirectoryURL)
            }
        } else if let explicitPath {
            sourcePatterns = [normalizeGlobPath(explicitPath, baseURL: manifestDirectoryURL)]
        } else {
            sourcePatterns = [normalizeGlobPath(defaultDirectory, baseURL: manifestDirectoryURL)]
        }

        modules.append(
            WorkspaceModuleRecord(
                moduleID: workspaceModuleID(buildSystem: "swiftpm", manifestPath: manifestPath, targetName: name),
                name: name,
                manifestPath: manifestPath,
                packageDisplayName: packageDisplayName,
                packageIdentity: packageIdentity,
                sourcePatterns: sourcePatterns,
                dependencyRefs: dependencies,
                swiftPMPackageDependencies: packageDependencies,
                buildSystem: "swiftpm"
            )
        )

        return .skipChildren
    }
}

private final class TuistManifestCollector: SyntaxVisitor {
    private let manifestDirectoryURL: URL
    private let manifestPath: String
    private(set) var modules: [WorkspaceModuleRecord] = []

    init(manifestURL: URL) {
        self.manifestDirectoryURL = manifestURL.deletingLastPathComponent()
        self.manifestPath = NSString(string: manifestURL.path(percentEncoded: false)).standardizingPath
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isTuistTargetCall(node) else {
            return .visitChildren
        }

        guard let name = labeledStringArgument("name", in: node.arguments) else {
            return .visitChildren
        }

        let sources = parseStringArray(from: labeledExpression("sources", in: node.arguments))
        let dependencies = parseTuistDependencyRefs(
            from: labeledExpression("dependencies", in: node.arguments),
            manifestDirectoryURL: manifestDirectoryURL,
            manifestPath: manifestPath
        )
        let sourcePatterns = (sources.isEmpty ? ["Sources/**"] : sources).map {
            normalizeGlobPath($0, baseURL: manifestDirectoryURL)
        }

        modules.append(
            WorkspaceModuleRecord(
                moduleID: workspaceModuleID(buildSystem: "tuist", manifestPath: manifestPath, targetName: name),
                name: name,
                manifestPath: manifestPath,
                packageDisplayName: nil,
                packageIdentity: nil,
                sourcePatterns: sourcePatterns,
                dependencyRefs: dependencies,
                swiftPMPackageDependencies: [],
                buildSystem: "tuist"
            )
        )

        return .skipChildren
    }
}

private struct SwiftPMProductBuilder {
    let productName: String
    let targetNames: [String]
}

private func normalizeGlobPath(_ path: String, baseURL: URL) -> String {
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

private func labeledStringArgument(_ label: String, in arguments: LabeledExprListSyntax) -> String? {
    stringLiteralValue(labeledExpression(label, in: arguments))
}

private func labeledExpression(_ label: String, in arguments: LabeledExprListSyntax) -> ExprSyntax? {
    arguments.first(where: { $0.label?.text == label })?.expression
}

private func stringLiteralValue(_ expression: ExprSyntax?) -> String? {
    guard let expression else {
        return nil
    }

    let text = expression.trimmedDescription
    guard text.count >= 2, text.first == "\"", text.last == "\"" else {
        return nil
    }

    return String(text.dropFirst().dropLast())
}

private func parseStringArray(from expression: ExprSyntax?) -> [String] {
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

private func workspaceModuleID(buildSystem: String, manifestPath: String, targetName: String) -> String {
    "\(buildSystem)|\(manifestPath)|\(targetName)"
}

private func swiftPMProductID(manifestPath: String, productName: String) -> String {
    "\(manifestPath)|product|\(productName)"
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

private func parseSwiftPMPackageDependencies(
    from expression: ExprSyntax?,
    manifestDirectoryURL: URL
) -> [WorkspaceSwiftPMPackageDependencyRecord] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        guard let call = element.expression.as(FunctionCallExprSyntax.self) else {
            return nil
        }

        let explicitName = labeledStringArgument("name", in: call.arguments)
        let localPath = labeledStringArgument("path", in: call.arguments)
        let url = labeledStringArgument("url", in: call.arguments)

        let resolvedManifestPath = localPath.map { path in
            NSString(
                string: manifestDirectoryURL
                    .appendingPathComponent(path)
                    .appendingPathComponent("Package.swift")
                    .path(percentEncoded: false)
            ).standardizingPath
        }
        let inferredIdentitySource = explicitName
            ?? localPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? url.map { URL(string: $0)?.deletingPathExtension().lastPathComponent ?? $0 }
        let referenceNames = [explicitName, inferredIdentitySource]
            .compactMap { $0 }
            .map(normalizePackageIdentity)
        let uniqueReferenceNames = Array(Set(referenceNames)).sorted()

        return WorkspaceSwiftPMPackageDependencyRecord(
            referenceNames: uniqueReferenceNames,
            resolvedManifestPath: resolvedManifestPath
        )
    }
}

private func parseSwiftPMProducts(from expression: ExprSyntax?) -> [SwiftPMProductBuilder] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        guard let call = element.expression.as(FunctionCallExprSyntax.self),
              let productName = labeledStringArgument("name", in: call.arguments) else {
            return nil
        }
        let targetNames = parseStringArray(from: labeledExpression("targets", in: call.arguments))
        return SwiftPMProductBuilder(productName: productName, targetNames: targetNames)
    }
}

private func parseSwiftPMDependencyRefs(
    from expression: ExprSyntax?,
    manifestPath: String
) -> [WorkspaceModuleDependencyRef] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        if let literal = stringLiteralValue(element.expression) {
            return WorkspaceModuleDependencyRef(
                kind: .unqualifiedSwiftPMDependency,
                targetName: literal,
                packageReference: nil,
                manifestPath: manifestPath
            )
        }

        guard let call = element.expression.as(FunctionCallExprSyntax.self) else {
            return nil
        }

        let targetName = labeledStringArgument("name", in: call.arguments)
            ?? labeledStringArgument("target", in: call.arguments)

        guard let targetName else {
            return nil
        }

        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            switch memberAccess.declName.baseName.text {
            case "product":
                return WorkspaceModuleDependencyRef(
                    kind: .swiftPMProduct,
                    targetName: targetName,
                    packageReference: labeledStringArgument("package", in: call.arguments),
                    manifestPath: nil
                )
            case "target":
                return WorkspaceModuleDependencyRef(
                    kind: .localTarget,
                    targetName: targetName,
                    packageReference: nil,
                    manifestPath: manifestPath
                )
            case "byName":
                return WorkspaceModuleDependencyRef(
                    kind: .unqualifiedSwiftPMDependency,
                    targetName: targetName,
                    packageReference: nil,
                    manifestPath: manifestPath
                )
            default:
                break
            }
        }

        return WorkspaceModuleDependencyRef(
            kind: .unqualifiedSwiftPMDependency,
            targetName: targetName,
            packageReference: nil,
            manifestPath: manifestPath
        )
    }
}

private func parseTuistDependencyRefs(
    from expression: ExprSyntax?,
    manifestDirectoryURL: URL,
    manifestPath: String
) -> [WorkspaceModuleDependencyRef] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        guard let call = element.expression.as(FunctionCallExprSyntax.self) else {
            return nil
        }

        let calledName: String?
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            calledName = memberAccess.declName.baseName.text
        } else if let declReference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            calledName = declReference.baseName.text
        } else {
            calledName = nil
        }

        switch calledName {
        case "target":
            guard let targetName = labeledStringArgument("name", in: call.arguments) else {
                return nil
            }
            return WorkspaceModuleDependencyRef(
                kind: .localTarget,
                targetName: targetName,
                packageReference: nil,
                manifestPath: manifestPath
            )

        case "project":
            guard let targetName = labeledStringArgument("target", in: call.arguments) ?? labeledStringArgument("name", in: call.arguments),
                  let projectPath = labeledStringArgument("path", in: call.arguments) else {
                return nil
            }
            let resolvedManifestPath = NSString(
                string: manifestDirectoryURL
                    .appendingPathComponent(projectPath)
                    .appendingPathComponent("Project.swift")
                    .path(percentEncoded: false)
            ).standardizingPath
            return WorkspaceModuleDependencyRef(
                kind: .tuistProject,
                targetName: targetName,
                packageReference: nil,
                manifestPath: resolvedManifestPath
            )

        default:
            return nil
        }
    }
}

private func isTuistTargetCall(_ node: FunctionCallExprSyntax) -> Bool {
    if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "target" {
        return true
    }

    if let declReference = node.calledExpression.as(DeclReferenceExprSyntax.self),
       declReference.baseName.text == "Target" {
        return true
    }

    return false
}

private func globMatch(_ glob: String, filePath: String) -> Bool {
    let pattern = "^" + NSRegularExpression.escapedPattern(for: NSString(string: glob).standardizingPath)
        .replacingOccurrences(of: "\\*\\*", with: ".*")
        .replacingOccurrences(of: "\\*", with: "[^/]*") + "$"

    return filePath.range(of: pattern, options: .regularExpression) != nil
}
