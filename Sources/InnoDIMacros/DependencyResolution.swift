import InnoDICore
import SwiftSyntax

/// Availability state for one dependency name at a specific declaration index.
///
/// `unknown` means the container never declares the name, while `unavailable`
/// means the name exists but declaration-order or scope rules prevent it from
/// being injected at the current member.
typealias DependencyReferenceStatus = DependencyAvailabilityIndex.Status

/// Macro adapter for the shared, syntax-independent availability rule.
/// Diagnostics and injectable edge selection use the index; ownership edge
/// selection deliberately retains unavailable references to detect cycles.
struct DependencyResolutionContext {
    let members: [ProvideMemberModel]
    private let availability: DependencyAvailabilityIndex
    let initializationOrder: ContainerInitializationOrderValue
    var knownNames: Set<String> { availability.knownNames }

    init(
        members: [ProvideMemberModel],
        initializationOrder: ContainerInitializationOrderValue = .declaration
    ) {
        self.members = members
        self.initializationOrder = initializationOrder
        self.availability = DependencyAvailabilityIndex(members: members.map { member in
            let kind: DependencyAvailabilityIndex.Kind
            switch member.scope {
            case .input: kind = .input
            case .transient: kind = .transient
            case .shared:
                kind = member.isAsyncFactory ? .asynchronousShared : .synchronousShared
            }
            return .init(name: member.name, kind: kind)
        })
    }

    func availableNames(forMemberAt index: Int) -> Set<String> {
        availability.availableNames(
            forMemberAt: index,
            allowForwardSharedReferences: initializationOrder == .dependency
        )
    }

    func status(of dependencyName: String, forMemberAt index: Int) -> DependencyReferenceStatus {
        availability.status(
            of: dependencyName,
            forMemberAt: index,
            allowForwardSharedReferences: initializationOrder == .dependency
        )
    }

    /// Graph edges that are both declared and currently injectable.
    func graphDependencies(forMemberAt index: Int) -> [String] {
        guard members.indices.contains(index) else { return [] }
        let member = members[index]

        return deduplicateStrings(
            member.graphDependencyCandidates.filter { name in
                status(of: name, forMemberAt: index) == .available
            }
        )
    }

    /// Ownership edges include deferred handles and unavailable forward
    /// references. Availability is diagnosed separately; it must not hide a
    /// reference cycle, including when other graph diagnostics are disabled.
    func cycleDependencies(forMemberAt index: Int) -> [String] {
        guard members.indices.contains(index) else { return [] }
        let member = members[index]
        return deduplicateStrings(
            member.graphDependencyCandidates.filter { knownNames.contains($0) }
        )
    }
}
