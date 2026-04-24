import Testing

@testable import InnoDICore

/// Covers the `isSoft` plumbing for the CLI DAG validator.
///
/// The macro-level validator and the CLI validator must agree: a cycle that is
/// broken by a single `Lazy<T>` edge on any path should not be reported as a
/// cycle. These tests target the pure adjacency/dedup helpers shared between
/// them so the contract stays verified even while the CLI collectors don't yet
/// populate member-level edges.
@Suite("Soft edge cycle filter")
struct SoftEdgeCycleFilterTests {
    private func makeNode(_ id: String) -> DependencyGraphNode {
        DependencyGraphNode(
            id: id,
            displayName: id,
            semanticPath: id,
            isRoot: false,
            requiredInputs: []
        )
    }

    @Test("Soft edges are excluded from cycle-detection adjacency")
    func softEdgesAreExcludedFromAdjacency() {
        let nodes = [makeNode("A"), makeNode("B")]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false),
            DependencyGraphEdge(fromID: "B", toID: "A", label: nil, isSoft: true)
        ]

        let adjacency = buildCycleDetectionAdjacency(nodes: nodes, edges: edges)

        #expect(adjacency["A"] == ["B"])
        #expect(adjacency["B"] == [])
        #expect(detectDependencyCycles(adjacency: adjacency).isEmpty)
    }

    @Test("Hard back-edge still forms a cycle even when a soft edge co-exists")
    func hardBackEdgeStillCycles() {
        let nodes = [makeNode("A"), makeNode("B")]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false),
            DependencyGraphEdge(fromID: "B", toID: "A", label: nil, isSoft: false),
            // A redundant soft edge in the same direction must not "launder"
            // the hard edge out of cycle detection.
            DependencyGraphEdge(fromID: "B", toID: "A", label: nil, isSoft: true)
        ]

        let adjacency = buildCycleDetectionAdjacency(nodes: nodes, edges: edges)
        let cycles = detectDependencyCycles(adjacency: adjacency)

        #expect(!cycles.isEmpty)
    }

    @Test("Three-node cycle broken by one soft edge no longer cycles")
    func threeNodeCycleBrokenBySoftEdge() {
        let nodes = [makeNode("A"), makeNode("B"), makeNode("C")]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "C", label: nil, isSoft: true),
            DependencyGraphEdge(fromID: "B", toID: "A", label: nil, isSoft: false),
            DependencyGraphEdge(fromID: "C", toID: "B", label: nil, isSoft: false)
        ]

        let adjacency = buildCycleDetectionAdjacency(nodes: nodes, edges: edges)
        let cycles = detectDependencyCycles(adjacency: adjacency)

        #expect(cycles.isEmpty)
    }

    @Test("Isolated nodes remain in adjacency with empty successor lists")
    func isolatedNodesRemainInAdjacency() {
        let nodes = [makeNode("A"), makeNode("B"), makeNode("Isolated")]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false)
        ]

        let adjacency = buildCycleDetectionAdjacency(nodes: nodes, edges: edges)

        #expect(adjacency.keys.sorted() == ["A", "B", "Isolated"])
        #expect(adjacency["Isolated"] == [])
    }

    @Test("Hard occurrence demotes prior soft merge in deduplicateEdges")
    func hardOccurrenceDemotesPriorSoftMerge() {
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: true),
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 1)
        #expect(deduped[0].isSoft == false)
    }

    @Test("All-soft occurrences keep the merged edge soft")
    func allSoftOccurrencesStaySoft() {
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: true),
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: true)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 1)
        #expect(deduped[0].isSoft == true)
    }

    @Test("Different labels produce separate edges even with same endpoints")
    func differentLabelsProduceSeparateEdges() {
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: "x", isSoft: true),
            DependencyGraphEdge(fromID: "A", toID: "B", label: "y", isSoft: false)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 2)
        #expect(deduped.contains(where: { $0.label == "x" && $0.isSoft }))
        #expect(deduped.contains(where: { $0.label == "y" && !$0.isSoft }))
    }

    // MARK: - Provider edges

    @Test("Provider edges are excluded from cycle-detection adjacency")
    func providerEdgesAreExcludedFromAdjacency() {
        let nodes = [makeNode("A"), makeNode("B")]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false),
            DependencyGraphEdge(fromID: "B", toID: "A", label: nil, isSoft: false, isProvider: true)
        ]

        let adjacency = buildCycleDetectionAdjacency(nodes: nodes, edges: edges)

        #expect(adjacency["A"] == ["B"])
        #expect(adjacency["B"] == [])
        #expect(detectDependencyCycles(adjacency: adjacency).isEmpty)
    }

    @Test("Three-node cycle broken by one provider edge no longer cycles")
    func threeNodeCycleBrokenByProviderEdge() {
        let nodes = [makeNode("A"), makeNode("B"), makeNode("C")]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "C", label: nil, isSoft: false, isProvider: true),
            DependencyGraphEdge(fromID: "B", toID: "A", label: nil, isSoft: false),
            DependencyGraphEdge(fromID: "C", toID: "B", label: nil, isSoft: false)
        ]

        let adjacency = buildCycleDetectionAdjacency(nodes: nodes, edges: edges)

        #expect(detectDependencyCycles(adjacency: adjacency).isEmpty)
    }

    @Test("Provider-only occurrences keep the merged edge as provider")
    func providerOnlyOccurrencesStayProvider() {
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false, isProvider: true),
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false, isProvider: true)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 1)
        #expect(deduped[0].isProvider)
        #expect(!deduped[0].isSoft)
    }

    @Test("Hard occurrence demotes a prior provider merge")
    func hardOccurrenceDemotesPriorProviderMerge() {
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false, isProvider: true),
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false, isProvider: false)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 1)
        #expect(!deduped[0].isProvider)
        #expect(!deduped[0].isSoft)
    }

    @Test("Soft and provider occurrences on the same edge collapse to hard")
    func softProviderMismatchDemotesToHard() {
        // Different call sites reporting the same (from, to, label) with
        // conflicting deferred-kind metadata should collapse to hard — we
        // cannot prove the deferral is consistent across every path.
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: true, isProvider: false),
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: false, isProvider: true)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 1)
        #expect(!deduped[0].isSoft)
        #expect(!deduped[0].isProvider)
    }

    // MARK: - Ownership edges

    @Test("Ownership edges participate in cycle detection as hard edges")
    func ownershipEdgesCountAsHard() {
        // `@SubContainer` construction happens at parent init — a parent ↔
        // child loop would loop during init, so ownership stays hard.
        let nodes = [makeNode("Parent"), makeNode("Child")]
        let edges = [
            DependencyGraphEdge(fromID: "Parent", toID: "Child", label: "feature", isOwnership: true),
            DependencyGraphEdge(fromID: "Child", toID: "Parent", label: nil)
        ]

        let adjacency = buildCycleDetectionAdjacency(nodes: nodes, edges: edges)

        #expect(adjacency["Parent"] == ["Child"])
        #expect(adjacency["Child"] == ["Parent"])
        #expect(!detectDependencyCycles(adjacency: adjacency).isEmpty)
    }

    @Test("Ownership-only occurrences keep the merged edge as ownership")
    func ownershipOnlyOccurrencesStayOwnership() {
        let edges = [
            DependencyGraphEdge(fromID: "Parent", toID: "Child", label: "feature", isOwnership: true),
            DependencyGraphEdge(fromID: "Parent", toID: "Child", label: "feature", isOwnership: true)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 1)
        #expect(deduped[0].isOwnership)
    }

    @Test("A plain hard occurrence demotes a prior ownership merge")
    func hardOccurrenceDemotesPriorOwnershipMerge() {
        let edges = [
            DependencyGraphEdge(fromID: "Parent", toID: "Child", label: "feature", isOwnership: true),
            DependencyGraphEdge(fromID: "Parent", toID: "Child", label: "feature", isOwnership: false)
        ]

        let deduped = deduplicateEdges(edges)

        #expect(deduped.count == 1)
        #expect(!deduped[0].isOwnership)
    }

    @Test("Ownership edges stay hard through dedup and cycle detection even when deferred flags are present")
    func ownershipEdgesDominateDeferredFlags() {
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: true, isProvider: false, isOwnership: true),
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: true, isProvider: false, isOwnership: true)
        ]

        let deduped = deduplicateEdges(edges)
        let adjacency = buildCycleDetectionAdjacency(
            nodes: [makeNode("A"), makeNode("B")],
            edges: deduped + [DependencyGraphEdge(fromID: "B", toID: "A", label: nil)]
        )

        #expect(deduped.count == 1)
        #expect(deduped[0].isOwnership)
        #expect(!deduped[0].isSoft)
        #expect(!deduped[0].isProvider)
        #expect(adjacency["A"] == ["B"])
        #expect(!detectDependencyCycles(adjacency: adjacency).isEmpty)
    }
}
