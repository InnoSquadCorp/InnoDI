import Foundation
import InnoDICore
import InnoDIDependencyGraphCore
import Testing

/// Verifies the renderer styling for soft edges.
///
/// These tests bypass the CLI pipeline and call the render functions directly
/// with a synthetic graph containing both hard and deferred edges. The
/// end-to-end CLI integration tests cover real collector plumbing
/// separately; these tests keep renderer-specific regressions localized and
/// easy to read.
@Suite("Soft edge renderer styling")
struct SoftEdgeRendererTests {
    private func makeGraph() -> ([DependencyGraphNode], [DependencyGraphEdge]) {
        let nodes = [
            DependencyGraphNode(
                id: "CoordinatorA",
                displayName: "CoordinatorA",
                semanticPath: "CoordinatorA",
                isRoot: false,
                requiredInputs: []
            ),
            DependencyGraphNode(
                id: "CoordinatorB",
                displayName: "CoordinatorB",
                semanticPath: "CoordinatorB",
                isRoot: false,
                requiredInputs: []
            )
        ]
        let edges = [
            DependencyGraphEdge(fromID: "CoordinatorA", toID: "CoordinatorB", label: nil, isSoft: false),
            DependencyGraphEdge(fromID: "CoordinatorB", toID: "CoordinatorA", label: nil, isSoft: true)
        ]
        return (nodes, edges)
    }

    @Test("Mermaid renders soft edges with the `-.->` arrow glyph")
    func mermaidSoftEdgeGlyph() {
        let (nodes, edges) = makeGraph()
        let output = renderMermaid(nodes: nodes, edges: edges)

        // Hard edge keeps the standard `-->`.
        #expect(output.contains("N0 --> N1"))
        // Soft edge uses the Mermaid dashed-arrow syntax.
        #expect(output.contains("N1 -.-> N0"))
    }

    @Test("DOT renders soft edges with style=dashed attribute")
    func dotSoftEdgeAttribute() {
        let (nodes, edges) = makeGraph()
        let output = renderDOT(nodes: nodes, edges: edges)

        // Hard edge has no attribute block.
        #expect(output.contains("\"N0\" -> \"N1\";"))
        // Soft edge gains the `style=dashed` attribute.
        #expect(output.contains("\"N1\" -> \"N0\" [style=dashed];"))
    }

    @Test("ASCII renders soft edges with `- ->` glyph and a legend")
    func asciiSoftEdgeGlyphAndLegend() {
        let (nodes, edges) = makeGraph()
        let output = renderASCII(nodes: nodes, edges: edges)

        #expect(output.contains("CoordinatorA --> CoordinatorB"))
        #expect(output.contains("CoordinatorB - -> CoordinatorA"))
        // Legend only appears when at least one soft edge exists.
        #expect(output.contains("Legend: --> hard dependency    - -> soft dependency (Lazy<T>)"))
    }

    @Test("ASCII legend is omitted when no soft edges exist")
    func asciiLegendOmittedWithoutSoftEdges() {
        let (nodes, _) = makeGraph()
        let hardOnlyEdges = [
            DependencyGraphEdge(fromID: "CoordinatorA", toID: "CoordinatorB", label: nil, isSoft: false)
        ]
        let output = renderASCII(nodes: nodes, edges: hardOnlyEdges)

        #expect(!output.contains("Legend:"))
        #expect(output.contains("CoordinatorA --> CoordinatorB"))
    }

    @Test("Mermaid preserves labels on soft edges")
    func mermaidSoftEdgeWithLabel() {
        let (nodes, _) = makeGraph()
        let labeledEdges = [
            DependencyGraphEdge(fromID: "CoordinatorA", toID: "CoordinatorB", label: "lazy", isSoft: true)
        ]
        let output = renderMermaid(nodes: nodes, edges: labeledEdges)

        #expect(output.contains("N0 -.->|lazy| N1"))
    }

    @Test("DOT combines label and style=dashed attributes for soft edges")
    func dotSoftEdgeWithLabel() {
        let (nodes, _) = makeGraph()
        let labeledEdges = [
            DependencyGraphEdge(fromID: "CoordinatorA", toID: "CoordinatorB", label: "lazy", isSoft: true)
        ]
        let output = renderDOT(nodes: nodes, edges: labeledEdges)

        #expect(output.contains("\"N0\" -> \"N1\" [label=\"lazy\", style=dashed];"))
    }

    // MARK: - Provider edges

    private func makeProviderGraph() -> ([DependencyGraphNode], [DependencyGraphEdge]) {
        let nodes = [
            DependencyGraphNode(id: "Logger", displayName: "Logger", semanticPath: "Logger", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "Request", displayName: "Request", semanticPath: "Request", isRoot: false, requiredInputs: [])
        ]
        let edges = [
            DependencyGraphEdge(fromID: "Logger", toID: "Request", label: nil, isSoft: false, isProvider: true)
        ]
        return (nodes, edges)
    }

    @Test("Mermaid renders provider edges with the `==>` thick-arrow glyph")
    func mermaidProviderEdgeGlyph() {
        let (nodes, edges) = makeProviderGraph()
        let output = renderMermaid(nodes: nodes, edges: edges)

        #expect(output.contains("N0 ==> N1"))
        #expect(!output.contains("N0 -.-> N1"))
    }

    @Test("DOT renders provider edges with style=dotted attribute")
    func dotProviderEdgeAttribute() {
        let (nodes, edges) = makeProviderGraph()
        let output = renderDOT(nodes: nodes, edges: edges)

        #expect(output.contains("\"N0\" -> \"N1\" [style=dotted];"))
    }

