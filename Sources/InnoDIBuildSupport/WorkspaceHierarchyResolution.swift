import InnoDICore

struct PendingHierarchyIssue {
    let parentContainerID: String
    let issue: ValidationIssue
}

struct ResolvedHierarchyModuleContext: Equatable {
    let moduleID: String
    let displayName: String
    let manifestPath: String

    init(record: WorkspaceModuleRecord) {
        self.moduleID = record.moduleID
        self.displayName = record.name
        self.manifestPath = record.manifestPath
    }
}

struct ResolvedHierarchyEdge: Equatable {
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

struct ReachableHierarchy {
    let containerIDs: Set<String>
    let edges: [ResolvedHierarchyEdge]
}

struct ResolvedHierarchyEdgesResult {
    let edges: [ResolvedHierarchyEdge]
    let pendingIssues: [PendingHierarchyIssue]
}

func resolveHierarchyEdges(
    containers: [WorkspaceHierarchyContainerRecord],
    containersByNominalPath: [String: [WorkspaceHierarchyContainerRecord]],
    moduleGraph: WorkspaceModuleGraphSnapshot,
    resolver: SemanticResolverIndex,
    modulesByContainerID: [String: ResolvedHierarchyModuleContext],
    candidatePaths: Set<String>
) -> ResolvedHierarchyEdgesResult {
    var pendingIssues: [PendingHierarchyIssue] = []

    let edges: [ResolvedHierarchyEdge] = containers.flatMap { parent in
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

    return ResolvedHierarchyEdgesResult(edges: edges, pendingIssues: pendingIssues)
}

func reachablePathsAndEdges(
    from rootContainerIDs: [String],
    edges: [ResolvedHierarchyEdge]
) -> ReachableHierarchy {
    let groupedEdges = Dictionary(grouping: edges, by: \.parentContainerID)
    var visited: Set<String> = []
    var reachableEdges: [ResolvedHierarchyEdge] = []
    var queue = rootContainerIDs
    var index = 0

    while index < queue.count {
        let current = queue[index]
        index += 1
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

struct ResolvedDependencyMapping {
    let parentName: String
    let location: ValidationIssueLocation
}

struct ResolvedDependencyMappingsResult {
    let mappings: [String: ResolvedDependencyMapping]
    let issues: [ValidationIssue]
    let suppressesDependencySatisfaction: Bool

    init(
        mappings: [String: ResolvedDependencyMapping],
        issues: [ValidationIssue],
        suppressesDependencySatisfaction: Bool = false
    ) {
        self.mappings = mappings
        self.issues = issues
        self.suppressesDependencySatisfaction = suppressesDependencySatisfaction
    }
}

func resolvedDependencyMappings(
    parent: WorkspaceHierarchyContainerRecord,
    child: WorkspaceHierarchyContainerRecord,
    edge: ResolvedHierarchyEdge
) -> ResolvedDependencyMappingsResult {
    // The macro-side validator (`DIContainerValidator`) treats
    // `with: + withNames:` and `bindings: + same-name wiring` as independent
    // conflicts, so both diagnostics can fire on the same attribute. Match
    // that behavior here instead of short-circuiting on the first hit — when
    // a user combines all three labels they should see every mismatch in
    // one pass.
    var conflictIssues: [ValidationIssue] = []

    if case let .conflictingWithAndWithNames(location) = edge.subContainer.sameNameWiring {
        conflictIssues.append(
            makeConflictingWithAndWithNamesIssue(
                parent: parent,
                child: child,
                edge: edge,
                location: location
            )
        )
    }

    // When `with:` and `withNames:` are both present, `sameNameWiring.label`
    // collapses to nil — but the bindings-vs-same-name conflict is still
    // real. Surface it under the `.with` label (the canonical form) so the
    // user sees both diagnostics in one pass.
    let bindingsConflictLabel: SubContainerSameNameWiringLabel? = {
        if let label = edge.subContainer.sameNameWiring.label {
            return label
        }
        if case .conflictingWithAndWithNames = edge.subContainer.sameNameWiring {
            return .with
        }
        return nil
    }()
    if !edge.subContainer.bindings.isEmpty, let bindingsConflictLabel {
        conflictIssues.append(
            makeConflictingSameNameAndBindingsIssue(
                parent: parent,
                child: child,
                edge: edge,
                label: bindingsConflictLabel
            )
        )
    }

    if !conflictIssues.isEmpty {
        return ResolvedDependencyMappingsResult(
            mappings: [:],
            issues: conflictIssues,
            suppressesDependencySatisfaction: true
        )
    }

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

    switch edge.subContainer.sameNameWiring {
    case let .parsed(_, dependencies):
        return resolvedDependencyMappings(
            parent: parent,
            child: child,
            edge: edge,
            kind: .withDependency,
            candidates: dependencies.map {
                (
                    key: $0.name,
                    mapping: ResolvedDependencyMapping(parentName: $0.name, location: $0.location),
                    location: $0.location
                )
            }
        )
    case let .invalid(label, location):
        return ResolvedDependencyMappingsResult(
            mappings: [:],
            issues: [
                makeInvalidSameNameWiringIssue(
                    parent: parent,
                    child: child,
                    edge: edge,
                    label: label,
                    location: location
                )
            ],
            suppressesDependencySatisfaction: true
        )
    case let .conflictingWithAndWithNames(location):
        return ResolvedDependencyMappingsResult(
            mappings: [:],
            issues: [
                makeConflictingWithAndWithNamesIssue(
                    parent: parent,
                    child: child,
                    edge: edge,
                    location: location
                )
            ],
            suppressesDependencySatisfaction: true
        )
    case .omitted:
        break
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

private func makeConflictingSameNameAndBindingsIssue(
    parent: WorkspaceHierarchyContainerRecord,
    child: WorkspaceHierarchyContainerRecord,
    edge: ResolvedHierarchyEdge,
    label: SubContainerSameNameWiringLabel
) -> ValidationIssue {
    ValidationIssue(
        code: "hierarchy.bindings-conflicts-with-with",
        severity: .error,
        message: "@SubContainer '\(edge.subContainer.memberName)' in '\(edge.parentPath)' cannot use \(label.rawValue): together with bindings:.",
        location: edge.subContainer.location,
        notes: [
            ValidationIssueNote(
                message: "child component '\(child.path)' is reached from parent container '\(parent.path)'.",
                location: child.location
            )
        ],
        remediation: "Use with: or withNames: for same-name subset/reorder wiring, or bindings: for explicit child-to-parent remapping.",
        metadata: [
            "parentContainerPath": parent.path,
            "childContainerPath": child.path,
            "subContainerMemberName": edge.subContainer.memberName,
            "label": label.rawValue
        ]
    )
}

private func makeConflictingWithAndWithNamesIssue(
    parent: WorkspaceHierarchyContainerRecord,
    child: WorkspaceHierarchyContainerRecord,
    edge: ResolvedHierarchyEdge,
    location: ValidationIssueLocation
) -> ValidationIssue {
    ValidationIssue(
        code: "hierarchy.with-conflicts-with-with-names",
        severity: .error,
        message: "@SubContainer '\(edge.subContainer.memberName)' in '\(edge.parentPath)' cannot use both with: and withNames:.",
        location: location,
        notes: [
            ValidationIssueNote(
                message: "child component '\(child.path)' is reached from parent container '\(parent.path)'.",
                location: child.location
            )
        ],
        remediation: "Use exactly one same-name wiring form, or use bindings: for explicit child-to-parent remapping.",
        metadata: [
            "parentContainerPath": parent.path,
            "childContainerPath": child.path,
            "subContainerMemberName": edge.subContainer.memberName
        ]
    )
}

private func makeInvalidSameNameWiringIssue(
    parent: WorkspaceHierarchyContainerRecord,
    child: WorkspaceHierarchyContainerRecord,
    edge: ResolvedHierarchyEdge,
    label: SubContainerSameNameWiringLabel,
    location: ValidationIssueLocation
) -> ValidationIssue {
    let literalExample: String
    switch label {
    case .with:
        literalExample = "with: [\\.config] or with: []"
    case .withNames:
        literalExample = "withNames: [\"config\"] or withNames: []"
    }

    return ValidationIssue(
        code: "hierarchy.invalid-same-name-wiring",
        severity: .error,
        message: "@SubContainer '\(edge.subContainer.memberName)' in '\(edge.parentPath)' uses \(label.rawValue): that is not a fully parseable literal array.",
        location: location,
        notes: [
            ValidationIssueNote(
                message: "child component '\(child.path)' is reached from parent container '\(parent.path)'.",
                location: child.location
            )
        ],
        remediation: "Use a literal array such as \(literalExample). Runtime variables and computed elements are not supported; use bindings: for renamed child inputs.",
        metadata: [
            "parentContainerPath": parent.path,
            "childContainerPath": child.path,
            "subContainerMemberName": edge.subContainer.memberName,
            "label": label.rawValue
        ]
    )
}

extension WorkspaceHierarchySameNameWiringRecord {
    var label: SubContainerSameNameWiringLabel? {
        switch self {
        case .omitted:
            return nil
        case let .parsed(label, _), let .invalid(label, _):
            return label
        case .conflictingWithAndWithNames:
            return nil
        }
    }
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
            return "@SubContainer '\(edge.subContainer.memberName)' in '\(edge.parentPath)' lists dependency '\(dependencyName)' more than once in with:/withNames: for '\(child.displayName)'."
        }
    }

    var remediation: String {
        switch self {
        case .binding:
            "Keep at most one bindings: entry per child input."
        case .withDependency:
            "Keep each with:/withNames: dependency name listed at most once."
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

func hierarchyMemberTypesMatch(
    _ parent: WorkspaceHierarchyMemberRecord,
    _ child: WorkspaceHierarchyMemberRecord,
    resolver: SemanticResolverIndex,
    typeCandidatePaths: Set<String>
) -> Bool {
    let parentResolution = resolveHierarchyMemberType(
        parent,
        resolver: resolver,
        typeCandidatePaths: typeCandidatePaths
    )
    let childResolution = resolveHierarchyMemberType(
        child,
        resolver: resolver,
        typeCandidatePaths: typeCandidatePaths
    )

    switch (parentResolution, childResolution) {
    case let (.resolved(parentPath), .resolved(childPath)):
        return parentPath == childPath
    case (.ambiguous, _), (_, .ambiguous):
        return false
    case (.fallback, _), (_, .fallback):
        return parent.rawTypeSpelling == child.rawTypeSpelling
    }
}

func resolveHierarchyMemberType(
    _ member: WorkspaceHierarchyMemberRecord,
    resolver: SemanticResolverIndex,
    typeCandidatePaths: Set<String>
) -> HierarchyMemberTypeResolution {
    guard let reference = member.semanticTypeReference else {
        return .fallback
    }

    let resolution = resolver.resolvePath(for: reference, candidatePaths: typeCandidatePaths)
    switch resolution.state {
    case .resolved:
        guard let resolvedPath = resolution.resolvedPath else {
            return .fallback
        }
        return .resolved(resolvedPath)
    case .ambiguous:
        return .ambiguous
    case .excluded, .unresolved:
        return .fallback
    }
}

enum HierarchyMemberTypeResolution {
    case resolved(String)
    case ambiguous
    case fallback
}
