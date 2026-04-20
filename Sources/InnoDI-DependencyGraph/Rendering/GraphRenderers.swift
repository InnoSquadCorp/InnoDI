import InnoDICore

func renderMermaid(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) -> String {
    let aliases = nodeAliases(nodes: nodes)
    let duplicateDisplayNames = duplicateDisplayNameSet(nodes: nodes)

    var result = "graph TD\n"
    for node in nodes {
        guard let alias = aliases[node.id] else { continue }
        var label = displayLabel(for: node, duplicateDisplayNames: duplicateDisplayNames)
        if node.isRoot {
            label += " [root]"
        }
        result += "    \(alias)[\"\(escapeMermaidLabel(label))\"]\n"
    }

    for edge in edges {
        guard let fromAlias = aliases[edge.fromID],
              let toAlias = aliases[edge.toID] else {
            continue
        }
        let label = edge.label.map { "|\(escapeMermaidLabel($0))|" } ?? ""
        // Deferred edges render with distinct glyphs:
        //   - Soft (`Lazy<T>`, Phase K):     dashed `-.->`
        //   - Provider (`Provider<T>`, L):   thick  `==>`
        // Hard edges keep the default `-->`. All three are visually
        // distinguishable so reviewers can see at a glance which dependencies
        // defer resolution.
        let arrow: String
        if edge.isProvider {
            arrow = "==>"
        } else if edge.isSoft {
            arrow = "-.->"
        } else {
            arrow = "-->"
        }
        result += "    \(fromAlias) \(arrow)\(label) \(toAlias)\n"
    }

    result += "\n"
    return result
}

func renderDOT(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) -> String {
    let aliases = nodeAliases(nodes: nodes)
    let duplicateDisplayNames = duplicateDisplayNameSet(nodes: nodes)

    var result = "digraph InnoDI {\n"
    result += "  rankdir=TB;\n"
    result += "\n"
    result += "  // Nodes\n"

    for node in nodes {
        guard let alias = aliases[node.id] else { continue }
        let fill = node.isRoot ? "#e1f5fe" : "#e5e7eb"
        let label = escapeDOTLabel(displayLabel(for: node, duplicateDisplayNames: duplicateDisplayNames))
        result += "  \"\(alias)\" [label=\"\(label)\", shape=box, style=\"rounded,filled\", fillcolor=\"\(fill)\"];\n"
    }

    result += "\n"
    result += "  // Edges\n"

    for edge in edges {
        guard let fromAlias = aliases[edge.fromID],
              let toAlias = aliases[edge.toID] else {
            continue
        }

        // Deferred edges get distinct DOT styles:
        //   - Soft (`Lazy<T>`):       `style=dashed`
        //   - Provider (`Provider<T>`): `style=dotted`
        // Both still render as arrows so the dependency remains visible.
        var attributes: [String] = []
        if let label = edge.label {
            attributes.append("label=\"\(escapeDOTLabel(label))\"")
        }
        if edge.isProvider {
            attributes.append("style=dotted")
        } else if edge.isSoft {
            attributes.append("style=dashed")
        }

        if attributes.isEmpty {
            result += "  \"\(fromAlias)\" -> \"\(toAlias)\";\n"
        } else {
            result += "  \"\(fromAlias)\" -> \"\(toAlias)\" [\(attributes.joined(separator: ", "))];\n"
        }
    }

    result += "}\n"
    return result
}

func renderASCII(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) -> String {
    let duplicateDisplayNames = duplicateDisplayNameSet(nodes: nodes)
    let labelsByID = Dictionary(uniqueKeysWithValues: nodes.map {
        ($0.id, displayLabel(for: $0, duplicateDisplayNames: duplicateDisplayNames))
    })

    let maxNameLength = labelsByID.values.map(\.count).max() ?? 10

    var result = "InnoDI Dependency Graph\n"
    result += String(repeating: "=", count: maxNameLength + 15) + "\n"
    result += "Nodes:\n"

    for node in nodes {
        let label = labelsByID[node.id] ?? node.id
        let padding = String(repeating: " ", count: max(0, maxNameLength - label.count))
        let rootSuffix = node.isRoot ? " [ROOT]" : ""
        let inputs = node.requiredInputs.isEmpty ? "" : " (inputs: \(node.requiredInputs.joined(separator: ", ")))"
        result += "  \(label)\(padding)\(rootSuffix)\(inputs)\n"
    }

    result += "\n"
    result += "Edges:\n"

    let hasSoftEdge = edges.contains(where: \.isSoft)
    let hasProviderEdge = edges.contains(where: \.isProvider)
    if hasSoftEdge || hasProviderEdge {
        // Legend only appears when at least one deferred edge is present so
        // the default render stays compact. Each glyph-to-meaning mapping
        // is listed only when that glyph actually appears in the output.
        var legendParts: [String] = ["--> hard dependency"]
        if hasSoftEdge {
            legendParts.append("- -> soft dependency (Lazy<T>)")
        }
        if hasProviderEdge {
            legendParts.append("~~> provider (Provider<T>)")
        }
        result += "  Legend: " + legendParts.joined(separator: "    ") + "\n"
    }

    for edge in edges {
        let fromLabel = labelsByID[edge.fromID] ?? edge.fromID
        let toLabel = labelsByID[edge.toID] ?? edge.toID
        let labelPart = edge.label.map { ":\($0)" } ?? ""
        let padding = String(repeating: " ", count: max(0, maxNameLength - fromLabel.count))
        let arrow: String
        if edge.isProvider {
            arrow = "~~>"
        } else if edge.isSoft {
            arrow = "- ->"
        } else {
            arrow = "-->"
        }
        result += "  \(padding)\(fromLabel) \(arrow) \(toLabel)\(labelPart)\n"
    }

    return result
}

private func nodeAliases(nodes: [DependencyGraphNode]) -> [String: String] {
    var aliases: [String: String] = [:]
    for (index, node) in nodes.enumerated() {
        aliases[node.id] = "N\(index)"
    }
    return aliases
}

private func duplicateDisplayNameSet(nodes: [DependencyGraphNode]) -> Set<String> {
    var counts: [String: Int] = [:]
    for node in nodes {
        counts[node.displayName, default: 0] += 1
    }
    return Set(counts.compactMap { name, count in count > 1 ? name : nil })
}

private func displayLabel(for node: DependencyGraphNode, duplicateDisplayNames: Set<String>) -> String {
    if duplicateDisplayNames.contains(node.displayName) {
        return "\(node.displayName) (\(node.id))"
    }
    return node.displayName
}

private func escapeMermaidLabel(_ label: String) -> String {
    label
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "|", with: "\\|")
}

private func escapeDOTLabel(_ label: String) -> String {
    label
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
