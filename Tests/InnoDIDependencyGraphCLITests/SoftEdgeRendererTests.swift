import Foundation
import InnoDICore
import Testing

@testable import InnoDI_DependencyGraph

/// Verifies the renderer styling added in Phase K-5 for soft edges.
///
/// These tests bypass the CLI pipeline and call the render functions directly
/// with a synthetic graph containing both hard and soft edges. The
/// end-to-end CLI snapshot tests (`GraphRendererSnapshotTests`) continue to
/// cover the full pipeline with a hard-edge-only fixture — the collector
/// does not yet populate member-level soft edges, so soft-edge regressions
/// have to be exercised at the renderer boundary for now.
@Suite("Soft edge renderer styling (Phase K-5)")
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
}
