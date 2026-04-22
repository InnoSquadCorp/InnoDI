import Foundation
import InnoDICore
import SwiftParser
import SwiftSyntax

package enum WorkspaceHierarchyBuildValidator {
    package static func validate(rootPath: String) throws -> ValidationIssueReport {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let moduleGraph = try ModuleGraphProvider.snapshot(rootPath: rootPath)
        let sourceFiles = discoverValidationSourceFiles(rootPath: rootPath)

        var collectors: [WorkspaceHierarchyFileCollector] = []
        for relativePath in sourceFiles {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let syntax = Parser.parse(source: source)
            let collector = WorkspaceHierarchyFileCollector(
                filePath: fileURL.path(percentEncoded: false),
                syntax: syntax
            )
            collector.walk(syntax)
            collectors.append(collector)
        }

        let containers = collectors
            .flatMap(\.containers)
            .map { container in
                let moduleID = moduleGraph.moduleRecord(forFilePath: container.filePath)?.moduleID
                    ?? unknownWorkspaceModuleID(forFilePath: container.filePath)
                return container.resolved(moduleID: moduleID)
            }
        let roots = containers.filter(\.isHierarchyRoot)
        guard !roots.isEmpty else {
            return ValidationIssueReport(issues: [])
        }

        let nominalTypes = collectors.flatMap(\.nominalTypes)
        let typeAliases = collectors.flatMap(\.typeAliases)
        let resolver = SemanticResolverIndex(
            nominalTypes: nominalTypes,
            topLevelTypeAliases: typeAliases
        )
        let typeCandidatePaths = Set(nominalTypes.map(\.path))
        let containersByID = Dictionary(uniqueKeysWithValues: containers.map { ($0.containerID, $0) })
        let containersByNominalPath = Dictionary(grouping: containers, by: \.nominalPath)
        let candidatePaths = Set(containersByNominalPath.keys)
        let modulesByContainerID = Dictionary(uniqueKeysWithValues: containers.map { record in
            (record.containerID, moduleGraph.moduleRecord(moduleID: record.moduleID).map(ResolvedHierarchyModuleContext.init))
        })

        var issues: [ValidationIssue] = []
        var pendingIssues: [PendingHierarchyIssue] = []
        let resolvedEdges: [ResolvedHierarchyEdge] = containers.flatMap { parent in
            parent.subContainers.compactMap { child -> ResolvedHierarchyEdge? in
                guard let childReference = child.childReference else {
                    pendingIssues.append(
                        PendingHierarchyIssue(
                            parentContainerID: parent.containerID,
                            issue: makeUnresolvedChildReferenceIssue(
                                parent: parent,
                                subContainer: child,
                                childReferenceDisplayPath: child.childReferenceDisplayPath,
                                resolutionState: SemanticResolutionState.excluded.rawValue,
                                excludedReason: "unsupported semantic reference shape"
                            )
                        )
                    )
                    return nil
                }

                let resolution = resolver.resolvePath(
                    for: childReference,
                    candidatePaths: candidatePaths
                )
                switch resolution.state {
                case .resolved:
                    break
                case .ambiguous:
                    pendingIssues.append(
                        PendingHierarchyIssue(
                            parentContainerID: parent.containerID,
                            issue: makeAmbiguousChildReferenceIssue(
                                parent: parent,
                                subContainer: child,
                                childNominalPath: child.childReferenceDisplayPath,
                                semanticCandidates: resolution.candidates,
                                aliasExpansionTrace: resolution.aliasExpansionTrace,
                                resolutionSource: "semantic-resolver"
                            )
                        )
                    )
                    return nil
                case .unresolved, .excluded:
                    pendingIssues.append(
                        PendingHierarchyIssue(
                            parentContainerID: parent.containerID,
                            issue: makeUnresolvedChildReferenceIssue(
                                parent: parent,
                                subContainer: child,
                                childReferenceDisplayPath: child.childReferenceDisplayPath,
                                resolutionState: resolution.state.rawValue,
                                aliasExpansionTrace: resolution.aliasExpansionTrace,
                                excludedReason: resolution.excludedReason
                            )
                        )
                    )
                    return nil
                }

                guard let childNominalPath = resolution.resolvedPath,
                      let childCandidates = containersByNominalPath[childNominalPath],
                      !childCandidates.isEmpty else {
                    pendingIssues.append(
                        PendingHierarchyIssue(
                            parentContainerID: parent.containerID,
                            issue: makeUnresolvedChildReferenceIssue(
                                parent: parent,
                                subContainer: child,
                                childReferenceDisplayPath: child.childReferenceDisplayPath,
                                resolutionState: SemanticResolutionState.unresolved.rawValue,
                                aliasExpansionTrace: resolution.aliasExpansionTrace
                            )
                        )
                    )
                    return nil
                }

                switch resolveHierarchyChildContainer(
                    parent: parent,
                    subContainer: child,
                    childNominalPath: childNominalPath,
                    childCandidates: childCandidates,
                    moduleGraph: moduleGraph
                ) {
                case .resolved(let childContainer):
                    return ResolvedHierarchyEdge(
                        parentContainerID: parent.containerID,
                        parentPath: parent.nominalPath,
                        parentLocation: parent.location,
                        parentModule: modulesByContainerID[parent.containerID]
                            ?? moduleGraph.moduleRecord(moduleID: parent.moduleID).map(ResolvedHierarchyModuleContext.init),
                        subContainer: child,
                        childContainerID: childContainer.containerID,
                        childPath: childContainer.nominalPath,
                        childLocation: childContainer.location,
                        childModule: modulesByContainerID[childContainer.containerID]
                            ?? moduleGraph.moduleRecord(moduleID: childContainer.moduleID).map(ResolvedHierarchyModuleContext.init)
                    )
                case .ambiguous(let issue):
                    pendingIssues.append(
                        PendingHierarchyIssue(
                            parentContainerID: parent.containerID,
                            issue: issue
                        )
                    )
                    return nil
                }
            }
        }

        let reachable = reachablePathsAndEdges(from: roots.map(\.containerID), edges: resolvedEdges)
        let reachablePaths = reachable.containerIDs
        let reachableEdges = reachable.edges

        issues.append(contentsOf: pendingIssues.compactMap { pending in
            reachablePaths.contains(pending.parentContainerID) ? pending.issue : nil
        })
        issues.append(
            contentsOf: validateResolvedEdges(
                reachableEdges,
                containersByID: containersByID,
                moduleGraph: moduleGraph,
                resolver: resolver,
                typeCandidatePaths: typeCandidatePaths
            )
        )
        issues.append(contentsOf: validateDuplicateParents(reachableEdges, containersByID: containersByID))
        issues.append(contentsOf: validateOrphanComponents(containers, reachableContainerIDs: reachablePaths))
        issues.append(contentsOf: detectHierarchyCycles(from: roots.map(\.containerID), edges: resolvedEdges))

        issues.sort {
            if $0.location.filePath != $1.location.filePath { return $0.location.filePath < $1.location.filePath }
            if $0.location.line != $1.location.line { return $0.location.line < $1.location.line }
            return $0.location.column < $1.location.column
        }

        return ValidationIssueReport(issues: issues)
    }
}

