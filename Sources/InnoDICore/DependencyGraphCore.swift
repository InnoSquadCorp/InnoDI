package struct DependencyGraphNode: Hashable {
    package let id: String
    package let displayName: String
    package let semanticPath: String
    package let isRoot: Bool
    package let validateDAG: Bool
    package let requiredInputs: [String]
    package let assistedInputs: [String]

    package init(
        id: String,
        displayName: String,
        semanticPath: String,
        isRoot: Bool,
        validateDAG: Bool = true,
        requiredInputs: [String],
        assistedInputs: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.semanticPath = semanticPath
        self.isRoot = isRoot
        self.validateDAG = validateDAG
        self.requiredInputs = requiredInputs
        self.assistedInputs = assistedInputs
    }
}

/// Canonical provider semantics shared by source analysis and graph tooling.
/// Source coordinates intentionally live outside the semantic identity so a
/// declaration moving within the same file does not trip a contract diff.
package struct DependencyGraphProvider: Hashable, Sendable {
    package let id: String
    package let containerID: String
    package let name: String
    package let type: String
    package let role: Role
    package let lifetime: Lifetime
    package let initialization: Initialization
    package let isolation: Isolation
    package let effect: Effect
    package let inputKind: InputKind?
    package let dependencies: [String]
    package let dependencyBindings: [DependencyBinding]
    package let containerBindings: [ContainerBinding]
    package let collection: CollectionContract?
    package let source: SourceLocation

    package init(
        id: String,
        containerID: String,
        name: String,
        type: String,
        role: Role,
        lifetime: Lifetime,
        initialization: Initialization,
        isolation: Isolation,
        effect: Effect,
        inputKind: InputKind? = nil,
        dependencies: [String] = [],
        dependencyBindings: [DependencyBinding] = [],
        containerBindings: [ContainerBinding] = [],
        collection: CollectionContract? = nil,
        source: SourceLocation
    ) {
        self.id = id
        self.containerID = containerID
        self.name = name
        self.type = type
        self.role = role
        self.lifetime = lifetime
        self.initialization = initialization
        self.isolation = isolation
        self.effect = effect
        self.inputKind = inputKind
        self.dependencies = dependencies
        self.dependencyBindings = dependencyBindings
        self.containerBindings = containerBindings
        self.collection = collection
        self.source = source
    }

    package enum Role: String, Codable, Hashable, Sendable {
        case input
        case provider
        case subcontainer
        case assistedFactory
        case multibinding
    }

    package enum Lifetime: String, Codable, Hashable, Sendable {
        case external
        case shared
        case transient
    }

    package enum Initialization: String, Codable, Hashable, Sendable {
        case external
        case eager
        case onAccess
        case onDemand
        case assisted
    }

    package enum Isolation: String, Codable, Hashable, Sendable {
        case nonisolated
        case mainActor
    }

    package enum Effect: String, Codable, Hashable, Sendable {
        case sync
        case async
        case asyncThrows
    }

    package enum InputKind: String, Codable, Hashable, Sendable {
        case container
        case assisted
    }

    /// One source-visible factory argument bound to a canonical provider.
    /// `parameter` preserves the call-site label independently from the
    /// selected provider identity, and `kind` preserves eager/deferred
    /// construction semantics.
    package struct DependencyBinding: Codable, Hashable, Sendable {
        package let parameter: String
        package let providerID: String
        package let kind: FactoryDependencyKind

        package init(
            parameter: String,
            providerID: String,
            kind: FactoryDependencyKind
        ) {
            self.parameter = parameter
            self.providerID = providerID
            self.kind = kind
        }
    }

    /// Canonical child-input ↔ parent-provider wiring for fixed and assisted
    /// ownership. IDs are target/file-qualified graph IDs rather than display
    /// names, so swapping either endpoint is contractual.
    package struct ContainerBinding: Codable, Hashable, Sendable {
        package let childInputID: String
        package let parentProviderID: String
        package let ownership: Ownership

        package init(
            childInputID: String,
            parentProviderID: String,
            ownership: Ownership
        ) {
            self.childInputID = childInputID
            self.parentProviderID = parentProviderID
            self.ownership = ownership
        }

        package enum Ownership: String, Codable, Hashable, Sendable {
            case fixed
            case assisted
        }
    }

    /// Explicit collection semantics authored at the provider declaration.
    /// Entry order is contractual; keyed forms additionally carry a stable
    /// string key. Contributor lifetime comes from the referenced canonical
    /// provider rather than from an arbitrary collection factory body.
    package struct CollectionContract: Codable, Hashable, Sendable {
        package let kind: Kind
        package let entries: [Entry]

        package init(kind: Kind, entries: [Entry]) {
            self.kind = kind
            self.entries = entries
        }

        package enum Kind: String, Codable, Hashable, Sendable {
            case ordered
            case keyed
            case providers
            case keyedProviders
        }

        package struct Entry: Codable, Hashable, Sendable {
            package let key: String?
            package let order: Int
            package let providerID: String
            package let providerLifetime: Lifetime?

            package init(
                key: String?,
                order: Int,
                providerID: String,
                providerLifetime: Lifetime?
            ) {
                self.key = key
                self.order = order
                self.providerID = providerID
                self.providerLifetime = providerLifetime
            }
        }
    }

    package struct SourceLocation: Hashable, Sendable {
        package let path: String
        package let line: Int
        package let column: Int

        package init(path: String, line: Int, column: Int) {
            self.path = path
            self.line = line
            self.column = column
        }
    }
}

