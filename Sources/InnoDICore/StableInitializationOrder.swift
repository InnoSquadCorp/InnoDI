/// Syntax-free input for one shared-provider construction stage. Dependencies
/// are exact semantic member names; storage-prefix normalization belongs only
/// to the caller's fallback expression resolution, never to ordering edges.
package struct InitializationOrderNode: Sendable {
    package let name: String
    package let hardDependencies: [String]

    package init(name: String, hardDependencies: [String]) {
        self.name = name
        self.hardDependencies = hardDependencies
    }
}

package enum InitializationOrderError: Error, Equatable, Sendable {
    case duplicateName(String)
    case cycle
}

/// Returns original array indices in stable topological construction order.
/// Every ready-set choice uses the smallest original index, including newly
/// ready earlier declarations. Unknown names describe another stage, inputs or
/// unresolved references; their availability is validated by the caller.
///
/// O(E + V log V) expected dictionary/heap work and O(E + V) storage.
package func stableInitializationOrder(_ nodes: [InitializationOrderNode]) throws -> [Int] {
    var indices: [String: Int] = [:]
    indices.reserveCapacity(nodes.count)
    for (index, node) in nodes.enumerated() {
        guard indices.updateValue(index, forKey: node.name) == nil else {
            throw InitializationOrderError.duplicateName(node.name)
        }
    }
    var pendingCounts = Array(repeating: 0, count: nodes.count)
    var consumers = Array(repeating: [Int](), count: nodes.count)
    for (consumer, node) in nodes.enumerated() {
        var seen = Set<String>()
        for dependency in node.hardDependencies where seen.insert(dependency).inserted {
            guard let provider = indices[dependency] else { continue }
            pendingCounts[consumer] += 1
            consumers[provider].append(consumer)
        }
    }
    var ready = InitializationIndexMinHeap()
    for index in nodes.indices where pendingCounts[index] == 0 {
        ready.insert(index)
    }
    var result: [Int] = []
    result.reserveCapacity(nodes.count)
    while let provider = ready.removeMinimum() {
        result.append(provider)
        for consumer in consumers[provider] {
            pendingCounts[consumer] -= 1
            if pendingCounts[consumer] == 0 { ready.insert(consumer) }
        }
    }
    guard result.count == nodes.count else {
        throw InitializationOrderError.cycle
    }
    return result
}

private struct InitializationIndexMinHeap {
    private var values: [Int] = []

    mutating func insert(_ value: Int) {
        values.append(value)
        var index = values.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard values[index] < values[parent] else { break }
            values.swapAt(index, parent)
            index = parent
        }
    }

    mutating func removeMinimum() -> Int? {
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return values.removeLast() }
        let result = values[0]
        values[0] = values.removeLast()
        var index = 0
        while index * 2 + 1 < values.count {
            let left = index * 2 + 1
            let right = left + 1
            let child = right < values.count && values[right] < values[left] ? right : left
            guard values[child] < values[index] else { break }
            values.swapAt(index, child)
            index = child
        }
        return result
    }
}