private struct PendingHierarchyIssue {
    let parentContainerID: String
    let issue: ValidationIssue
}

package struct WorkspaceModuleGraphSnapshot: Equatable, Sendable {
    package let modules: [WorkspaceModuleRecord]
    package let swiftPMProducts: [WorkspaceSwiftPMProductRecord]

    package func moduleRecord(forFilePath filePath: String) -> WorkspaceModuleRecord? {
        modules
            .filter { $0.matches(filePath: filePath) }
            .max { $0.matchSpecificity(for: filePath) < $1.matchSpecificity(for: filePath) }
    }

    package func moduleRecord(moduleID: String) -> WorkspaceModuleRecord? {
        modules.first(where: { $0.moduleID == moduleID })
    }

    package func declaresDependencyEdge(from parent: WorkspaceModuleRecord, to child: WorkspaceModuleRecord) -> Bool? {
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
            let moduleIDs = modules.filter {
                $0.buildSystem == "tuist"
                    && $0.manifestPath == manifestPath
                    && $0.name == dependencyRef.targetName
            }.map(\.moduleID)
            return .resolved(Set(moduleIDs))
        }
    }

    private func localTargetModuleIDs(
        for dependencyRef: WorkspaceModuleDependencyRef,
        parent: WorkspaceModuleRecord
    ) -> Set<String> {
        let manifestPath = dependencyRef.manifestPath ?? parent.manifestPath
        let moduleIDs = modules.filter {
            $0.buildSystem == parent.buildSystem
                && $0.manifestPath == manifestPath
                && $0.name == dependencyRef.targetName
        }.map(\.moduleID)
        return Set(moduleIDs)
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

        let matchingProducts = swiftPMProducts.filter {
            candidateManifestPaths.contains($0.manifestPath) && $0.productName == productName
        }
        if matchingProducts.count > 1 {
            return .ambiguous
        }
        guard let product = matchingProducts.first else {
            return .resolved([])
        }

        return .resolved(Set(product.exportedModuleIDs))
    }
}

private enum DependencyResolutionResult: Equatable {
    case resolved(Set<String>)
    case ambiguous
    case unknown
}

