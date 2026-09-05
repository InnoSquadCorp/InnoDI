import InnoDICore

func validateResolvedEdges(
    _ edges: [ResolvedHierarchyEdge],
    containersByID: [String: WorkspaceHierarchyContainerRecord],
    moduleGraph: WorkspaceModuleGraphSnapshot,
    resolver: SemanticResolverIndex,
    typeCandidatePaths: Set<String>
) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    for edge in edges {
        guard let child = containersByID[edge.childContainerID] else {
            issues.append(
                makeChildContainerOutOfWorkspaceIssue(edge: edge)
            )
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
                    message: "@SubContainer '\(edge.subContainer.memberName)' crosses from module '\(edge.parentModule?.displayName ?? "<unknown>")' to '\(edge.childModule?.displayName ?? "<unknown>")', but '\(child.displayName)' does not declare ContainerRole.component.",
                    location: edge.subContainer.location,
                    notes: [
                        ValidationIssueNote(
                            message: "child container '\(child.path)' is declared here.",
                            location: child.location
                        )
                    ] + moduleDisambiguationNotes,
                    remediation: "Annotate '\(child.displayName)' with @DIContainerRole(role: ContainerRole.component), or keep the child in the same module as its parent.",
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

/// Build the diagnostic emitted when a `@SubContainer` resolves to a
/// child container ID the workspace snapshot did not collect a record for.
///
/// This previously fell through with a silent `continue`, masking child
/// containers that live in modules outside the snapshot scope or
/// references that the resolver accepted but the workspace collector did
/// not finish loading. The diagnostic now states which child reference
/// could not be located and points at the concrete remediation steps.
///
/// Distinct from `hierarchy.unresolved-child-reference`, which fires
/// earlier when the resolver itself rejected the type reference; this
/// code path runs only after a successful resolution that the workspace
/// snapshot still cannot map to a container record.
func makeChildContainerOutOfWorkspaceIssue(edge: ResolvedHierarchyEdge) -> ValidationIssue {
    let parentModuleName = edge.parentModule?.displayName ?? "<unknown>"
    let childModuleName = edge.childModule?.displayName ?? "<unknown-or-not-loaded>"

    var notes: [ValidationIssueNote] = [
        ValidationIssueNote(
            message: "child reference '\(edge.childPath)' resolved to a container ID '\(edge.childContainerID)' that is absent from the workspace snapshot.",
            location: edge.childLocation
        )
    ]
    if let childModule = edge.childModule {
        notes.append(
            ValidationIssueNote(
                message: "child module '\(childModule.displayName)' was identified at '\(childModule.manifestPath)' but its container declarations were not visible to this validation pass.",
                location: edge.childLocation
            )
        )
    }
    if let parentModule = edge.parentModule {
        notes.append(
            ValidationIssueNote(
                message: "parent module '\(parentModule.displayName)' is declared at '\(parentModule.manifestPath)'. Confirm this manifest or project file declares a dependency on the child target/product.",
                location: edge.parentLocation
            )
        )
    }
    notes.append(contentsOf: hierarchyModuleDisambiguationNotes(for: edge))

    var metadata: [String: String] = [
        "parentContainerPath": edge.parentPath,
        "childContainerPath": edge.childPath,
        "childContainerID": edge.childContainerID,
        "parentModule": parentModuleName,
        "childModule": childModuleName
    ]
    if let parentModule = edge.parentModule {
        metadata["parentModuleID"] = parentModule.moduleID
        metadata["parentManifestPath"] = parentModule.manifestPath
    }
    if let childModule = edge.childModule {
        metadata["childModuleID"] = childModule.moduleID
        metadata["childManifestPath"] = childModule.manifestPath
    }

    return ValidationIssue(
        code: "hierarchy.child-not-in-workspace",
        severity: .warning,
        message: "@SubContainer '\(edge.subContainer.memberName)' on '\(edge.parentPath)' (module '\(parentModuleName)') references child container '\(edge.childPath)', but the workspace validator could not find a container record for it. Cross-module checks (component marker, module dependency edge, dependency satisfaction) are skipped for this edge.",
        location: edge.subContainer.location,
        notes: notes,
        remediation: "Confirm the child target ships @DIContainerRole(role: ContainerRole.component), add the child target/product to the parent module's manifest dependencies, and re-run validation. If the child intentionally lives outside the validated workspace, treat this warning as the contract you are accepting.",
        metadata: metadata
    )
}

func hierarchyModuleDisambiguationNotes(for edge: ResolvedHierarchyEdge) -> [ValidationIssueNote] {
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

func makeAmbiguousChildReferenceIssue(
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

func makeUnresolvedChildReferenceIssue(
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

func validateDependencySatisfaction(
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
    if resolvedMappings.suppressesDependencySatisfaction {
        return issues
    }

    // Detect entries declared in `with:` / `bindings:` that
    // do not correspond to any child input. The dependency-satisfaction loop
    // below iterates `requiredInputs` keys, so extras would otherwise be
    // silently dropped — making `with: [\.bogus]` look successful.
    let extraMappings = resolvedMappings.mappings.keys
        .filter { requiredInputs[$0] == nil }
        .sorted()
    for extraName in extraMappings {
        let location = resolvedMappings.mappings[extraName]?.location ?? edge.subContainer.location
        issues.append(
            ValidationIssue(
                code: "hierarchy.unknown-child-input",
                severity: .error,
                message: "@SubContainer '\(edge.subContainer.memberName)' in '\(edge.parentPath)' forwards '\(extraName)', but '\(child.displayName)' does not declare a matching @Input member.",
                location: location,
                notes: [
                    ValidationIssueNote(
                        message: "child component '\(child.path)' is reached from parent container '\(parent.path)'.",
                        location: child.location
                    )
                ],
                remediation: "Remove '\(extraName)' from with:/bindings:, or declare a matching @Input on '\(child.displayName)'.",
                metadata: [
                    "parentContainerPath": parent.path,
                    "childContainerPath": child.path,
                    "childInputName": extraName
                ]
            )
        )
    }

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

func validateDuplicateParents(
    _ edges: [ResolvedHierarchyEdge],
    containersByID: [String: WorkspaceHierarchyContainerRecord]
) -> [ValidationIssue] {
    let grouped = Dictionary(grouping: edges.filter {
        containersByID[$0.childContainerID]?.isComponent == true
    }, by: \.childContainerID)

    var issues: [ValidationIssue] = []
    for (childContainerID, unsortedEdges) in grouped where unsortedEdges.count > 1 {
        // `Dictionary(grouping:)` does not preserve insertion order, so sort
        // edges by their source location before picking the "first" parent.
        // Without this, the duplicate-parent diagnostic's primary edge is
        // non-deterministic across runs, which makes the "first parent
        // mounts here" note hop between parents.
        let childEdges = unsortedEdges.sorted { lhs, rhs in
            let lhsLoc = lhs.subContainer.location
            let rhsLoc = rhs.subContainer.location
            if lhsLoc.filePath != rhsLoc.filePath {
                return lhsLoc.filePath < rhsLoc.filePath
            }
            if lhsLoc.line != rhsLoc.line {
                return lhsLoc.line < rhsLoc.line
            }
            return lhsLoc.column < rhsLoc.column
        }
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
                    remediation: "Keep each component-role container under a single parent hierarchy edge.",
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

func validateOrphanComponents(
    _ containers: [WorkspaceHierarchyContainerRecord],
    reachableContainerIDs: Set<String>
) -> [ValidationIssue] {
    containers
        .filter { $0.isComponent && !reachableContainerIDs.contains($0.containerID) }
        .map { component in
            ValidationIssue(
                code: "hierarchy.orphan-component",
                severity: .error,
                message: "Component '\(component.displayName)' is not reachable from any ContainerRole.root container.",
                location: component.location,
                remediation: "Mount '\(component.displayName)' from a root-role parent container, or change its role if this type is not part of the strict hierarchy.",
                metadata: [
                    "childContainerPath": component.nominalPath
                ]
            )
        }
}

func detectHierarchyCycles(
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
