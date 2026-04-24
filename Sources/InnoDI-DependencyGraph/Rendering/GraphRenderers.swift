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
        let rawLabel = edge.label
        let effectiveLabel: String?
        // Ownership edges always carry the `owns` word in their Mermaid label
        // so the semantics survive in viewers that don't parse styles. The
        // arrow glyph stays `-->` because Mermaid only exposes three distinct
        // edge shapes (-->, -.->, ==>) which are already taken by hard,
        // soft, and provider edges respectively.
        if edge.isOwnership {
            let ownsLabel = rawLabel.map { "owns: \($0)" } ?? "owns"
            effectiveLabel = "|\(escapeMermaidLabel(ownsLabel))|"
        } else {
            effectiveLabel = rawLabel.map { "|\(escapeMermaidLabel($0))|" }
        }
        let labelText = effectiveLabel ?? ""
        // Deferred edges render with distinct glyphs:
        //   - Soft (`Lazy<T>`):     dashed `-.->`
        //   - Provider (`Provider<T>`): thick  `==>`
        // Hard / ownership edges keep the default `-->`; ownership is
        // distinguished by the forced `owns` label above.
        let arrow: String
        if edge.isProvider {
            arrow = "==>"
        } else if edge.isSoft {
            arrow = "-.->"
        } else {
            arrow = "-->"
        }
        result += "    \(fromAlias) \(arrow)\(labelText) \(toAlias)\n"
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

        // Edge styles per kind:
        //   - Soft (`Lazy<T>`):        style=dashed
        //   - Provider (`Provider<T>`): style=dotted
        //   - Ownership (@SubContainer): style=bold + colored + "owns" label
        // Each kind still renders as an arrow so the dependency remains
        // visible; the style attribute just conveys the semantic category.
        var attributes: [String] = []
        if edge.isOwnership {
            let ownsLabel = edge.label.map { "owns: \($0)" } ?? "owns"
            attributes.append("label=\"\(escapeDOTLabel(ownsLabel))\"")
            attributes.append("style=bold")
            attributes.append("color=\"#1e3a8a\"")
        } else {
            if let label = edge.label {
                attributes.append("label=\"\(escapeDOTLabel(label))\"")
            }
            if edge.isProvider {
                attributes.append("style=dotted")
            } else if edge.isSoft {
                attributes.append("style=dashed")
            }
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
    let hasOwnershipEdge = edges.contains(where: \.isOwnership)
    if hasSoftEdge || hasProviderEdge || hasOwnershipEdge {
        // Legend only appears when at least one non-hard edge is present so
        // the default render stays compact. Each glyph-to-meaning mapping
        // is listed only when that glyph actually appears in the output.
        var legendParts: [String] = ["--> hard dependency"]
        if hasSoftEdge {
            legendParts.append("- -> soft dependency (Lazy<T>)")
        }
        if hasProviderEdge {
            legendParts.append("~~> provider (Provider<T>)")
        }
        if hasOwnershipEdge {
            legendParts.append("#=> ownership (@SubContainer)")
        }
        result += "  Legend: " + legendParts.joined(separator: "    ") + "\n"
    }

    for edge in edges {
        let fromLabel = labelsByID[edge.fromID] ?? edge.fromID
        let toLabel = labelsByID[edge.toID] ?? edge.toID
        // Ownership edges force the `owns` word into the suffix so the
        // semantic is visible even without the legend. Other edge kinds
        // pass through whatever label the author set.
        let labelPart: String
        if edge.isOwnership {
            if let label = edge.label {
                labelPart = ":owns,\(label)"
            } else {
                labelPart = ":owns"
            }
        } else {
            labelPart = edge.label.map { ":\($0)" } ?? ""
        }
        let padding = String(repeating: " ", count: max(0, maxNameLength - fromLabel.count))
        let arrow: String
        if edge.isOwnership {
            arrow = "#=>"
        } else if edge.isProvider {
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