package struct WorkspaceModuleRecord: Equatable, Sendable {
    package let moduleID: String
    package let name: String
    package let manifestPath: String
    package let packageDisplayName: String?
    package let packageIdentity: String?
    package let sourcePatterns: [String]
    package let dependencyRefs: [WorkspaceModuleDependencyRef]
    package let swiftPMPackageDependencies: [WorkspaceSwiftPMPackageDependencyRecord]
    package let buildSystem: String

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

package struct WorkspaceSwiftPMPackageDependencyRecord: Equatable, Sendable {
    package let referenceNames: [String]
    package let resolvedManifestPath: String?

    fileprivate func matches(reference: String) -> Bool {
        let normalizedReference = normalizePackageIdentity(reference)
        return referenceNames.contains(normalizedReference)
    }
}

package struct WorkspaceSwiftPMProductRecord: Equatable, Sendable {
    package let productID: String
    package let productName: String
    package let manifestPath: String
    package let packageDisplayName: String?
    package let packageIdentity: String
    package let exportedModuleIDs: [String]
}

package struct WorkspaceModuleDependencyRef: Equatable, Sendable {
    package enum Kind: String, Sendable {
        case localTarget
        case unqualifiedSwiftPMDependency
        case swiftPMProduct
        case tuistProject
    }

    package let kind: Kind
    package let targetName: String
    package let packageReference: String?
    package let manifestPath: String?
}

package enum ModuleGraphProvider {
    package static func snapshot(rootPath: String) throws -> WorkspaceModuleGraphSnapshot {
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
        if workspaceShouldSkipValidationPath(item) {
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

private struct ResolvedHierarchyModuleContext: Equatable {
    let moduleID: String
    let displayName: String
    let manifestPath: String

    init(record: WorkspaceModuleRecord) {
        self.moduleID = record.moduleID
        self.displayName = record.name
        self.manifestPath = record.manifestPath
    }
}

private struct ResolvedHierarchyEdge: Equatable {
    let parentContainerID: String
    let parentPath: String
    let parentLocation: ValidationIssueLocation
    let parentModule: ResolvedHierarchyModuleContext?
    let subContainer: WorkspaceHierarchySubContainerRecord
    let childContainerID: String
    let childPath: String
    let childLocation: ValidationIssueLocation
    let childModule: ResolvedHierarchyModuleContext?
}

private struct ReachableHierarchy {
    let containerIDs: Set<String>
    let edges: [ResolvedHierarchyEdge]
}

private func reachablePathsAndEdges(
    from rootContainerIDs: [String],
    edges: [ResolvedHierarchyEdge]
) -> ReachableHierarchy {
    let groupedEdges = Dictionary(grouping: edges, by: \.parentContainerID)
    var visited: Set<String> = []
    var reachableEdges: [ResolvedHierarchyEdge] = []
    var queue = rootContainerIDs

    while !queue.isEmpty {
        let current = queue.removeFirst()
        if !visited.insert(current).inserted {
            continue
        }

        for edge in groupedEdges[current] ?? [] {
            reachableEdges.append(edge)
            queue.append(edge.childContainerID)
        }
    }

    return ReachableHierarchy(containerIDs: visited, edges: reachableEdges)
}

private func validateResolvedEdges(
    _ edges: [ResolvedHierarchyEdge],
    containersByID: [String: WorkspaceHierarchyContainerRecord],
    moduleGraph: WorkspaceModuleGraphSnapshot,
    resolver: SemanticResolverIndex,
    typeCandidatePaths: Set<String>
) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    for edge in edges {
        guard let child = containersByID[edge.childContainerID] else {
            continue
        }

        let crossesModuleBoundary = edge.parentModule != nil
            && edge.childModule != nil
            && edge.parentModule?.moduleID != edge.childModule?.moduleID
        let moduleDisambiguationNotes = hierarchyModuleDisambiguationNotes(for: edge)

        if crossesModuleBoundary, child.isComponent == false {
            issues.append(
                ValidationIssue(
                    code: "hierarchy.child-not-component",
                    severity: .error,
                    message: "@SubContainer '\(edge.subContainer.memberName)' crosses from module '\(edge.parentModule?.displayName ?? "<unknown>")' to '\(edge.childModule?.displayName ?? "<unknown>")', but '\(child.displayName)' is not marked with @DIComponent.",
                    location: edge.subContainer.location,
                    notes: [
                        ValidationIssueNote(
                            message: "child container '\(child.path)' is declared here.",
                            location: child.location
                        )
                    ] + moduleDisambiguationNotes,
                    remediation: "Annotate '\(child.displayName)' with @DIComponent, or keep the child in the same module as its parent.",
                    metadata: [
                        "parentContainerPath": edge.parentPath,
                        "childContainerPath": edge.childPath
                    ]
                )
            )
        }

        if crossesModuleBoundary,
           let parentModule = edge.parentModule,
           let childModule = edge.childModule,
           let parentRecord = moduleGraph.moduleRecord(moduleID: parentModule.moduleID),
           let childRecord = moduleGraph.moduleRecord(moduleID: childModule.moduleID),
           moduleGraph.declaresDependencyEdge(from: parentRecord, to: childRecord) == false {
            issues.append(
                ValidationIssue(
                    code: "hierarchy.module-edge-missing",
                    severity: .error,
                    message: "Module '\(parentModule.displayName)' mounts child container '\(child.displayName)' from module '\(childModule.displayName)' without declaring a module dependency edge.",
                    location: edge.subContainer.location,
                    notes: [
                        ValidationIssueNote(
                            message: "child container '\(child.path)' is declared here.",
                            location: child.location
                        )
                    ] + moduleDisambiguationNotes,
                    remediation: "Add '\(childModule.displayName)' to module '\(parentModule.displayName)' dependencies, or remove the cross-module @SubContainer edge.",
                    metadata: [
                        "parentModule": parentModule.displayName,
                        "childModule": childModule.displayName,
                        "parentModuleID": parentModule.moduleID,
                        "childModuleID": childModule.moduleID
                    ]
                )
            )
        }

        if crossesModuleBoundary, child.isComponent,
           let parent = containersByID[edge.parentContainerID] {
            issues.append(
                contentsOf: validateDependencySatisfaction(
                    parent: parent,
                    edge: edge,
                    child: child,
                    resolver: resolver,
                    typeCandidatePaths: typeCandidatePaths
                )
            )
        }
    }

    return issues
}

private func hierarchyModuleDisambiguationNotes(for edge: ResolvedHierarchyEdge) -> [ValidationIssueNote] {
    guard let parentModule = edge.parentModule,
          let childModule = edge.childModule,
          parentModule.moduleID != childModule.moduleID,
          parentModule.displayName == childModule.displayName else {
        return []
    }

    return [
        ValidationIssueNote(
            message: "parent module '\(parentModule.displayName)' comes from '\(parentModule.manifestPath)'.",
            location: edge.parentLocation
        ),
        ValidationIssueNote(
            message: "child module '\(childModule.displayName)' comes from '\(childModule.manifestPath)'.",
            location: edge.childLocation
        ),
    ]
}

private enum HierarchyChildResolution {
    case resolved(WorkspaceHierarchyContainerRecord)
    case ambiguous(ValidationIssue)
}

private func resolveHierarchyChildContainer(
    parent: WorkspaceHierarchyContainerRecord,
    subContainer: WorkspaceHierarchySubContainerRecord,
    childNominalPath: String,
    childCandidates: [WorkspaceHierarchyContainerRecord],
    moduleGraph: WorkspaceModuleGraphSnapshot
) -> HierarchyChildResolution {
    if childCandidates.count == 1, let child = childCandidates.first {
        return .resolved(child)
    }

    let sameModuleCandidates = childCandidates.filter { $0.moduleID == parent.moduleID }
    if sameModuleCandidates.count == 1, let child = sameModuleCandidates.first {
        return .resolved(child)
    }
    if sameModuleCandidates.count > 1 {
        return .ambiguous(
            makeAmbiguousChildReferenceIssue(
                parent: parent,
                subContainer: subContainer,
                childNominalPath: childNominalPath,
                candidates: sameModuleCandidates
            )
        )
    }

    if let parentModule = moduleGraph.moduleRecord(moduleID: parent.moduleID) {
        let dependencyCandidates = childCandidates.filter { candidate in
            guard let childModule = moduleGraph.moduleRecord(moduleID: candidate.moduleID) else {
                return false
            }
            return moduleGraph.declaresDependencyEdge(from: parentModule, to: childModule) == true
        }
        if dependencyCandidates.count == 1, let child = dependencyCandidates.first {
            return .resolved(child)
        }
        if dependencyCandidates.count > 1 {
            return .ambiguous(
                makeAmbiguousChildReferenceIssue(
                    parent: parent,
                    subContainer: subContainer,
                    childNominalPath: childNominalPath,
                    candidates: dependencyCandidates
                )
            )
        }
    }

    return .ambiguous(
        makeAmbiguousChildReferenceIssue(
            parent: parent,
            subContainer: subContainer,
            childNominalPath: childNominalPath,
            candidates: childCandidates
        )
    )
}

private func makeAmbiguousChildReferenceIssue(
    parent: WorkspaceHierarchyContainerRecord,
    subContainer: WorkspaceHierarchySubContainerRecord,
    childNominalPath: String,
    candidates: [WorkspaceHierarchyContainerRecord] = [],
    semanticCandidates: [String] = [],
    aliasExpansionTrace: [String] = [],
    resolutionSource: String = "container-disambiguation"
) -> ValidationIssue {
    var notes = candidates.sorted { lhs, rhs in
        if lhs.nominalPath != rhs.nominalPath {
            return lhs.nominalPath < rhs.nominalPath
        }
        return lhs.filePath < rhs.filePath
    }.map { candidate in
        ValidationIssueNote(
            message: "candidate '\(candidate.nominalPath)' is declared in module '\(candidate.moduleID)' at '\(candidate.filePath)'.",
            location: candidate.location
        )
    }
    notes.append(contentsOf: semanticCandidates.sorted().map { candidate in
        ValidationIssueNote(
            message: "semantic candidate '\(candidate)' matches child reference '\(childNominalPath)'.",
            location: subContainer.location
        )
    })
    if !aliasExpansionTrace.isEmpty {
        notes.append(
            ValidationIssueNote(
                message: "alias expansion trace: \(aliasExpansionTrace.joined(separator: " -> ")).",
                location: subContainer.location
            )
        )
    }

    return ValidationIssue(
        code: "hierarchy.ambiguous-child-reference",
        severity: .error,
        message: "@SubContainer '\(subContainer.memberName)' in '\(parent.nominalPath)' resolves to multiple child containers named '\(childNominalPath)'.",
        location: subContainer.location,
        notes: notes,
        remediation: "Make the child reference unique within the workspace, move the intended child into the same module, or reduce matching candidates to a single dependency edge.",
        metadata: [
            "parentContainerPath": parent.nominalPath,
            "childNominalPath": childNominalPath,
            "resolutionSource": resolutionSource
        ]
    )
}

private func makeUnresolvedChildReferenceIssue(
    parent: WorkspaceHierarchyContainerRecord,
    subContainer: WorkspaceHierarchySubContainerRecord,
    childReferenceDisplayPath: String,
    resolutionState: String,
    aliasExpansionTrace: [String] = [],
    excludedReason: String? = nil
) -> ValidationIssue {
    var notes: [ValidationIssueNote] = [
        ValidationIssueNote(
            message: "written child reference: '\(childReferenceDisplayPath)'.",
            location: subContainer.location
        )
    ]
    if !aliasExpansionTrace.isEmpty {
        notes.append(
            ValidationIssueNote(
                message: "alias expansion trace: \(aliasExpansionTrace.joined(separator: " -> ")).",
                location: subContainer.location
            )
        )
    }
    if let excludedReason {
        notes.append(
            ValidationIssueNote(
                message: "resolution excluded this reference: \(excludedReason).",
                location: subContainer.location
            )
        )
    }

    return ValidationIssue(
        code: "hierarchy.unresolved-child-reference",
        severity: .error,
        message: "@SubContainer '\(subContainer.memberName)' in '\(parent.nominalPath)' does not resolve to a known child container for '\(childReferenceDisplayPath)'.",
        location: subContainer.location,
        notes: notes,
        remediation: "Declare a matching @DIContainer child type, qualify the child reference explicitly, or remove the invalid @SubContainer edge.",
        metadata: [
            "parentContainerPath": parent.nominalPath,
            "childReference": childReferenceDisplayPath,
            "resolutionState": resolutionState
        ]
    )
}

private func validateDependencySatisfaction(
    parent: WorkspaceHierarchyContainerRecord,
    edge: ResolvedHierarchyEdge,
    child: WorkspaceHierarchyContainerRecord,
    resolver: SemanticResolverIndex,
    typeCandidatePaths: Set<String>
) -> [ValidationIssue] {
    let requiredInputs = child.inputMembers
    let resolvedMappings = resolvedDependencyMappings(
        parent: parent,
        child: child,
        edge: edge
    )

    var issues = resolvedMappings.issues
    for (childInputName, childType) in requiredInputs.sorted(by: { $0.key < $1.key }) {
        guard let mapping = resolvedMappings.mappings[childInputName] else {
            issues.append(
                ValidationIssue(
                    code: "hierarchy.unsatisfied-dependency",
                    severity: .error,
                    message: "Parent container '\(parent.displayName)' cannot satisfy component input '\(childInputName)' required by '\(child.displayName)'.",
                    location: edge.subContainer.location,
                    notes: [
                        ValidationIssueNote(
                            message: "child component '\(child.path)' declares '\(childInputName): \(childType.rawTypeSpelling)'.",
                            location: child.location
                        )
                    ],
                    remediation: "Add a parent @Provide member named '\(childInputName)', or use bindings: to map that child input explicitly.",
                    metadata: [
                        "parentContainerPath": parent.path,
                        "childContainerPath": child.path,
                        "childInputName": childInputName
                    ]
                )
            )
            continue
        }

        guard let parentType = parent.providedMembers[mapping.parentName],
              hierarchyMemberTypesMatch(
                parentType,
                childType,
                resolver: resolver,
                typeCandidatePaths: typeCandidatePaths
              ) else {
            let parentType = parent.providedMembers[mapping.parentName]?.rawTypeSpelling ?? "<missing>"
            issues.append(
                ValidationIssue(
                    code: "hierarchy.unsatisfied-dependency",
                    severity: .error,
                    message: "Parent container '\(parent.displayName)' maps child input '\(childInputName)' to '\(mapping.parentName)', but the types do not match (\(parentType) vs \(childType.rawTypeSpelling)).",
                    location: mapping.location,
                    notes: [
                        ValidationIssueNote(
                            message: "child component '\(child.path)' declares '\(childInputName): \(childType.rawTypeSpelling)'.",
                            location: child.location
                        )
                    ],
                    remediation: "Change the parent member type, or remap '\(childInputName)' to a parent member whose type matches exactly.",
                    metadata: [
                        "parentContainerPath": parent.path,
                        "childContainerPath": child.path,
                        "childInputName": childInputName,
                        "parentMemberName": mapping.parentName
                    ]
                )
            )
            continue
        }
    }

    return issues
}

private struct ResolvedDependencyMapping {
    let parentName: String
    let location: ValidationIssueLocation
}

private struct ResolvedDependencyMappingsResult {
    let mappings: [String: ResolvedDependencyMapping]
    let issues: [ValidationIssue]
}

private func resolvedDependencyMappings(
    parent: WorkspaceHierarchyContainerRecord,
    child: WorkspaceHierarchyContainerRecord,
    edge: ResolvedHierarchyEdge
) -> ResolvedDependencyMappingsResult {
    if !edge.subContainer.bindings.isEmpty {
        return resolvedDependencyMappings(
            parent: parent,
            child: child,
            edge: edge,
            kind: .binding,
            candidates: edge.subContainer.bindings.map {
                (
                    key: $0.childInputName,
                    mapping: ResolvedDependencyMapping(
                        parentName: $0.parentMemberName,
                        location: $0.parentLocation
                    ),
                    location: $0.childLocation
                )
            }
        )
    }

    if !edge.subContainer.withDependencies.isEmpty {
        return resolvedDependencyMappings(
            parent: parent,
            child: child,
            edge: edge,
            kind: .withDependency,
            candidates: edge.subContainer.withDependencies.map {
                (
                    key: $0.name,
                    mapping: ResolvedDependencyMapping(parentName: $0.name, location: $0.location),
                    location: $0.location
                )
            }
        )
    }

    return ResolvedDependencyMappingsResult(
        mappings: Dictionary(uniqueKeysWithValues: child.inputMembers.keys.compactMap { inputName in
            guard parent.providedMembers[inputName] != nil else {
                return nil
            }
            return (
                inputName,
                ResolvedDependencyMapping(parentName: inputName, location: edge.subContainer.location)
            )
        }),
        issues: []
    )
}

private enum ResolvedDependencyMappingKind {
    case binding
    case withDependency

    var duplicateIssueCode: String {
        switch self {
        case .binding:
            "hierarchy.duplicate-binding-mapping"
        case .withDependency:
            "hierarchy.duplicate-with-dependency"
        }
    }

    func duplicateMessage(
        edge: ResolvedHierarchyEdge,
        child: WorkspaceHierarchyContainerRecord,
        dependencyName: String
    ) -> String {
        switch self {
        case .binding:
            return "@SubContainer '\(edge.subContainer.memberName)' in '\(edge.parentPath)' maps child input '\(dependencyName)' more than once in bindings: for '\(child.displayName)'."
        case .withDependency:
            return "@SubContainer '\(edge.subContainer.memberName)' in '\(edge.parentPath)' lists dependency '\(dependencyName)' more than once in with: for '\(child.displayName)'."
        }
    }

    var remediation: String {
        switch self {
        case .binding:
            "Keep at most one bindings: entry per child input."
        case .withDependency:
            "Keep each with: dependency name listed at most once."
        }
    }
}

private func resolvedDependencyMappings(
    parent: WorkspaceHierarchyContainerRecord,
    child: WorkspaceHierarchyContainerRecord,
    edge: ResolvedHierarchyEdge,
    kind: ResolvedDependencyMappingKind,
    candidates: [(key: String, mapping: ResolvedDependencyMapping, location: ValidationIssueLocation)]
) -> ResolvedDependencyMappingsResult {
    var mappings: [String: ResolvedDependencyMapping] = [:]
    var firstLocations: [String: ValidationIssueLocation] = [:]
    var issues: [ValidationIssue] = []

    for candidate in candidates {
        if mappings[candidate.key] == nil {
            mappings[candidate.key] = candidate.mapping
            firstLocations[candidate.key] = candidate.location
            continue
        }

        let firstLocation = firstLocations[candidate.key]
        issues.append(
            ValidationIssue(
                code: kind.duplicateIssueCode,
                severity: .error,
                message: kind.duplicateMessage(edge: edge, child: child, dependencyName: candidate.key),
                location: candidate.location,
                notes: firstLocation.map {
                    [ValidationIssueNote(message: "first mapping for '\(candidate.key)' appears here.", location: $0)]
                } ?? [],
                remediation: kind.remediation,
                metadata: [
                    "parentContainerPath": parent.path,
                    "childContainerPath": child.path,
                    "childInputName": candidate.key
                ]
            )
        )
    }

    return ResolvedDependencyMappingsResult(mappings: mappings, issues: issues)
}

private func hierarchyMemberTypesMatch(
    _ parent: WorkspaceHierarchyMemberRecord,
    _ child: WorkspaceHierarchyMemberRecord,
    resolver: SemanticResolverIndex,
    typeCandidatePaths: Set<String>
) -> Bool {
    if let parentPath = resolvedHierarchyMemberTypePath(
        parent,
        resolver: resolver,
        typeCandidatePaths: typeCandidatePaths
    ),
       let childPath = resolvedHierarchyMemberTypePath(
        child,
        resolver: resolver,
        typeCandidatePaths: typeCandidatePaths
       ) {
        return parentPath == childPath
    }

    return parent.rawTypeSpelling == child.rawTypeSpelling
}

private func resolvedHierarchyMemberTypePath(
    _ member: WorkspaceHierarchyMemberRecord,
    resolver: SemanticResolverIndex,
    typeCandidatePaths: Set<String>
) -> String? {
    guard let reference = member.semanticTypeReference else {
        return nil
    }

    let resolution = resolver.resolvePath(for: reference, candidatePaths: typeCandidatePaths)
    guard resolution.state == .resolved else {
        return nil
    }
    return resolution.resolvedPath
}

private func validateDuplicateParents(
    _ edges: [ResolvedHierarchyEdge],
    containersByID: [String: WorkspaceHierarchyContainerRecord]
) -> [ValidationIssue] {
    let grouped = Dictionary(grouping: edges.filter {
        containersByID[$0.childContainerID]?.isComponent == true
    }, by: \.childContainerID)

    var issues: [ValidationIssue] = []
    for (childContainerID, childEdges) in grouped where childEdges.count > 1 {
        guard let firstEdge = childEdges.first,
              let child = containersByID[childContainerID] else {
            continue
        }

        for edge in childEdges.dropFirst() {
            issues.append(
                ValidationIssue(
                    code: "hierarchy.duplicate-parent",
                    severity: .error,
                    message: "Component '\(child.displayName)' is mounted from multiple parents ('\(firstEdge.parentPath)' and '\(edge.parentPath)').",
                    location: edge.subContainer.location,
                    notes: [
                        ValidationIssueNote(
                            message: "first parent mounts '\(child.displayName)' here.",
                            location: firstEdge.subContainer.location
                        )
                    ],
                    remediation: "Keep each @DIComponent under a single parent hierarchy edge.",
                    metadata: [
                        "childContainerPath": child.nominalPath,
                        "firstParentPath": firstEdge.parentPath,
                        "secondParentPath": edge.parentPath
                    ]
                )
            )
        }
    }

    return issues
}

private func validateOrphanComponents(
    _ containers: [WorkspaceHierarchyContainerRecord],
    reachableContainerIDs: Set<String>
) -> [ValidationIssue] {
    containers
        .filter { $0.isComponent && !reachableContainerIDs.contains($0.containerID) }
        .map { component in
            ValidationIssue(
                code: "hierarchy.orphan-component",
                severity: .error,
                message: "Component '\(component.displayName)' is not reachable from any @DIHierarchyRoot container.",
                location: component.location,
                remediation: "Mount '\(component.displayName)' from a rooted parent container, or remove @DIComponent if this type is not part of the strict hierarchy.",
                metadata: [
                    "childContainerPath": component.nominalPath
                ]
            )
        }
}

private func detectHierarchyCycles(
    from rootContainerIDs: [String],
    edges: [ResolvedHierarchyEdge]
) -> [ValidationIssue] {
    let adjacency = Dictionary(grouping: edges, by: \.parentContainerID)
    var visiting: Set<String> = []
    var visited: Set<String> = []
    var nodeStack: [String] = []
    var pathStack: [ResolvedHierarchyEdge] = []
    var issues: [ValidationIssue] = []
    var seenCycleKeys: Set<String> = []

    func recordCycle(endingWith edge: ResolvedHierarchyEdge, cycleStartIndex: Int) {
        let cycleEdges = Array(pathStack.dropFirst(cycleStartIndex)) + [edge]
        let cycleKey = cycleEdges.map { "\($0.parentContainerID)->\($0.childContainerID)" }.joined(separator: "|")
        guard seenCycleKeys.insert(cycleKey).inserted else {
            return
        }

        issues.append(
            ValidationIssue(
                code: "hierarchy.component-cycle",
                severity: .error,
                message: "Strict hierarchy cycle detected: \(cycleEdges.map(\.parentPath).joined(separator: " -> ")) -> \(edge.childPath).",
                location: edge.subContainer.location,
                remediation: "Break the @SubContainer ownership cycle so the rooted component hierarchy remains acyclic.",
                metadata: [
                    "cycle": cycleKey
                ]
            )
        )
    }

    func dfs(_ current: String) {
        if visited.contains(current) {
            return
        }
        visiting.insert(current)
        nodeStack.append(current)

        for edge in adjacency[current] ?? [] {
            if let cycleStartIndex = nodeStack.firstIndex(of: edge.childContainerID) {
                recordCycle(endingWith: edge, cycleStartIndex: cycleStartIndex)
                continue
            }

            if visiting.contains(edge.childContainerID) {
                continue
            }

            pathStack.append(edge)
            dfs(edge.childContainerID)
            _ = pathStack.popLast()
        }

        _ = nodeStack.popLast()
        visiting.remove(current)
        visited.insert(current)
    }

    for root in rootContainerIDs {
        dfs(root)
    }

    return issues
}

private struct WorkspaceHierarchyMemberRecord: Equatable {
    let rawTypeSpelling: String
    let semanticTypeReference: SemanticTypeReference?
}

private func makeHierarchyMemberRecord(from type: TypeSyntax?) -> WorkspaceHierarchyMemberRecord {
    WorkspaceHierarchyMemberRecord(
        rawTypeSpelling: type?.trimmedDescription ?? "<unknown>",
        semanticTypeReference: type.flatMap(normalizedSemanticTypeReference)
    )
}

private final class WorkspaceHierarchyFileCollector: SyntaxVisitor {
    private let filePath: String
    private let locationConverter: SourceLocationConverter
    private var declarationStack: [String] = []
    private var containerContextStack: [String?] = []
    private var containerBuilders: [String: WorkspaceHierarchyContainerBuilder] = [:]

    private(set) var nominalTypes: [SemanticNominalTypeRecord] = []
    private(set) var typeAliases: [SemanticTypeAliasRecord] = []

    var containers: [WorkspaceHierarchyContainerRecord] {
        containerBuilders.values
            .map { builder in
                WorkspaceHierarchyContainerRecord(
                    containerID: "",
                    nominalPath: builder.path,
                    moduleID: "",
                    displayName: builder.path.split(separator: ".").last.map(String.init) ?? builder.path,
                    filePath: builder.filePath,
                    location: builder.location,
                    isComponent: builder.isComponent,
                    isHierarchyRoot: builder.isHierarchyRoot,
                    inputMembers: builder.inputMembers,
                    providedMembers: builder.providedMembers,
                    subContainers: builder.subContainers
                )
            }
            .sorted { $0.nominalPath < $1.nominalPath }
    }

    init(filePath: String, syntax: SourceFileSyntax) {
        self.filePath = filePath
        self.locationConverter = SourceLocationConverter(fileName: filePath, tree: syntax)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let components = declarationStack + [node.name.text]
        let path = components.joined(separator: ".")

        if let targetReference = normalizedSemanticTypeReference(node.initializer.value) {
            typeAliases.append(
                SemanticTypeAliasRecord(
                    path: path,
                    components: components,
                    target: targetReference
                )
            )
        }

        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let currentContainerPath = containerContextStack.last ?? nil,
              node.parent?.is(MemberBlockItemSyntax.self) == true,
              let binding = hierarchyValidatedBinding(node) else {
            return .skipChildren
        }

        if let provideAttribute = findAttribute(named: "Provide", in: node.attributes) {
            let provideArguments = parseProvideArguments(provideAttribute)
            containerBuilders[currentContainerPath, default: WorkspaceHierarchyContainerBuilder(
                path: currentContainerPath,
                filePath: filePath,
                location: sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
            )]
            .providedMembers[binding.name] = makeHierarchyMemberRecord(from: binding.type)

            if provideArguments.scope == .input {
                containerBuilders[currentContainerPath]?.inputMembers[binding.name] = makeHierarchyMemberRecord(from: binding.type)
            }
        }

        if let subContainerAttribute = findAttribute(named: "SubContainer", in: node.attributes),
           let childType = binding.type {
            var builder = containerBuilders[currentContainerPath, default: WorkspaceHierarchyContainerBuilder(
                path: currentContainerPath,
                filePath: filePath,
                location: sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
            )]
            builder.subContainers.append(
                WorkspaceHierarchySubContainerRecord(
                    memberName: binding.name,
                    location: sourceLocation(for: subContainerAttribute.positionAfterSkippingLeadingTrivia),
                    childReferenceDisplayPath: childType.trimmedDescription,
                    childReference: normalizedSemanticTypeReference(childType),
                    withDependencies: extractWithDependencies(from: subContainerAttribute),
                    bindings: extractSubContainerBindings(from: subContainerAttribute)
                )
            )
            containerBuilders[currentContainerPath] = builder
        }

        return .skipChildren
    }

    private func visitNominal(
        node: Syntax,
        name: String,
        attributes: AttributeListSyntax?
    ) -> SyntaxVisitorContinueKind {
        declarationStack.append(name)
        let declarationPath = declarationStack.joined(separator: ".")
        nominalTypes.append(
            SemanticNominalTypeRecord(path: declarationPath, components: declarationStack)
        )

        let location = sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
        if containsHierarchyAttribute("DIContainer", in: attributes) {
            containerBuilders[declarationPath] = WorkspaceHierarchyContainerBuilder(
                path: declarationPath,
                filePath: filePath,
                location: location,
                isComponent: containsHierarchyAttribute("DIComponent", in: attributes),
                isHierarchyRoot: containsHierarchyAttribute("DIHierarchyRoot", in: attributes)
            )
            containerContextStack.append(declarationPath)
        } else {
            containerContextStack.append(nil)
        }

        return .visitChildren
    }

    private func visitPostNominal() {
        if !declarationStack.isEmpty {
            declarationStack.removeLast()
        }
        if !containerContextStack.isEmpty {
            containerContextStack.removeLast()
        }
    }

    private func sourceLocation(for position: AbsolutePosition) -> ValidationIssueLocation {
        let location = locationConverter.location(for: position)
        return ValidationIssueLocation(
            filePath: filePath,
            line: location.line,
            column: location.column
        )
    }
}

private struct WorkspaceHierarchyContainerRecord: Equatable {
    let containerID: String
    let nominalPath: String
    let moduleID: String
    let displayName: String
    let filePath: String
    let location: ValidationIssueLocation
    let isComponent: Bool
    let isHierarchyRoot: Bool
    let inputMembers: [String: WorkspaceHierarchyMemberRecord]
    let providedMembers: [String: WorkspaceHierarchyMemberRecord]
    let subContainers: [WorkspaceHierarchySubContainerRecord]

    var path: String { nominalPath }

    func resolved(moduleID: String) -> WorkspaceHierarchyContainerRecord {
        WorkspaceHierarchyContainerRecord(
            containerID: workspaceContainerID(moduleID: moduleID, nominalPath: nominalPath, filePath: filePath),
            nominalPath: nominalPath,
            moduleID: moduleID,
            displayName: displayName,
            filePath: filePath,
            location: location,
            isComponent: isComponent,
            isHierarchyRoot: isHierarchyRoot,
            inputMembers: inputMembers,
            providedMembers: providedMembers,
            subContainers: subContainers
        )
    }
}

private struct WorkspaceHierarchyContainerBuilder {
    let path: String
    let filePath: String
    let location: ValidationIssueLocation
    var isComponent: Bool = false
    var isHierarchyRoot: Bool = false
    var inputMembers: [String: WorkspaceHierarchyMemberRecord] = [:]
    var providedMembers: [String: WorkspaceHierarchyMemberRecord] = [:]
    var subContainers: [WorkspaceHierarchySubContainerRecord] = []
}

private struct WorkspaceHierarchySubContainerRecord: Equatable {
    let memberName: String
    let location: ValidationIssueLocation
    let childReferenceDisplayPath: String
    let childReference: SemanticTypeReference?
    let withDependencies: [HierarchyWithDependencyRecord]
    let bindings: [HierarchyBindingRecord]
}

private struct HierarchyWithDependencyRecord: Equatable {
    let name: String
    let location: ValidationIssueLocation
}

private struct HierarchyBindingRecord: Equatable {
    let childInputName: String
    let parentMemberName: String
    let childLocation: ValidationIssueLocation
    let parentLocation: ValidationIssueLocation
}

private struct HierarchyValidatedBinding {
    let name: String
    let type: TypeSyntax?
}

private func hierarchyValidatedBinding(_ varDecl: VariableDeclSyntax) -> HierarchyValidatedBinding? {
    guard varDecl.bindings.count == 1,
          let binding = varDecl.bindings.first,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
        return nil
    }

    return HierarchyValidatedBinding(
        name: identifier.identifier.text,
        type: binding.typeAnnotation?.type
    )
}

private func containsHierarchyAttribute(_ name: String, in attributes: AttributeListSyntax?) -> Bool {
    attributes?.contains(where: { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return hierarchyAttributeBaseName(attribute.attributeName) == name
    }) == true
}

private func hierarchyAttributeBaseName(_ type: TypeSyntax) -> String? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text
    }
    if let member = type.as(MemberTypeSyntax.self) {
        return member.name.text
    }
    return nil
}

