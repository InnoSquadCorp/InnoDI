import InnoDICore
import InnoDIDependencyGraphCore

/// Referential integrity is checked before diffing, even when both inputs
/// are byte-identical. Equality cannot make an invalid contract acceptable.
func validateGraphBindingReferences(
    _ document: GraphJSON.Document,
    providersByID: [String: GraphJSON.Provider],
    path: String
) throws {
    func invalid(_ provider: GraphJSON.Provider, _ reason: String) -> GraphInspectionError {
        .invalidDocument(path: path, reason: "provider '\(provider.id)' \(reason)")
    }

    for provider in document.providers {
        for binding in provider.dependencyBindings {
            // Parameter labels are not provider identities. Repeated external
            // labels and differently named bindings can be valid Swift calls.
            guard !binding.parameter.isEmpty else {
                throw invalid(provider, "has an empty factory parameter")
            }
            guard let target = providersByID[binding.providerID],
                  target.containerID == provider.containerID else {
                throw invalid(provider, "factory binding '\(binding.providerID)' is missing or belongs to another container")
            }
            if binding.kind != .hard, target.effect != .sync {
                throw invalid(provider, "deferred binding '\(binding.providerID)' targets an asynchronous provider")
            }
            if binding.kind == .provider, target.lifetime != .transient {
                throw invalid(provider, "Provider binding '\(binding.providerID)' must target a transient provider")
            }
        }
        if provider.dependencyBindings.isEmpty {
            for name in provider.dependencies {
                guard providersByID["\(provider.containerID).\(name)"] != nil else {
                    throw invalid(provider, "dependency '\(name)' does not name a local provider")
                }
            }
        }

        let ownership: DependencyGraphProvider.ContainerBinding.Ownership
        let edgeKind: GraphJSON.EdgeKind
        switch provider.role {
        case .subcontainer:
            ownership = .fixed
            edgeKind = .ownership
        case .assistedFactory:
            ownership = .assisted
            edgeKind = .assistedFactoryOwnership
        case .input, .provider, .multibinding:
            guard provider.containerBindings.isEmpty else {
                throw invalid(provider, "has child bindings but is not a child owner")
            }
            continue
        }

        let mounts = document.edges.filter {
            $0.from == provider.containerID && $0.label == provider.name && $0.kind == edgeKind
        }
        guard mounts.count == 1, let mount = mounts.first else {
            throw invalid(provider, "must have exactly one matching ownership edge")
        }
        var childInputs: Set<String> = []
        for binding in provider.containerBindings {
            guard childInputs.insert(binding.childInputID).inserted else {
                throw invalid(provider, "duplicates child input binding '\(binding.childInputID)'")
            }
            guard binding.ownership == ownership else {
                throw invalid(provider, "child binding ownership disagrees with its role")
            }
            guard let child = providersByID[binding.childInputID],
                  child.role == .input, child.inputKind != .assisted,
                  child.containerID == mount.to else {
                throw invalid(provider, "child binding '\(binding.childInputID)' must name an ordinary input of the mounted child")
            }
            guard let parent = providersByID[binding.parentProviderID],
                  parent.containerID == provider.containerID else {
                throw invalid(provider, "parent binding '\(binding.parentProviderID)' is missing or belongs to another container")
            }
        }
        let requiredInputs = Set(document.providers.filter {
            $0.containerID == mount.to && $0.role == .input && $0.inputKind != .assisted
        }.map(\.id))
        guard childInputs == requiredInputs else {
            throw invalid(provider, "child bindings do not cover exactly the mounted child's ordinary inputs")
        }
    }
}
