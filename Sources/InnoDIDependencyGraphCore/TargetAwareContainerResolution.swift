import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftSyntax

struct TargetAwareImportEntry: Hashable {
    let moduleName: String
    let declarationPath: [String]?
    let isExported: Bool
    let isConditional: Bool
}

struct TargetAwareSourceImports: Hashable {
    static let empty = Self(entries: [])

    let entries: [TargetAwareImportEntry]

    init(entries: [TargetAwareImportEntry]) {
        self.entries = Array(Set(entries)).sorted {
            if $0.moduleName != $1.moduleName {
                return $0.moduleName < $1.moduleName
            }
            let lhsPath = $0.declarationPath?.joined(separator: ".") ?? ""
            let rhsPath = $1.declarationPath?.joined(separator: ".") ?? ""
            if lhsPath != rhsPath {
                return lhsPath < rhsPath
            }
            if $0.isExported != $1.isExported {
                return $0.isExported && !$1.isExported
            }
            return !$0.isConditional && $1.isConditional
        }
    }

    var exportedOnly: Self {
        Self(entries: entries.filter(\.isExported))
    }

    func merging(_ other: Self) -> Self {
        Self(entries: entries + other.entries)
    }

    func containsWholeModule(_ moduleName: String) -> Bool {
        entries.contains {
            $0.moduleName == moduleName
                && $0.declarationPath == nil
                && !$0.isConditional
        }
    }

    func exposes(
        moduleName: String,
        reference: SemanticTypeReference
    ) -> Bool {
        entries.contains { entry in
            !entry.isConditional
                && entryExposes(
                    entry,
                    moduleName: moduleName,
                    reference: reference
                )
        }
    }

    func conditionallyExposes(
        moduleName: String,
        reference: SemanticTypeReference
    ) -> Bool {
        guard !exposes(moduleName: moduleName, reference: reference) else {
            return false
        }
        return entries.contains { entry in
            entry.isConditional
                && entryExposes(
                    entry,
                    moduleName: moduleName,
                    reference: reference
                )
        }
    }

    private func entryExposes(
        _ entry: TargetAwareImportEntry,
        moduleName: String,
        reference: SemanticTypeReference
    ) -> Bool {
        guard entry.moduleName == moduleName else {
            return false
        }
        guard let declarationPath = entry.declarationPath else {
            return true
        }
        let referenceComponents = reference.components
        if declarationPath == referenceComponents {
            return true
        }
        if referenceComponents.count >= declarationPath.count,
           Array(referenceComponents.prefix(declarationPath.count))
            == declarationPath {
            return true
        }
        if declarationPath.count >= referenceComponents.count,
           Array(declarationPath.suffix(referenceComponents.count))
            == referenceComponents {
            return true
        }
        return false
    }
}

struct TargetAwareContainerAlias {
    let record: SemanticTypeAliasRecord
    let sourceIdentity: String
    let sourceImports: TargetAwareSourceImports
}

struct TargetAwareContainerResolutionIndex {
    private struct IndexedTarget {
        let id: WorkspaceTargetID
        let moduleName: String
        let directDependencyTargetIDs: [WorkspaceTargetID]
        let allNodeIDsBySemanticPath: [String: [String]]
        let eligibleNodeIDsBySemanticPath: [String: [String]]
        let aliases: [TargetAwareContainerAlias]
        let exportedImports: TargetAwareSourceImports
    }

    private struct ResolutionCandidate {
        let reference: SemanticTypeReference
        let sourceImports: TargetAwareSourceImports
        let aliasExpansionTrace: [String]
    }

    private struct ResolutionVisit: Hashable {
        let targetID: WorkspaceTargetID
        let referencePath: String
        let sourceImports: TargetAwareSourceImports
    }

    private let targetsByID: [WorkspaceTargetID: IndexedTarget]
    private let workspaceModuleNames: Set<String>