private func extractWithDependencies(from attribute: AttributeSyntax) -> [HierarchyWithDependencyRecord] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "with" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return []
        }

        return arrayExpr.elements.compactMap { element in
            guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
                  let property = keyPath.components.last?
                    .component.as(KeyPathPropertyComponentSyntax.self)?
                    .declName.baseName.text else {
                return nil
            }

            return HierarchyWithDependencyRecord(
                name: property,
                location: ValidationIssueLocation(
                    filePath: "<macro>",
                    line: 0,
                    column: 0
                )
            )
        }
    }

    return []
}

private func extractSubContainerBindings(from attribute: AttributeSyntax) -> [HierarchyBindingRecord] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "bindings" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return []
        }

        return arrayExpr.elements.compactMap { element in
            guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
                return nil
            }

            var childName: String?
            var parentName: String?

            for tupleElement in tupleExpr.elements {
                guard let label = tupleElement.label?.text,
                      let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self),
                      let property = keyPath.components.last?
                        .component.as(KeyPathPropertyComponentSyntax.self)?
                        .declName.baseName.text else {
                    continue
                }

                switch label {
                case "child":
                    childName = property
                case "parent":
                    parentName = property
                default:
                    continue
                }
            }

            guard let childName, let parentName else {
                return nil
            }

            return HierarchyBindingRecord(
                childInputName: childName,
                parentMemberName: parentName,
                childLocation: ValidationIssueLocation(filePath: "<macro>", line: 0, column: 0),
                parentLocation: ValidationIssueLocation(filePath: "<macro>", line: 0, column: 0)
            )
        }
    }

    return []
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

private func workspaceContainerID(moduleID: String, nominalPath: String, filePath: String) -> String {
    "\(moduleID)|\(nominalPath)|\(NSString(string: filePath).standardizingPath)"
}

private func unknownWorkspaceModuleID(forFilePath filePath: String) -> String {
    "unknown|\(NSString(string: filePath).standardizingPath)"
}

private func swiftPMProductID(manifestPath: String, productName: String) -> String {
    "\(manifestPath)|product|\(productName)"
}

private func normalizePackageIdentity(_ raw: String) -> String {
    raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: ".git", with: "")
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

private func workspaceShouldSkipValidationPath(_ path: String) -> Bool {
    for token in validationSkipTokens where path.contains(token) {
        return true
    }
    return false
}