    @Test("ASCII renders provider edges with `~~>` glyph and extended legend")
    func asciiProviderEdgeGlyphAndLegend() {
        let (nodes, edges) = makeProviderGraph()
        let output = renderASCII(nodes: nodes, edges: edges)

        #expect(output.contains("Logger ~~> Request"))
        #expect(output.contains("Legend: --> hard dependency"))
        #expect(output.contains("~~> provider (Provider<T>)"))
        // Soft legend clause should NOT appear when there are no soft edges.
        #expect(!output.contains("- -> soft dependency"))
    }

    @Test("ASCII legend lists both soft and provider clauses when both are present")
    func asciiLegendListsBothDeferredClauses() {
        let nodes = [
            DependencyGraphNode(id: "A", displayName: "A", semanticPath: "A", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "B", displayName: "B", semanticPath: "B", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "C", displayName: "C", semanticPath: "C", isRoot: false, requiredInputs: [])
        ]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil, isSoft: true),
            DependencyGraphEdge(fromID: "A", toID: "C", label: nil, isSoft: false, isProvider: true)
        ]

        let output = renderASCII(nodes: nodes, edges: edges)

        #expect(output.contains("A - -> B"))
        #expect(output.contains("A ~~> C"))
        #expect(output.contains("- -> soft dependency (Lazy<T>)"))
        #expect(output.contains("~~> provider (Provider<T>)"))
    }

    @Test("Mermaid preserves labels on provider edges")
    func mermaidProviderEdgeWithLabel() {
        let (nodes, _) = makeProviderGraph()
        let labeledEdges = [
            DependencyGraphEdge(fromID: "Logger", toID: "Request", label: "provider", isSoft: false, isProvider: true)
        ]
        let output = renderMermaid(nodes: nodes, edges: labeledEdges)

        #expect(output.contains("N0 ==>|provider| N1"))
    }

    @Test("DOT combines label and style=dotted attributes for provider edges")
    func dotProviderEdgeWithLabel() {
        let (nodes, _) = makeProviderGraph()
        let labeledEdges = [
            DependencyGraphEdge(fromID: "Logger", toID: "Request", label: "provider", isSoft: false, isProvider: true)
        ]
        let output = renderDOT(nodes: nodes, edges: labeledEdges)

        #expect(output.contains("\"N0\" -> \"N1\" [label=\"provider\", style=dotted];"))
    }

    // MARK: - Ownership edges

    private func makeOwnershipGraph() -> ([DependencyGraphNode], [DependencyGraphEdge]) {
        let nodes = [
            DependencyGraphNode(id: "AppContainer", displayName: "AppContainer", semanticPath: "AppContainer", isRoot: true, requiredInputs: []),
            DependencyGraphNode(id: "FeatureContainer", displayName: "FeatureContainer", semanticPath: "FeatureContainer", isRoot: false, requiredInputs: [])
        ]
        let edges = [
            DependencyGraphEdge(fromID: "AppContainer", toID: "FeatureContainer", label: "feature", isOwnership: true)
        ]
        return (nodes, edges)
    }

    @Test("Mermaid forces an `owns` label on ownership edges")
    func mermaidOwnershipEdgeLabel() {
        let (nodes, edges) = makeOwnershipGraph()
        let output = renderMermaid(nodes: nodes, edges: edges)

        // Mermaid has no fourth distinct arrow glyph, so the semantic is
        // carried by the label. The prefix `owns: ` comes before the
        // author-supplied member name (`feature`).
        #expect(output.contains("N0 -->|owns: feature| N1"))
    }

    @Test("DOT renders ownership edges with style=bold + navy color + owns label")
    func dotOwnershipEdgeAttribute() {
        let (nodes, edges) = makeOwnershipGraph()
        let output = renderDOT(nodes: nodes, edges: edges)

        #expect(output.contains("\"N0\" -> \"N1\" [label=\"owns: feature\", style=bold, color=\"#1e3a8a\"];"))
    }

    @Test("ASCII renders ownership edges with `#=>` glyph, owns suffix, and legend")
    func asciiOwnershipEdgeGlyphAndLegend() {
        let (nodes, edges) = makeOwnershipGraph()
        let output = renderASCII(nodes: nodes, edges: edges)

        #expect(output.contains("AppContainer #=> FeatureContainer:owns,feature"))
        #expect(output.contains("Legend: --> hard dependency"))
        #expect(output.contains("#=> ownership (@SubContainer)"))
        // Deferred-edge legend clauses should NOT appear without soft/provider edges.
        #expect(!output.contains("- -> soft dependency"))
        #expect(!output.contains("~~> provider"))
    }

    @Test("ASCII legend combines every edge kind when all four are present")
    func asciiLegendCombinesEveryEdgeKind() {
        let nodes = [
            DependencyGraphNode(id: "A", displayName: "A", semanticPath: "A", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "B", displayName: "B", semanticPath: "B", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "C", displayName: "C", semanticPath: "C", isRoot: false, requiredInputs: []),
            DependencyGraphNode(id: "D", displayName: "D", semanticPath: "D", isRoot: false, requiredInputs: [])
        ]
        let edges = [
            DependencyGraphEdge(fromID: "A", toID: "B", label: nil),
            DependencyGraphEdge(fromID: "A", toID: "C", label: nil, isSoft: true),
            DependencyGraphEdge(fromID: "A", toID: "D", label: nil, isSoft: false, isProvider: true),
            DependencyGraphEdge(fromID: "A", toID: "B", label: "child", isOwnership: true)
        ]

        let output = renderASCII(nodes: nodes, edges: edges)

        #expect(output.contains("--> hard dependency"))
        #expect(output.contains("- -> soft dependency (Lazy<T>)"))
        #expect(output.contains("~~> provider (Provider<T>)"))
        #expect(output.contains("#=> ownership (@SubContainer)"))
    }
}