    init(
        manifest: WorkspaceAnalysisManifest,
        nodesByTargetID: [WorkspaceTargetID: [DependencyGraphNode]],
        aliasesByTargetID: [WorkspaceTargetID: [TargetAwareContainerAlias]],
        exportedImportsByTargetID: [
            WorkspaceTargetID: TargetAwareSourceImports
        ],
        validateDAG: Bool
    ) {
        var targets: [WorkspaceTargetID: IndexedTarget] = [:]
        for target in manifest.targets {
            let nodes = nodesByTargetID[target.id] ?? []
            let eligibleNodes = validateDAG
                ? nodes.filter(\.validateDAG)
                : nodes
            targets[target.id] = IndexedTarget(
                id: target.id,
                moduleName: target.moduleName,
                directDependencyTargetIDs: target.directDependencyTargetIDs,
                allNodeIDsBySemanticPath: Self.idsBySemanticPath(nodes),
                eligibleNodeIDsBySemanticPath: Self.idsBySemanticPath(
                    eligibleNodes
                ),
                aliases: (aliasesByTargetID[target.id] ?? []).sorted {
                    if $0.record.path != $1.record.path {
                        return $0.record.path < $1.record.path
                    }
                    if $0.record.target.displayPath
                        != $1.record.target.displayPath {
                        return $0.record.target.displayPath
                            < $1.record.target.displayPath
                    }
                    return $0.sourceIdentity < $1.sourceIdentity
                },
                exportedImports: exportedImportsByTargetID[target.id]
                    ?? .empty
            )
        }
        targetsByID = targets
        workspaceModuleNames = Set(manifest.targets.map(\.moduleName))
    }

    func resolver(
        from targetID: WorkspaceTargetID,
        sourceImports: TargetAwareSourceImports
    ) -> GraphContainerResolver {
        GraphContainerResolver { reference in
            var activeVisits: Set<ResolutionVisit> = []
            return resolve(
                reference,
                from: targetID,
                sourceImports: sourceImports,
                activeVisits: &activeVisits
            )
        }
    }

    private func resolve(
        _ reference: SemanticTypeReference,
        from targetID: WorkspaceTargetID,
        sourceImports: TargetAwareSourceImports,
        activeVisits: inout Set<ResolutionVisit>
    ) -> GraphContainerResolution {
        guard let target = targetsByID[targetID] else {
            return .unresolved()
        }

        let visit = ResolutionVisit(
            targetID: targetID,
            referencePath: reference.displayPath,
            sourceImports: sourceImports
        )
        guard activeVisits.insert(visit).inserted else {
            return .unresolved()
        }
        defer { activeVisits.remove(visit) }

        let candidates = expandedCandidates(
            for: reference,
            in: target,
            sourceImports: sourceImports
        )
        if let localResolution = preferredLocalResolution(
            for: reference,
            candidates: candidates,
            sourceImports: sourceImports,
            in: target
        ) {
            return localResolution
        }

        if let dependencyResolution = resolveDependencyCandidates(
            candidates,
            from: target,
            activeVisits: &activeVisits
        ) {
            return dependencyResolution
        }

        return .unresolved(
            aliasExpansionTrace: uniqueSortedStrings(
                candidates.flatMap(\.aliasExpansionTrace)
            )
        )
    }

    private func preferredLocalResolution(
        for reference: SemanticTypeReference,
        candidates: [ResolutionCandidate],
        sourceImports: TargetAwareSourceImports,
        in target: IndexedTarget
    ) -> GraphContainerResolution? {
        let originalCandidate = ResolutionCandidate(
            reference: reference,
            sourceImports: sourceImports,
            aliasExpansionTrace: []
        )
        if let exactNominal = localResolution(
            candidates: [originalCandidate],
            in: target,
            useSuffixFallback: false
        ) {
            return exactNominal
        }

        if let exact = localResolution(
            candidates: candidates,
            in: target,
            useSuffixFallback: false
        ) {
            return exact
        }

        let suffixCandidates = candidates.filter { candidate in
            guard candidate.reference.components.count > 1,
                  let first = candidate.reference.components.first else {
                return true
            }
            return !workspaceModuleNames.contains(first)
                && first != target.moduleName
        }
        return localResolution(
            candidates: suffixCandidates,
            in: target,
            useSuffixFallback: true
        )
    }

