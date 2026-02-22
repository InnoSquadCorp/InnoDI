import Testing

@testable import InnoDICore

@Suite("DependencyGraphCore")
struct DependencyGraphCoreTests {
    @Test("Merges duplicate node IDs and propagates root and inputs")
    func normalizeNodesMergesSameIDAndPropagatesMetadata() throws {
        let nodes = [
            DependencyGraphNode(
                id: "App.swift#AppContainer",
                displayName: "AppContainer",
                isRoot: false,
                requiredInputs: ["config"]
            ),
            DependencyGraphNode(
                id: "App.swift#AppContainer",
                displayName: "AppContainer",
                isRoot: true,
                requiredInputs: ["logger", "config"]
            )
        ]

        let normalized = normalizeNodes(nodes)

        try #require(normalized.count == 1)
        #expect(normalized[0].id == "App.swift#AppContainer")
        #expect(normalized[0].isRoot == true)
        #expect(normalized[0].requiredInputs == ["config", "logger"])
    }

    @Test("Keeps same display names separate when node IDs differ")
    func normalizeNodesKeepsSameDisplayNameWithDifferentIDsSeparate() throws {
        let nodes = [
            DependencyGraphNode(
                id: "FeatureA/App.swift#AppContainer",
                displayName: "AppContainer",
                isRoot: false,
                requiredInputs: []
            ),
            DependencyGraphNode(
                id: "FeatureB/App.swift#AppContainer",
                displayName: "AppContainer",
                isRoot: true,
                requiredInputs: ["env"]
            )
        ]

        let normalized = normalizeNodes(nodes)
        let originalByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        #expect(normalized.count == 2)
        #expect(normalized.map(\.id) == [
            "FeatureA/App.swift#AppContainer",
            "FeatureB/App.swift#AppContainer"
        ])

        for item in normalized {
            let original = try #require(originalByID[item.id])
            #expect(item.isRoot == original.isRoot)
            #expect(item.requiredInputs == original.requiredInputs)
        }
    }

    @Test("Normalizes nodes with deterministic ID ordering")
    func normalizeNodesProducesDeterministicIDOrder() {
        let nodes = [
            DependencyGraphNode(id: "z.swift#Z", displayName: "Z", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "a.swift#A", displayName: "A", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "m.swift#M", displayName: "M", isRoot: false, requiredInputs: [])
        ]

        let normalized = normalizeNodes(nodes)

        #expect(normalized.map(\.id) == ["a.swift#A", "m.swift#M", "z.swift#Z"])
    }

    @Test("Deduplicates identical edges while preserving first-seen order")
    func deduplicateEdgesRemovesDuplicatesAndKeepsFirstSeenOrder() throws {
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil),
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil),
            DependencyGraphEdge(fromID: "A", toID: "B", label: "client"),
            DependencyGraphEdge(fromID: "A", toID: "B", label: "client"),
            DependencyGraphEdge(fromID: "B", toID: "C", label: nil)
        ]

        let deduplicated = deduplicateEdges(edges)

        try #require(deduplicated.count == 3)
        #expect(deduplicated[0].fromID == "A")
        #expect(deduplicated[0].toID == "B")
        #expect(deduplicated[0].label == nil)

        #expect(deduplicated[1].fromID == "A")
        #expect(deduplicated[1].toID == "B")
        #expect(deduplicated[1].label == "client")

        #expect(deduplicated[2].fromID == "B")
        #expect(deduplicated[2].toID == "C")
        #expect(deduplicated[2].label == nil)
    }
}
