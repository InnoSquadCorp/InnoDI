import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis

package enum WorkspaceHierarchyBuildValidator {
    package static func validate(rootPath: String) throws -> ValidationIssueReport {
        try validate(
            snapshot: loadWorkspaceSourceSnapshot(rootPath: rootPath),
            moduleGraph: ModuleGraphProvider.snapshot(rootPath: rootPath)
        )
    }

    static func validate(
        snapshot: WorkspaceSourceSnapshot,
        moduleGraph: WorkspaceModuleGraphSnapshot
    ) throws -> ValidationIssueReport {
        let moduleGraph = moduleGraph.cachingPathMatches(for: snapshot.files.map(\.filePath))
        var files: [(scope: String?, collector: WorkspaceHierarchyFileCollector)] = []
        for sourceFile in snapshot.files {
            let collector = WorkspaceHierarchyFileCollector(
                filePath: sourceFile.filePath,
                syntax: sourceFile.syntax
            )
            collector.walk(sourceFile.syntax)
            files.append((scope: sourceFile.targetID?.rawValue, collector: collector))
        }

        let containers = files
            .flatMap { $0.collector.containers }
            .map { container in
                let moduleID = moduleGraph.moduleRecord(forFilePath: container.filePath)?.moduleID
                    ?? unknownWorkspaceModuleID(forFilePath: container.filePath)
                return container.resolved(moduleID: moduleID)
            }
        let roots = containers.filter(\.isHierarchyRoot)
        guard !roots.isEmpty else {
            return ValidationIssueReport(issues: [])
        }

        let scopes = HierarchySemanticScopes(files: files)
        let containersGroupedByID = Dictionary(grouping: containers, by: \.containerID)
        let containersByID = containersGroupedByID.compactMapValues { $0.first }
        let containersByNominalPath = Dictionary(grouping: containers, by: \.nominalPath)
        let modulesByContainerID = containersByID.compactMapValues { record in
            moduleGraph.moduleRecord(moduleID: record.moduleID).map(ResolvedHierarchyModuleContext.init)
        }

        let edgeResolution = resolveHierarchyEdges(
            containers: containers,
            containersByNominalPath: containersByNominalPath,
            moduleGraph: moduleGraph,
            scopes: scopes,
            modulesByContainerID: modulesByContainerID
        )

        let reachable = reachablePathsAndEdges(from: roots.map(\.containerID), edges: edgeResolution.edges)
        let reachablePaths = reachable.containerIDs
        let reachableEdges = reachable.edges

        var issues: [ValidationIssue] = []
        issues.append(contentsOf: edgeResolution.pendingIssues.compactMap { pending in
            reachablePaths.contains(pending.parentContainerID) ? pending.issue : nil
        })
        issues.append(
            contentsOf: validateResolvedEdges(
                reachableEdges,
                containersByID: containersByID,
                moduleGraph: moduleGraph,
                scopes: scopes
            )
        )
        issues.append(contentsOf: validateDuplicateParents(reachableEdges, containersByID: containersByID))
        // A target-scoped snapshot holds the primary target and its
        // dependencies, never the targets that depend on it. Only a root in
        // a component's own target, or in a target that depends on it, can
        // mount the component, so the orphan check covers just the
        // components such a root could reach; a dependency's root cannot
        // mount the primary target's component. A root-path snapshot sees
        // the whole workspace and checks every component.
        let mountableModuleIDs = snapshot.analysisManifest == nil
            ? nil
            : hierarchyModulesMountable(
                fromRootModules: roots.map(\.moduleID),
                moduleGraph: moduleGraph
            )
        issues.append(
            contentsOf: validateOrphanComponents(
                containers,
                reachableContainerIDs: reachablePaths,
                mountableModuleIDs: mountableModuleIDs
            )
        )
        issues.append(contentsOf: detectHierarchyCycles(from: roots.map(\.containerID), edges: edgeResolution.edges))

        issues.sort {
            if $0.location.filePath != $1.location.filePath { return $0.location.filePath < $1.location.filePath }
            if $0.location.line != $1.location.line { return $0.location.line < $1.location.line }
            return $0.location.column < $1.location.column
        }

        return ValidationIssueReport(issues: issues)
    }
}