package extension DependencyGraphProvider {
    func replacingContainerBindings(
        _ bindings: [ContainerBinding]
    ) -> DependencyGraphProvider {
        DependencyGraphProvider(
            id: id,
            containerID: containerID,
            name: name,
            type: type,
            role: role,
            lifetime: lifetime,
            initialization: initialization,
            isolation: isolation,
            effect: effect,
            inputKind: inputKind,
            dependencies: dependencies,
            dependencyBindings: dependencyBindings,
            containerBindings: bindings,
            collection: collection,
            source: source
        )
    }

    func replacingCollectionContract(
        _ contract: CollectionContract?
    ) -> DependencyGraphProvider {
        DependencyGraphProvider(
            id: id,
            containerID: containerID,
            name: name,
            type: type,
            role: role,
            lifetime: lifetime,
            initialization: initialization,
            isolation: isolation,
            effect: effect,
            inputKind: inputKind,
            dependencies: dependencies,
            dependencyBindings: dependencyBindings,
            containerBindings: containerBindings,
            collection: contract,
            source: source
        )
    }
}

package func normalizeProviders(
    _ providers: [DependencyGraphProvider]
) -> [DependencyGraphProvider] {
    var providersByID: [String: DependencyGraphProvider] = [:]
    for provider in providers.sorted(by: providerCanonicalOrder) {
        providersByID[provider.id] = providersByID[provider.id] ?? provider
    }
    return providersByID.values.sorted(by: providerCanonicalOrder)
}

private func providerCanonicalOrder(
    _ lhs: DependencyGraphProvider,
    _ rhs: DependencyGraphProvider
) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    if lhs.source.path != rhs.source.path {
        return lhs.source.path < rhs.source.path
    }
    if lhs.source.line != rhs.source.line {
        return lhs.source.line < rhs.source.line
    }
    return lhs.source.column < rhs.source.column
}