    private func resolveDependencyCandidates(
        _ candidates: [ResolutionCandidate],
        from target: IndexedTarget,
        activeVisits: inout Set<ResolutionVisit>
    ) -> GraphContainerResolution? {
        var dependencyResolutions: [GraphContainerResolution] = []
        var ineligibleConditionalResolutions: [
            GraphContainerResolution
        ] = []
        for candidate in candidates {
            guard let firstComponent = candidate.reference.components.first
            else {
                continue
            }

            let selfQualified = resolveSelfQualifiedCandidate(
                candidate,
                firstComponent: firstComponent,
                from: target,
                activeVisits: &activeVisits
            )
            if selfQualified.wasHandled {
                if let resolution = selfQualified.resolution {
                    dependencyResolutions.append(resolution)
                }
                continue
            }

            if let conditionalResolution = conditionalImportResolution(
                for: candidate.reference,
                from: target,
                sourceImports: candidate.sourceImports
            ) {
                let tracedResolution = conditionalResolution
                    .withAliasExpansionTrace(
                        candidate.aliasExpansionTrace
                    )
                if tracedResolution.requiresDiagnostic {
                    return tracedResolution
                }
                ineligibleConditionalResolutions.append(
                    tracedResolution
                )
            }

            let visibleDependencies = visibleDependencies(
                for: candidate.reference,
                from: target,
                sourceImports: candidate.sourceImports
            )
            if let qualifiedResolutions = resolveWorkspaceQualifiedCandidate(
                candidate,
                firstComponent: firstComponent,
                visibleDependencies: visibleDependencies,
                activeVisits: &activeVisits
            ) {
                dependencyResolutions.append(
                    contentsOf: qualifiedResolutions
                )
                continue
            }

            for dependency in visibleDependencies {
                let resolution = resolve(
                    candidate.reference,
                    from: dependency.id,
                    sourceImports: .empty,
                    activeVisits: &activeVisits
                )
                if !resolution.allCandidateIDs.isEmpty {
                    dependencyResolutions.append(
                        resolution.withAliasExpansionTrace(
                            candidate.aliasExpansionTrace
                        )
                    )
                }
            }
        }

        if !dependencyResolutions.isEmpty {
            return mergedResolution(dependencyResolutions)
        }
        guard !ineligibleConditionalResolutions.isEmpty else {
            return nil
        }
        return mergedResolution(ineligibleConditionalResolutions)
    }

    private func resolveSelfQualifiedCandidate(
        _ candidate: ResolutionCandidate,
        firstComponent: String,
        from target: IndexedTarget,
        activeVisits: inout Set<ResolutionVisit>
    ) -> (wasHandled: Bool, resolution: GraphContainerResolution?) {
        guard candidate.reference.components.count > 1,
              firstComponent == target.moduleName else {
            return (false, nil)
        }

        let resolution = resolve(
            semanticReference(
                components: Array(candidate.reference.components.dropFirst())
            ),
            from: target.id,
            sourceImports: candidate.sourceImports,
            activeVisits: &activeVisits
        )
        guard !resolution.allCandidateIDs.isEmpty else {
            return (true, nil)
        }
        return (
            true,
            resolution.withAliasExpansionTrace(
                candidate.aliasExpansionTrace
            )
        )
    }

    private func resolveWorkspaceQualifiedCandidate(
        _ candidate: ResolutionCandidate,
        firstComponent: String,
        visibleDependencies: [IndexedTarget],
        activeVisits: inout Set<ResolutionVisit>
    ) -> [GraphContainerResolution]? {
        guard candidate.reference.components.count > 1,
              workspaceModuleNames.contains(firstComponent) else {
            return nil
        }

        let stripped = semanticReference(
            components: Array(candidate.reference.components.dropFirst())
        )
        var resolutions: [GraphContainerResolution] = []
        for dependency in visibleDependencies
        where dependency.moduleName == firstComponent {
            let resolution = resolve(
                stripped,
                from: dependency.id,
                sourceImports: .empty,
                activeVisits: &activeVisits
            )
            if !resolution.allCandidateIDs.isEmpty {
                resolutions.append(
                    resolution.withAliasExpansionTrace(
                        candidate.aliasExpansionTrace
                    )
                )
            }
        }
        return resolutions
    }

    private func conditionalImportResolution(
        for reference: SemanticTypeReference,
        from target: IndexedTarget,
        sourceImports: TargetAwareSourceImports
    ) -> GraphContainerResolution? {
        var activeTargetIDs: Set<WorkspaceTargetID> = [target.id]
        return conditionalImportResolution(
            for: reference,
            from: target,
            sourceImports: sourceImports,
            activeTargetIDs: &activeTargetIDs
        )
    }

