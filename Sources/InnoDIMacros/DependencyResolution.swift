import SwiftSyntax

enum DependencyReferenceStatus {
    case available
    case unknown
    case unavailable
}

struct DependencyResolutionContext {
    let members: [ProvideMemberModel]
    let knownNames: Set<String>

    init(members: [ProvideMemberModel]) {
        self.members = members
        self.knownNames = Set(members.map(\.name))
    }

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

    func status(of dependencyName: String, forMemberAt index: Int) -> DependencyReferenceStatus {
        guard knownNames.contains(dependencyName) else {
            return .unknown
        }

        if availableNames(forMemberAt: index).contains(dependencyName) {
            return .available
        }

        return .unavailable
    }

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
}