package struct DependencyGraphEdge: Hashable {
    package let fromID: String
    package let toID: String
    package let label: String?
    /// Soft edges are excluded from global DAG cycle detection and rendered
    /// with a dashed style. They originate from factory parameters typed
    /// `Lazy<T>`, InnoDI's soft-edge escape hatch. The current container
    /// collector does not yet populate member-level edges, so this field is
    /// primarily future-proofing — but renderers and `runDAGValidation`
    /// already respect it so downstream collectors can emit soft edges the
    /// moment they have the information.
    package let isSoft: Bool
    /// Provider edges originate from factory parameters typed `Provider<T>`.
    /// They are also excluded from cycle detection, but rendered
    /// with a dotted style to distinguish "deferred but repeat-callable"
    /// semantics from `Lazy<T>`'s one-shot deferral. Like `isSoft`, the
    /// container collector does not yet emit member-level provider edges, but
    /// the plumbing is ready end-to-end.
    package let isProvider: Bool
    /// Ownership edges represent a `@SubContainer` relationship — the parent
    /// container owns (either caches for `.shared` or re-builds for
    /// `.transient`) the child container. Ownership edges participate in
    /// cycle detection as hard edges because child construction happens at
    /// parent-init time, but they are rendered with a distinct style and
    /// "owns" label so reviewers can tell container ownership apart from
    /// regular `.input` wiring.
    package let isOwnership: Bool
    /// Assisted-factory ownership is distinct from fixed `@SubContainer`
    /// ownership in graph schema v6, while remaining a hard ownership edge.
    package let isAssistedFactoryOwnership: Bool
    /// Ordered collection contribution metadata. Contribution edges are
    /// self-edges on the owning container and are excluded from cycle checks.
    package let isContribution: Bool
    package let contributor: String?
    package let order: Int?

    package init(
        fromID: String,
        toID: String,
        label: String?,
        isSoft: Bool = false,
        isProvider: Bool = false,
        isOwnership: Bool = false,
        isAssistedFactoryOwnership: Bool = false,
        isContribution: Bool = false,
        contributor: String? = nil,
        order: Int? = nil
    ) {
        self.fromID = fromID
        self.toID = toID
        self.label = label
        self.isSoft = isSoft
        self.isProvider = isProvider
        self.isOwnership = isOwnership || isAssistedFactoryOwnership
        self.isAssistedFactoryOwnership = isAssistedFactoryOwnership
        self.isContribution = isContribution
        self.contributor = contributor
        self.order = order
    }
}

package func normalizeNodes(_ nodes: [DependencyGraphNode]) -> [DependencyGraphNode] {
    var map: [String: (
        displayName: String,
        semanticPath: String,
        isRoot: Bool,
        validateDAG: Bool,
        inputs: Set<String>,
        assistedInputs: Set<String>
    )] = [:]

    for node in nodes {
        var entry = map[node.id] ?? (
            displayName: node.displayName,
            semanticPath: node.semanticPath,
            isRoot: false,
            validateDAG: true,
            inputs: [],
            assistedInputs: []
        )
        entry.isRoot = entry.isRoot || node.isRoot
        entry.validateDAG = entry.validateDAG && node.validateDAG
        entry.inputs.formUnion(node.requiredInputs)
        entry.assistedInputs.formUnion(node.assistedInputs)

        if entry.displayName.isEmpty {
            entry.displayName = node.displayName
        }
        if entry.semanticPath.isEmpty {
            entry.semanticPath = node.semanticPath
        }

        map[node.id] = entry
    }

    return map.keys.sorted().map { id in
        let entry = map[id]!
        return DependencyGraphNode(
            id: id,
            displayName: entry.displayName,
            semanticPath: entry.semanticPath,
            isRoot: entry.isRoot,
            validateDAG: entry.validateDAG,
            requiredInputs: entry.inputs.sorted(),
            assistedInputs: entry.assistedInputs.sorted()
        )
    }
}

/// Builds a DFS adjacency list for global DAG cycle detection.
///
/// Deferred edges are intentionally excluded: `isSoft` (`Lazy<T>`) resolves
/// a one-shot value after construction, and `isProvider` (`Provider<T>`)
/// resolves a fresh transient on every call. Both
/// kinds participate in rendering but not in cycle detection, matching the
/// per-container validator's hard-only DFS.
///
/// Ownership edges stay hard even if a merged edge still carries deferred
/// flags from upstream callers — parent-owned child construction happens at
/// init time, so ownership must participate in cycle detection.
///
/// The returned adjacency includes every input node as a key (empty list if
/// it has no outgoing hard edges) so callers can reason about isolated nodes
/// uniformly.
package func buildCycleDetectionAdjacency(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) -> [String: [String]] {
    var adjacency: [String: [String]] = [:]
    for node in nodes {
        adjacency[node.id] = []
    }
    for edge in edges where !edge.isContribution
        && (edge.isOwnership || (!edge.isSoft && !edge.isProvider)) {
        adjacency[edge.fromID, default: []].append(edge.toID)
    }
    return adjacency
}

