import SwiftSyntax

/// Availability state for one dependency name at a specific declaration index.
///
/// `unknown` means the container never declares the name, while `unavailable`
/// means the name exists but declaration-order or scope rules prevent it from
/// being injected at the current member.
enum DependencyReferenceStatus {
    case available
    case unknown
    case unavailable
}

/// Shared declaration-order resolver used by macro diagnostics and graph
/// collection.
///
/// This type is the source of truth for which dependencies are injectable at a
/// given member index. Fix-it suggestions, unknown/unavailable diagnostics, and
/// graph edge extraction all route through the same availability matrix so
/// diagnostics never suggest names that the generated container cannot legally
/// reference.
struct DependencyResolutionContext {
    let members: [ProvideMemberModel]
    let knownNames: Set<String>

    init(members: [ProvideMemberModel]) {
        self.members = members
        self.knownNames = Set(members.map(\.name))
    }

    /// Returns the dependency names that are injectable at `index`.
    ///
    /// `.shared` members follow declaration-order rules, async shared members
    /// can also see earlier async shared dependencies plus all sync shared
    /// dependencies, and `.transient` members can reference any known name.
    func availableNames(forMemberAt index: Int) -> Set<String> {
        guard members.indices.contains(index) else { return [] }
        let member = members[index]

        switch member.scope {
        case .input:
            return []
        case .shared:
            let inputNames = Set(members.lazy.filter { $0.scope == .input }.map(\.name))
            let syncSharedNames = Set(
                members[..<index]
                    .lazy
                    .filter { $0.scope == .shared && !$0.isAsyncFactory }
                    .map(\.name)
            )

            if member.isAsyncFactory {
                let allSyncSharedNames = Set(
                    members.lazy.filter { $0.scope == .shared && !$0.isAsyncFactory }.map(\.name)
                )
                let priorAsyncSharedNames = Set(
                    members[..<index]
                        .lazy
                        .filter { $0.scope == .shared && $0.isAsyncFactory }
                        .map(\.name)
                )
                return inputNames
                    .union(allSyncSharedNames)
                    .union(priorAsyncSharedNames)
            }

            return inputNames.union(syncSharedNames)
        case .transient:
            return knownNames
        }
    }

    /// Classifies a dependency reference using the same declaration-order rules
    /// as container validation.
    func status(of dependencyName: String, forMemberAt index: Int) -> DependencyReferenceStatus {
        guard knownNames.contains(dependencyName) else {
            return .unknown
        }

        if availableNames(forMemberAt: index).contains(dependencyName) {
            return .available
        }

        return .unavailable
    }

    /// Graph edges that are both declared and currently injectable.
    func graphDependencies(forMemberAt index: Int) -> [String] {
        guard members.indices.contains(index) else { return [] }
        let member = members[index]
        let availableNames = availableNames(forMemberAt: index)

        return deduplicateStrings(
            member.graphDependencyCandidates.filter { name in
                knownNames.contains(name) && availableNames.contains(name)
            }
        )
    }

    /// Same as `graphDependencies(forMemberAt:)` but drops edges that are
    /// classified as `.soft` (`Lazy<T>`) or `.provider` (`Provider<T>`).
    ///
    /// The validator's cycle-detection DFS uses this variant so a graph that
    /// would otherwise be rejected as cyclic can compile as long as each
    /// cycle has at least one deferred edge — either `Lazy<T>` for
    /// one-shot deferral or `Provider<T>` for repeated resolution of a
    /// transient target. `with:` key-path dependencies remain hard; only
    /// closure parameters can express lazy/provider wiring.
    func hardGraphDependencies(forMemberAt index: Int) -> [String] {
        guard members.indices.contains(index) else { return [] }
        let member = members[index]
        let availableNames = availableNames(forMemberAt: index)
        let deferredNames = Set(member.softClosureDependencies)
            .union(member.providerClosureDependencies)

        let hardCandidates = member.graphDependencyCandidates.filter { !deferredNames.contains($0) }

        return deduplicateStrings(
            hardCandidates.filter { name in
                knownNames.contains(name) && availableNames.contains(name)
            }
        )
    }
}
