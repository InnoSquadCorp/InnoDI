import Testing

@testable import InnoDICore

@Suite("Dependency availability index")
struct DependencyAvailabilityIndexTests {
    typealias Member = DependencyAvailabilityIndex.Member
    typealias Kind = DependencyAvailabilityIndex.Kind

    @Test("All small declaration sequences match the original set-based rule")
    func exhaustiveRecoveryParity() {
        let kinds: [Kind] = [.input, .synchronousShared, .asynchronousShared, .transient]
        let choices = ["a", "b"].flatMap { name in
            kinds.map { Member(name: name, kind: $0) }
        }
        // Exhaustively covers ordering and duplicates of every kind, including
        // mixed-kind duplicates which remain possible in invalid source.
        for count in 0...4 {
            var sequenceCount = 1
            for _ in 0..<count { sequenceCount *= choices.count }
            for encoded in 0..<sequenceCount {
                var value = encoded
                var members: [Member] = []
                for _ in 0..<count {
                    members.append(choices[value % choices.count])
                    value /= choices.count
                }
                let index = DependencyAvailabilityIndex(members: members)
                #expect(index.knownNames == Set(members.map(\.name)))
                for consumer in [-1] + Array(0..<count) + [count, Int.max, Int.min] {
                    let expected = referenceAvailableNames(members, at: consumer)
                    #expect(index.availableNames(forMemberAt: consumer) == expected)
                    for name in ["a", "b", "unknown"] {
                        let status: DependencyAvailabilityIndex.Status =
                            !index.knownNames.contains(name) ? .unknown
                            : expected.contains(name) ? .available : .unavailable
                        #expect(index.status(of: name, forMemberAt: consumer) == status)
                    }
                }
            }
        }
    }

    @Test("Async shared sees future sync storage but never future async storage")
    func mixedOrder() {
        let index = DependencyAvailabilityIndex(members: [
            .init(name: "first", kind: .asynchronousShared),
            .init(name: "laterSync", kind: .synchronousShared),
            .init(name: "laterAsync", kind: .asynchronousShared),
            .init(name: "input", kind: .input),
            .init(name: "transient", kind: .transient),
        ])
        #expect(index.availableNames(forMemberAt: 0) == ["laterSync", "input"])
        #expect(index.availableNames(forMemberAt: 1) == ["input"])
        #expect(index.availableNames(forMemberAt: 2) == ["first", "laterSync", "input"])
        #expect(index.availableNames(forMemberAt: 3).isEmpty)
        #expect(index.availableNames(forMemberAt: 4) == index.knownNames)
    }

    /// Deliberately independent reference implementation from the old macro
    /// resolver: set unions over declarations, not the new index's predicates.
    private func referenceAvailableNames(_ members: [Member], at index: Int) -> Set<String> {
        guard members.indices.contains(index) else { return [] }
        switch members[index].kind {
        case .input:
            return []
        case .transient:
            return Set(members.map(\.name))
        case .synchronousShared:
            return Set(members.filter { $0.kind == .input }.map(\.name)).union(
                members[..<index].filter { $0.kind == .synchronousShared }.map(\.name)
            )
        case .asynchronousShared:
            return Set(members.filter { $0.kind == .input }.map(\.name)).union(
                members.filter { $0.kind == .synchronousShared }.map(\.name)
            ).union(members[..<index].filter { $0.kind == .asynchronousShared }.map(\.name))
        }
    }
}