    private func conditionalImportResolution(
        for reference: SemanticTypeReference,
        from target: IndexedTarget,
        sourceImports: TargetAwareSourceImports,
        activeTargetIDs: inout Set<WorkspaceTargetID>
    ) -> GraphContainerResolution? {
        var ineligibleMatches: [GraphContainerResolution] = []
        for dependencyID in target.directDependencyTargetIDs {
            guard let dependency = targetsByID[dependencyID] else {
                continue
            }
            let lookupReference: SemanticTypeReference
            if reference.components.count > 1,
               reference.components.first == dependency.moduleName {
                lookupReference = semanticReference(
                    components: Array(reference.components.dropFirst())
                )
            } else {
                lookupReference = reference
            }

            if sourceImports.conditionallyExposes(
                moduleName: dependency.moduleName,
                reference: lookupReference
            ),
               let resolution = targetPotentialContainerResolution(
                lookupReference,
                in: dependency
            ) {
                if !resolution.eligibleCandidateIDs.isEmpty {
                    return .excluded(
                        reason: "conditional import visibility for module "
                            + "'\(dependency.moduleName)' cannot be proven "
                            + "without the active Swift compilation "
                            + "conditions",
                        aliasExpansionTrace: []
                    )
                }
                ineligibleMatches.append(resolution)
            }
            guard sourceImports.exposes(
                moduleName: dependency.moduleName,
                reference: lookupReference
            ),
                  sourceImports.containsWholeModule(
                    dependency.moduleName
                  ),
                  activeTargetIDs.insert(dependency.id).inserted else {
                continue
            }
            if let resolution = conditionalImportResolution(
                for: reference,
                from: dependency,
                sourceImports: dependency.exportedImports,
                activeTargetIDs: &activeTargetIDs
            ) {
                if resolution.requiresDiagnostic {
                    return resolution
                }
                ineligibleMatches.append(resolution)
            }
            activeTargetIDs.remove(dependency.id)
        }
        guard !ineligibleMatches.isEmpty else {
            return nil
        }
        return mergedResolution(ineligibleMatches)
    }

    private func targetPotentialContainerResolution(
        _ reference: SemanticTypeReference,
        in target: IndexedTarget
    ) -> GraphContainerResolution? {
        let candidates = expandedCandidates(
            for: reference,
            in: target,
            sourceImports: .empty
        )
        if let exactResolution = localResolution(
            candidates: candidates,
            in: target,
            useSuffixFallback: false
        ) {
            return exactResolution
        }
        let suffixCandidates = candidates.filter { candidate in
            guard candidate.reference.components.count > 1,
                  let first = candidate.reference.components.first else {
                return true
            }
            return !workspaceModuleNames.contains(first)
                && first != target.moduleName
        }
        return localResolution(
            candidates: suffixCandidates,
            in: target,
            useSuffixFallback: true
        )
    }

    private func visibleDependencies(
        for reference: SemanticTypeReference,
        from target: IndexedTarget,
        sourceImports: TargetAwareSourceImports
    ) -> [IndexedTarget] {
        var visibleByID: [WorkspaceTargetID: IndexedTarget] = [:]
        var activeTargetIDs: Set<WorkspaceTargetID> = [target.id]
        collectVisibleDependencies(
            for: reference,
            from: target,
            sourceImports: sourceImports,
            activeTargetIDs: &activeTargetIDs,
            visibleByID: &visibleByID
        )
        return visibleByID.values.sorted { $0.id < $1.id }
    }

    private func collectVisibleDependencies(
        for reference: SemanticTypeReference,
        from target: IndexedTarget,
        sourceImports: TargetAwareSourceImports,
        activeTargetIDs: inout Set<WorkspaceTargetID>,
        visibleByID: inout [WorkspaceTargetID: IndexedTarget]
    ) {
        for dependencyID in target.directDependencyTargetIDs {
            guard let dependency = targetsByID[dependencyID] else {
                continue
            }
            let lookupReference: SemanticTypeReference
            if reference.components.count > 1,
               reference.components.first == dependency.moduleName {
                lookupReference = semanticReference(
                    components: Array(reference.components.dropFirst())
                )
            } else {
                lookupReference = reference
            }
            guard sourceImports.exposes(
                moduleName: dependency.moduleName,
                reference: lookupReference
            ) else {
                continue
            }

            visibleByID[dependency.id] = dependency
            guard sourceImports.containsWholeModule(
                dependency.moduleName
            ),
                  activeTargetIDs.insert(dependency.id).inserted else {
                continue
            }
            collectVisibleDependencies(
                for: reference,
                from: dependency,
                sourceImports: dependency.exportedImports,
                activeTargetIDs: &activeTargetIDs,
                visibleByID: &visibleByID
            )
            activeTargetIDs.remove(dependency.id)
        }
    }

