import InnoDICore

/// Construction order is deliberately separate from the source model. Only
/// the two initialization loops consume these arrays; parameters, overrides,
/// support storage and tracing ownership retain source order. Teardown has a
/// separate reverse-dependency plan independent of construction policy.
struct DIContainerInitializationPlan {
    let syncShared: [ProvideMemberModel]
    let asyncShared: [ProvideMemberModel]

    init(model: DIContainerExpansionModel) throws {
        if model.options.initializationOrder == .dependency {
            syncShared = try Self.ordered(model.syncSharedMembers)
            asyncShared = try Self.ordered(model.asyncSharedMembers)
        } else {
            syncShared = model.syncSharedMembers
            asyncShared = model.asyncSharedMembers
        }
    }

    /// Close dependants before dependencies, including paths through eager
    /// providers. Eager task storage itself is not owned by legacy close.
    static func asyncTeardownMembers(model: DIContainerExpansionModel) throws -> [ProvideMemberModel] {
        try ordered(model.asyncSharedMembers).reversed().filter(\.isAsyncOnDemand)
    }

    private static func ordered(_ members: [ProvideMemberModel]) throws -> [ProvideMemberModel] {
        // Never use availability-filtered graphDependencies: unavailable
        // forward references are precisely the edges this plan must order.
        // Deferred Lazy/Provider ownership edges remain cycle constraints,
        // but are not startup prerequisites.
        let nodes = members.map {
            InitializationOrderNode(
                name: $0.name,
                hardDependencies: $0.hardClosureDependencies + $0.withDependencies
            )
        }
        do {
            return try stableInitializationOrder(nodes).map { members[$0] }
        } catch InitializationOrderError.duplicateName(let name) {
            throw CodegenInvariantError(description: "Duplicate shared provider in initialization plan: '\(name)'.")
        } catch InitializationOrderError.cycle {
            // Semantic validation normally reports the canonical ownership
            // cycle diagnostic before codegen. Both preflight and emission
            // still fail closed if validation was bypassed by a direct caller.
            throw CodegenInvariantError(description: "Shared initialization dependency cycle reached code generation.")
        }
    }
}
