import Foundation
import InnoDICore
import SwiftParser

package enum WorkspaceHierarchyBuildValidator {
    package static func validate(rootPath: String) throws -> ValidationIssueReport {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let moduleGraph = try ModuleGraphProvider.snapshot(rootPath: rootPath)
        let sourceFiles = discoverValidationSourceFiles(rootPath: rootPath)

        var collectors: [WorkspaceHierarchyFileCollector] = []
        for relativePath in sourceFiles {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let syntax = Parser.parse(source: source)
            let collector = WorkspaceHierarchyFileCollector(
                filePath: fileURL.path(percentEncoded: false),
                syntax: syntax
            )
            collector.walk(syntax)
            collectors.append(collector)
        }

        let containers = collectors
            .flatMap(\.containers)
            .map { container in
                let moduleID = moduleGraph.moduleRecord(forFilePath: container.filePath)?.moduleID
                    ?? unknownWorkspaceModuleID(forFilePath: container.filePath)
                return container.resolved(moduleID: moduleID)
            }
        let roots = containers.filter(\.isHierarchyRoot)
        guard !roots.isEmpty else {
            return ValidationIssueReport(issues: [])
        }

        let nominalTypes = collectors.flatMap(\.nominalTypes)
        let typeAliases = collectors.flatMap(\.typeAliases)
        let resolver = SemanticResolverIndex(
            nominalTypes: nominalTypes,
            topLevelTypeAliases: typeAliases
        )
        let typeCandidatePaths = Set(nominalTypes.map(\.path))
        let containersGroupedByID = Dictionary(grouping: containers, by: \.containerID)
        let containersByID = containersGroupedByID.compactMapValues { $0.first }
        let containersByNominalPath = Dictionary(grouping: containers, by: \.nominalPath)
        let candidatePaths = Set(containersByNominalPath.keys)
        let modulesByContainerID = containersByID.compactMapValues { record in
            moduleGraph.moduleRecord(moduleID: record.moduleID).map(ResolvedHierarchyModuleContext.init)
        }

        let edgeResolution = resolveHierarchyEdges(
            containers: containers,
            containersByNominalPath: containersByNominalPath,
            moduleGraph: moduleGraph,
            resolver: resolver,
            modulesByContainerID: modulesByContainerID,
            candidatePaths: candidatePaths
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
                resolver: resolver,
                typeCandidatePaths: typeCandidatePaths
            )
        )
        issues.append(contentsOf: validateDuplicateParents(reachableEdges, containersByID: containersByID))
        issues.append(contentsOf: validateOrphanComponents(containers, reachableContainerIDs: reachablePaths))
        issues.append(contentsOf: detectHierarchyCycles(from: roots.map(\.containerID), edges: edgeResolution.edges))

        issues.sort {
            if $0.location.filePath != $1.location.filePath { return $0.location.filePath < $1.location.filePath }
            if $0.location.line != $1.location.line { return $0.location.line < $1.location.line }
            return $0.location.column < $1.location.column
        }

        return ValidationIssueReport(issues: issues)
    }
}