    private func expandedCandidates(
        for reference: SemanticTypeReference,
        in target: IndexedTarget,
        sourceImports: TargetAwareSourceImports
    ) -> [ResolutionCandidate] {
        var queue = [
            ResolutionCandidate(
                reference: reference,
                sourceImports: sourceImports,
                aliasExpansionTrace: []
            )
        ]
        var visited: Set<String> = [
            candidateIdentity(
                reference: reference,
                sourceImports: sourceImports
            )
        ]
        var terminalCandidates: [ResolutionCandidate] = []
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1
            var matchedAlias = false

            for prefixLength in stride(
                from: current.reference.components.count,
                through: 1,
                by: -1
            ) {
                let prefix = Array(
                    current.reference.components.prefix(prefixLength)
                )
                let remainder = Array(
                    current.reference.components.dropFirst(prefixLength)
                )
                for alias in matchingAliases(prefix, in: target.aliases) {
                    matchedAlias = true
                    let components = alias.record.target.components
                        + remainder
                    let expanded = semanticReference(components: components)
                    let identity = candidateIdentity(
                        reference: expanded,
                        sourceImports: alias.sourceImports
                    )
                    guard visited.insert(identity).inserted else {
                        continue
                    }
                    queue.append(
                        ResolutionCandidate(
                            reference: expanded,
                            sourceImports: alias.sourceImports,
                            aliasExpansionTrace:
                                current.aliasExpansionTrace
                                + [alias.record.path]
                        )
                    )
                }
            }

            if !matchedAlias {
                terminalCandidates.append(current)
            }
        }

        return terminalCandidates
    }

    private func matchingAliases(
        _ referencePrefix: [String],
        in aliases: [TargetAwareContainerAlias]
    ) -> [TargetAwareContainerAlias] {
        let exactMatches = aliases.filter {
            $0.record.components == referencePrefix
        }
        if !exactMatches.isEmpty {
            return exactMatches
        }
        return aliases.filter { alias in
            guard alias.record.components.count >= referencePrefix.count
            else {
                return false
            }
            return Array(
                alias.record.components.suffix(referencePrefix.count)
            ) == referencePrefix
        }
    }

    private func localResolution(
        candidates: [ResolutionCandidate],
        in target: IndexedTarget,
        useSuffixFallback: Bool
    ) -> GraphContainerResolution? {
        var matchingPathsByCandidate: [
            (candidate: ResolutionCandidate, paths: [String])
        ] = []

        for candidate in candidates {
            let paths: [String]
            if useSuffixFallback {
                paths = suffixMatches(
                    for: candidate.reference.components,
                    candidatePaths: Set(
                        target.allNodeIDsBySemanticPath.keys
                    )
                )
            } else if target.allNodeIDsBySemanticPath[
                candidate.reference.displayPath
            ] != nil {
                paths = [candidate.reference.displayPath]
            } else {
                paths = []
            }
            if !paths.isEmpty {
                matchingPathsByCandidate.append((candidate, paths))
            }
        }

        guard !matchingPathsByCandidate.isEmpty else {
            return nil
        }

        let allIDs = uniqueSortedStrings(
            matchingPathsByCandidate.flatMap { item in
                item.paths.flatMap {
                    target.allNodeIDsBySemanticPath[$0] ?? []
                }
            }
        )
        let eligibleIDs = uniqueSortedStrings(
            matchingPathsByCandidate.flatMap { item in
                item.paths.flatMap {
                    target.eligibleNodeIDsBySemanticPath[$0] ?? []
                }
            }
        )
        let traces = uniqueSortedStrings(
            matchingPathsByCandidate.flatMap {
                $0.candidate.aliasExpansionTrace
            }
        )
        return GraphContainerResolution(
            state: allIDs.count > 1 ? .ambiguous : .resolved,
            allCandidateIDs: allIDs,
            eligibleCandidateIDs: eligibleIDs,
            excludedReason: nil,
            aliasExpansionTrace: traces,
            usedSuffixFallback: useSuffixFallback
        )
    }

    private func mergedResolution(
        _ resolutions: [GraphContainerResolution]
    ) -> GraphContainerResolution {
        let allIDs = uniqueSortedStrings(
            resolutions.flatMap(\.allCandidateIDs)
        )
        return GraphContainerResolution(
            state: allIDs.count > 1 ? .ambiguous : .resolved,
            allCandidateIDs: allIDs,
            eligibleCandidateIDs: uniqueSortedStrings(
                resolutions.flatMap(\.eligibleCandidateIDs)
            ),
            excludedReason: nil,
            aliasExpansionTrace: uniqueSortedStrings(
                resolutions.flatMap(\.aliasExpansionTrace)
            ),
            usedSuffixFallback: resolutions.contains {
                $0.usedSuffixFallback
            }
        )
    }

    private func suffixMatches(
        for components: [String],
        candidatePaths: Set<String>
    ) -> [String] {
        guard !components.isEmpty else {
            return []
        }
        return candidatePaths.filter { path in
            let candidateComponents = path.split(separator: ".")
                .map(String.init)
            if candidateComponents.count >= components.count {
                return Array(
                    candidateComponents.suffix(components.count)
                ) == components
            }
            guard candidateComponents.count > 1 else {
                return false
            }
            return Array(
                components.suffix(candidateComponents.count)
            ) == candidateComponents
        }
        .sorted()
    }

    private func candidateIdentity(
        reference: SemanticTypeReference,
        sourceImports: TargetAwareSourceImports
    ) -> String {
        reference.displayPath + "|" + sourceImports.entries.map { entry in
            let path = entry.declarationPath?.joined(separator: ".") ?? "*"
            let exported = entry.isExported ? "exported" : "local"
            let conditional = entry.isConditional
                ? "conditional"
                : "unconditional"
            return "\(entry.moduleName):\(path):\(exported):\(conditional)"
        }
        .joined(separator: ",")
    }

    private func semanticReference(
        components: [String]
    ) -> SemanticTypeReference {
        SemanticTypeReference(
            displayPath: components.joined(separator: "."),
            components: components
        )
    }

    private static func idsBySemanticPath(
        _ nodes: [DependencyGraphNode]
    ) -> [String: [String]] {
        Dictionary(grouping: nodes, by: \.semanticPath)
            .mapValues { uniqueSortedStrings($0.map(\.id)) }
    }
}

