/// Shared-construction availability with an optional forward-reference policy. This does not classify factory effects,
/// resolve Swift types, or decide which ownership edges belong in a graph.
package struct DependencyAvailabilityIndex: Sendable {
    package enum Kind: Sendable {
        case input
        case synchronousShared
        case asynchronousShared
        case transient
    }

    /// Syntax-independent input, in the macro model's declaration order.
    package struct Member: Sendable {
        package let name: String
        package let kind: Kind

        package init(name: String, kind: Kind) {
            self.name = name
            self.kind = kind
        }
    }

    package enum Status: Equatable, Sendable {
        case available
        case unknown
        case unavailable
    }

    private struct Declarations: Sendable {
        var hasInput = false
        var firstSynchronousShared: Int?
        var firstAsynchronousShared: Int?
    }

    private let kinds: [Kind]
    private let declarationsByName: [String: Declarations]
    package let knownNames: Set<String>

    /// O(N) expected dictionary work and storage. Duplicate names deliberately
    /// retain the old set-union availability semantics during error recovery;
    /// name collision diagnostics are owned by the caller, not this index.
    package init(members: [Member]) {
        var declarationsByName: [String: Declarations] = [:]
        declarationsByName.reserveCapacity(members.count)
        for (index, member) in members.enumerated() {
            var declarations = declarationsByName[member.name] ?? Declarations()
            switch member.kind {
            case .input:
                declarations.hasInput = true
            case .synchronousShared:
                if declarations.firstSynchronousShared == nil {
                    declarations.firstSynchronousShared = index
                }
            case .asynchronousShared:
                if declarations.firstAsynchronousShared == nil {
                    declarations.firstAsynchronousShared = index
                }
            case .transient:
                break
            }
            declarationsByName[member.name] = declarations
        }
        self.kinds = members.map(\.kind)
        self.knownNames = Set(declarationsByName.keys)
        self.declarationsByName = declarationsByName
    }

    /// Expected O(1) lookup, without materializing a set per dependency edge.
    /// Unknown names take precedence even when the consumer index is invalid.
    package func status(
        of name: String,
        forMemberAt index: Int,
        allowForwardSharedReferences: Bool = false
    ) -> Status {
        guard let declarations = declarationsByName[name] else { return .unknown }
        guard kinds.indices.contains(index) else { return .unavailable }
        switch kinds[index] {
        case .input:
            return .unavailable
        case .transient:
            return .available
        case .synchronousShared:
            if declarations.hasInput
                || declarations.firstSynchronousShared.map({ allowForwardSharedReferences || $0 < index }) == true {
                return .available
            }
        case .asynchronousShared:
            if declarations.hasInput
                || declarations.firstSynchronousShared != nil
                || declarations.firstAsynchronousShared.map({ allowForwardSharedReferences || $0 < index }) == true {
                return .available
            }
        }
        return .unavailable
    }

    /// Explicit O(N) materialization for clients that actually need a set.
    /// Individual edge checks must use `status` instead.
    package func availableNames(
        forMemberAt index: Int,
        allowForwardSharedReferences: Bool = false
    ) -> Set<String> {
        guard kinds.indices.contains(index) else { return [] }
        return Set(knownNames.filter {
            status(of: $0, forMemberAt: index,
                   allowForwardSharedReferences: allowForwardSharedReferences) == .available
        })
    }
}
