import Foundation
import InnoDIBuildSupport
import InnoDIDependencyGraphCore
import InnoDIWorkspaceAnalysis

package func runDependencyGraphCLI() -> Int32 {
    let parsed: ParsedArguments
    switch parseArguments() {
    case .parsed(let args, let warnings):
        parsed = args
        for warning in warnings {
            fputs("\(warning)\n", stderr)
        }
    case .helpRequested:
        printUsage()
        return 0
    case .failed(let error):
        fputs("\(error.message)\n", stderr)
        printUsage()
        return 1
    }

    let outputPath = parsed.output
    let outputFormat = parsed.format ?? .mermaid
    let maintenanceRootPath = parsed.rootPath
        ?? FileManager.default.currentDirectoryPath

    // `--diagnose-lock` short-circuits before any source loading: it
    // does not need to parse the user's containers, only inspect the
    // scratch directory.
    if let requested = parsed.diagnoseLockPath {
        return runDiagnoseLockSubcommand(
            rootPath: maintenanceRootPath,
            requestedScratchPath: requested
        )
    }

    // `--cache-stats` likewise only inspects on-disk metrics
    // artifacts; it never parses source.
    if let requested = parsed.cacheStatsPath {
        return runCacheStatsSubcommand(
            rootPath: maintenanceRootPath,
            requestedStatePath: requested
        )
    }

    if let diffInput = parsed.diffInput {
        do {
            let before = try loadGraphJSONDocument(at: diffInput.beforePath)
            let after = try loadGraphJSONDocument(at: diffInput.afterPath)
            return writeValidationResult(
                DependencyGraphCommandResult(
                    exitCode: ExitCode.success,
                    stdout: renderGraphDiff(before: before, after: after),
                    stderr: ""
                ),
                outputPath: outputPath
            )
        } catch {
            fputs("Error comparing dependency graphs: \(error.localizedDescription)\n", stderr)
            return ExitCode.failure
        }
    }

    guard let input = parsed.input else {
        fputs("Error: graph input was not resolved\n", stderr)
        return ExitCode.failure
    }

    let snapshot: WorkspaceSourceSnapshot
    let primaryTargetID: WorkspaceTargetID?
    do {
        switch input {
        case .analysisManifest(let path):
            let manifest = try loadWorkspaceAnalysisManifest(
                at: URL(fileURLWithPath: path)
            )
            snapshot = try loadWorkspaceSourceSnapshot(manifest: manifest)
            primaryTargetID = manifest.primaryTargetID
        case .root(let rootPath):
            primaryTargetID = nil
            snapshot = try loadWorkspaceSourceSnapshot(
                rootPath: rootPath
            )
        }
    } catch {
        fputs(
            "Error loading Swift sources: \(error.localizedDescription)\n",
            stderr
        )
        return ExitCode.failure
    }

    let declarationMatrix = ContainerSemanticBuildValidator.validateDeclarationMatrix(
        snapshot: snapshot
    )
    if let failure = declarationMatrix.asCommandResult() {
        return writeValidationResult(
            DependencyGraphCommandResult(
                exitCode: failure.exitCode,
                stdout: failure.stdout,
                stderr: failure.stderr
            ),
            outputPath: outputPath
        )
    }

    let generatedQualifierPreflight = GeneratedQualifierBuildValidator
        .validate(snapshot: snapshot)
    if let failure = generatedQualifierPreflight.asCommandResult() {
        return writeValidationResult(
            DependencyGraphCommandResult(
                exitCode: failure.exitCode,
                stdout: failure.stdout,
                stderr: failure.stderr
            ),
            outputPath: outputPath
        )
    }

    if parsed.validateDAG {
        return writeValidationResult(
            validateDependencyGraph(snapshot: snapshot),
            outputPath: outputPath
        )
    }

    if let query = parsed.query {
        let graph = collectDependencyGraph(
            snapshot: snapshot,
            validateDAG: false
        )
        if let failure = graph.preflightFailure {
            return writeValidationResult(failure, outputPath: outputPath)
        }
        guard !graph.nodes.isEmpty else {
            return writeNoContainersMessage(outputPath: outputPath)
        }
        do {
            let rendered = try renderGraphQuery(
                query,
                nodes: graph.nodes,
                edges: graph.edges
            )
            return writeValidationResult(
                DependencyGraphCommandResult(
                    exitCode: ExitCode.success,
                    stdout: rendered,
                    stderr: ""
                ),
                outputPath: outputPath
            )
        } catch {
            let result = DependencyGraphCommandResult(
                exitCode: ExitCode.failure,
                stdout: "",
                stderr: "Error querying dependency graph: \(error.localizedDescription)\n"
            )
            return writeValidationResult(result, outputPath: outputPath)
        }
    }

    guard let rootPruning = parsed.rootPruning else {
        fputs("Error: render scope was not resolved\n", stderr)
        return ExitCode.failure
    }
    let renderedGraph = collectRenderableDependencyGraph(
        snapshot: snapshot,
        validateDAG: false,
        rootPruning: rootPruning
    )
    if let failure = renderedGraph.preflightFailure {
        return writeValidationResult(failure, outputPath: outputPath)
    }
    guard !renderedGraph.nodes.isEmpty else {
        return writeNoContainersMessage(outputPath: outputPath)
    }

    let rendered: String
    do {
        switch outputFormat {
        case .mermaid:
            rendered = renderMermaid(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
        case .dot:
            rendered = renderDOT(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
        case .ascii:
            rendered = renderASCII(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
        case .json:
            guard let primaryTargetID else {
                fputs(
                    "Error: JSON schema v2 requires target-scoped analysis\n",
                    stderr
                )
                return ExitCode.failure
            }
            rendered = try renderJSON(
                scope: GraphJSON.Scope(
                    primaryTargetID: primaryTargetID.rawValue,
                    rootPruning: rootPruning
                ),
                nodes: renderedGraph.nodes,
                edges: renderedGraph.edges
            )
        }
    } catch {
        fputs("Error rendering dependency graph: \(error)\n", stderr)
        return ExitCode.failure
    }

    return writeGraphOutput(rendered, format: outputFormat, outputPath: outputPath)
}

private func writeValidationResult(
    _ result: DependencyGraphCommandResult,
    outputPath: String?
) -> Int32 {
    if let outputPath, outputPath != "-" {
        let message = result.stdout.isEmpty ? result.stderr : result.stdout
        do {
            try message.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return ExitCode.ioError
        }
        if !result.stderr.isEmpty {
            fputs(result.stderr, stderr)
        }
        return result.exitCode
    }

    if outputPath == "-" {
        if !result.stdout.isEmpty {
            fputs(result.stdout, stdout)
        }
        if !result.stderr.isEmpty {
            fputs(result.stderr, stderr)
        }
        return result.exitCode
    }

    if !result.stdout.isEmpty {
        fputs(result.stdout, stdout)
    }
    if !result.stderr.isEmpty {
        fputs(result.stderr, stderr)
    }
    return result.exitCode
}

private func writeNoContainersMessage(outputPath: String?) -> Int32 {
    let errorMessage = "No @DIContainer found in project.\n"

    if let outputPath, outputPath != "-" {
        do {
            try errorMessage.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return ExitCode.ioError
        }
    } else if outputPath == "-" {
        fputs(errorMessage, stdout)
    } else {
        fputs(errorMessage, stderr)
    }

    return ExitCode.noContainers
}