private extension GraphContainerResolution {
    func withAliasExpansionTrace(
        _ prefix: [String]
    ) -> GraphContainerResolution {
        GraphContainerResolution(
            state: state,
            allCandidateIDs: allCandidateIDs,
            eligibleCandidateIDs: eligibleCandidateIDs,
            excludedReason: excludedReason,
            aliasExpansionTrace: uniqueSortedStrings(
                prefix + aliasExpansionTrace
            ),
            usedSuffixFallback: usedSuffixFallback,
            requiresDiagnostic: requiresDiagnostic
        )
    }
}

private func uniqueSortedStrings(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

private final class SourceImportCollector: SyntaxVisitor {
    var entries: [TargetAwareImportEntry] = []
    private var conditionalCompilationDepth = 0

    override func visit(
        _ node: IfConfigDeclSyntax
    ) -> SyntaxVisitorContinueKind {
        conditionalCompilationDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: IfConfigDeclSyntax) {
        conditionalCompilationDepth -= 1
    }

    override func visit(
        _ node: ImportDeclSyntax
    ) -> SyntaxVisitorContinueKind {
        let components = node.path.map { $0.name.text }
        guard let moduleName = components.first,
              !moduleName.isEmpty else {
            return .skipChildren
        }
        let isExported = node.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else {
                return false
            }
            return attribute.attributeName.trimmedDescription == "_exported"
        } || node.modifiers.contains {
            $0.name.text == "public"
        }
        entries.append(
            TargetAwareImportEntry(
                moduleName: moduleName,
                declarationPath: node.importKindSpecifier == nil
                    ? nil
                    : Array(components.dropFirst()),
                isExported: isExported,
                isConditional: conditionalCompilationDepth > 0
            )
        )
        return .skipChildren
    }
}

func targetAwareSourceImports(
    in sourceFile: SourceFileSyntax
) -> TargetAwareSourceImports {
    let collector = SourceImportCollector(viewMode: .sourceAccurate)
    collector.walk(sourceFile)
    return TargetAwareSourceImports(entries: collector.entries)
}
