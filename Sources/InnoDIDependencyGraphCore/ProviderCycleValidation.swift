import InnoDICore

/// Local provider ownership is mandatory even for containers that opt out of
/// global graph diagnostics. Deferred kind affects resolution, not retention.
package func providerCycleFailure(
    providers: [DependencyGraphProvider]
) -> DependencyGraphCommandResult? {
    let knownIDs = Set(providers.map(\.id))
    var adjacency: [String: [String]] = [:]
    for provider in providers {
        adjacency[provider.id] = provider.canonicalDependencyIDs
            .filter { knownIDs.contains($0) }.sorted()
    }
    let result = analyzeDependencyCycles(adjacency: adjacency)
    guard !result.cycles.isEmpty || result.truncatedByDepthLimit else { return nil }
    var lines = result.cycles.map {
        "[container.dependency-cycle] \($0.joined(separator: " -> ")). Lazy<T> and Provider<T> do not exempt ownership cycles."
    }
    if result.truncatedByDepthLimit {
        lines.append("[container.dependency-cycle] cycle detection truncated at depth limit before validation completed")
    }
    return DependencyGraphCommandResult(
        exitCode: DependencyGraphCoreExitCode.dagValidationFailure,
        stdout: "",
        stderr: lines.joined(separator: "\n") + "\n"
    )
}
