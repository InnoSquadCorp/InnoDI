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

    let rootPath = parsed.root
    let outputPath = parsed.output
    let outputFormat = parsed.format ?? .mermaid

    // `--diagnose-lock` short-circuits before any source loading: it
    // does not need to parse the user's containers, only inspect the
    // scratch directory.
    if let requested = parsed.diagnoseLockPath {
        return runDiagnoseLockSubcommand(
            rootPath: rootPath,
            requestedScratchPath: requested
        )
    }

    // `--cache-stats` likewise only inspects on-disk metrics
    // artifacts; it never parses source.
    if let requested = parsed.cacheStatsPath {
        return runCacheStatsSubcommand(
            rootPath: rootPath,
            requestedStatePath: requested
        )
    }

    let snapshot: WorkspaceSourceSnapshot
    do {
        if parsed.validateDAG {
            snapshot = try loadWorkspaceSourceSnapshot(rootPath: rootPath)
        } else {
            snapshot = try loadWorkspaceSourceSnapshot(rootPath: rootPath) { relativePath, fileURL, error in
                fputs(
                    "Warning: failed to read '\(relativePath)' (\(fileURL.path(percentEncoded: false))): \(error)\n",
                    stderr
                )
            }
        }
    } catch {
        fputs("Error loading Swift sources: \(error)\n", stderr)
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

    if parsed.validateDAG {
        return writeValidationResult(
            validateDependencyGraph(snapshot: snapshot),
            outputPath: outputPath
        )
    }

    let renderedGraph = collectRenderableDependencyGraph(
        snapshot: snapshot,
        validateDAG: false
    )
    guard !renderedGraph.nodes.isEmpty else {
        return writeNoContainersMessage(outputPath: outputPath)
    }

    let rendered: String
    switch outputFormat {
    case .mermaid:
        rendered = renderMermaid(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
    case .dot:
        rendered = renderDOT(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
    case .ascii:
        rendered = renderASCII(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
    case .json:
        rendered = renderJSON(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
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