package func deduplicateEdges(_ edges: [DependencyGraphEdge]) -> [DependencyGraphEdge] {
    struct EdgeKey: Hashable {
        let fromID: String
        let toID: String
        let label: String?
        let contributor: String?
        let order: Int?
    }

    func normalizedEdge(
        fromID: String,
        toID: String,
        label: String?,
        isSoft: Bool,
        isProvider: Bool,
        isOwnership: Bool,
        isAssistedFactoryOwnership: Bool,
        isContribution: Bool,
        contributor: String?,
        order: Int?
    ) -> DependencyGraphEdge {
        let effectiveIsContribution = isContribution
        let effectiveIsAssistedFactoryOwnership =
            !effectiveIsContribution && isAssistedFactoryOwnership
        let effectiveIsOwnership = !effectiveIsContribution
            && (isOwnership || effectiveIsAssistedFactoryOwnership)
        let effectiveIsSoft = effectiveIsOwnership || effectiveIsContribution
            ? false : isSoft
        let effectiveIsProvider = effectiveIsOwnership
            || effectiveIsContribution ? false : isProvider
        return DependencyGraphEdge(
            fromID: fromID,
            toID: toID,
            label: label,
            isSoft: effectiveIsSoft,
            isProvider: effectiveIsProvider,
            isOwnership: effectiveIsOwnership,
            isAssistedFactoryOwnership:
                effectiveIsAssistedFactoryOwnership,
            isContribution: effectiveIsContribution,
            contributor: contributor,
            order: order
        )
    }

    // Stable: first occurrence wins position. When the same (from, to, label)
    // edge is reported multiple times, the merged edge is `isSoft` only if
    // *every* reporting site said so — any hard occurrence demotes the merge
    // to hard. The same rule applies to `isProvider` and `isOwnership`.
    // When sites disagree about deferred kind (one soft, one provider) we
    // collapse deferred-ness to hard. Ownership also dominates deferred
    // flags: if the merged edge is still ownership, it must be treated as a
    // hard edge for cycle detection.
    var seen: [EdgeKey: Int] = [:]
    var result: [DependencyGraphEdge] = []

    for edge in edges {
        let key = EdgeKey(
            fromID: edge.fromID,
            toID: edge.toID,
            label: edge.label,
            contributor: edge.contributor,
            order: edge.order
        )
        if let existingIndex = seen[key] {
            let existing = result[existingIndex]
            let mergedIsSoft = existing.isSoft && edge.isSoft
            let mergedIsProvider = existing.isProvider && edge.isProvider
            let mergedIsOwnership = existing.isOwnership && edge.isOwnership
            let mergedIsAssistedFactoryOwnership =
                existing.isAssistedFactoryOwnership
                && edge.isAssistedFactoryOwnership
            let mergedIsContribution = existing.isContribution
                && edge.isContribution
            // If one occurrence is soft and another is provider, they are
            // different deferred wrappers at different sites — demote to hard.
            let deferredMismatch = (existing.isSoft && edge.isProvider)
                || (existing.isProvider && edge.isSoft)
            if existing.isSoft != mergedIsSoft
                || existing.isProvider != mergedIsProvider
                || existing.isOwnership != mergedIsOwnership
                || existing.isAssistedFactoryOwnership
                    != mergedIsAssistedFactoryOwnership
                || existing.isContribution != mergedIsContribution
                || deferredMismatch {
                result[existingIndex] = normalizedEdge(
                    fromID: edge.fromID,
                    toID: edge.toID,
                    label: edge.label,
                    isSoft: deferredMismatch ? false : mergedIsSoft,
                    isProvider: deferredMismatch ? false : mergedIsProvider,
                    isOwnership: mergedIsOwnership,
                    isAssistedFactoryOwnership:
                        mergedIsAssistedFactoryOwnership,
                    isContribution: mergedIsContribution,
                    contributor: edge.contributor,
                    order: edge.order
                )
            }
        } else {
            seen[key] = result.count
            result.append(
                normalizedEdge(
                    fromID: edge.fromID,
                    toID: edge.toID,
                    label: edge.label,
                    isSoft: edge.isSoft,
                    isProvider: edge.isProvider,
                    isOwnership: edge.isOwnership,
                    isAssistedFactoryOwnership:
                        edge.isAssistedFactoryOwnership,
                    isContribution: edge.isContribution,
                    contributor: edge.contributor,
                    order: edge.order
                )
            )
        }
    }

    return result
}
