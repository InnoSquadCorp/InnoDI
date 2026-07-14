import Foundation
import InnoDIDependencyGraphCore
import InnoDIWorkspaceAnalysis
import Testing

@Suite("DependencyGraph CLI Integration")
struct DependencyGraphCLITests {
    @Test("Unsupported nested containers block outer graph usage collection")
    func unsupportedNestedContainerIsAGraphUsageBarrier() throws {
        let fixtureURL = try makeUnsupportedNestedContainerFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let snapshot = try loadWorkspaceSourceSnapshot(
            rootPath: fixtureURL.path(percentEncoded: false)
        )

        let analysis = collectDependencyGraph(snapshot: snapshot, validateDAG: false)

        #expect(analysis.nodes.map(\.displayName).sorted() == ["Child", "Parent"])
        #expect(analysis.edges.isEmpty)
    }

    @Test("Unsupported container declarations fail render and validation preflight")
    func unsupportedDeclarationsFailEveryGraphMode() throws {
        let fixtureURL = try makeUnsupportedDeclarationFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let rootPath = fixtureURL.path(percentEncoded: false)

        for arguments in [
            ["--root", rootPath, "--format", "json"],
            ["--root", rootPath, "--validate-dag"],
        ] {
            let result = try runCLI(arguments)

            #expect(result.exitCode == 1)
            #expect(result.stdout.isEmpty)
            #expect(
                result.stderr.components(
                    separatedBy: "[container.unsupported-declaration-kind]"
                ).count - 1 == 1
            )
            #expect(
                result.stderr.components(
                    separatedBy: "[container.generic-unsupported]"
                ).count - 1 == 1
            )
            #expect(
                result.stderr.components(
                    separatedBy: "[container.unverifiable-enclosing-context]"
                ).count - 1 == 1
            )
            #expect(
                result.stderr.components(
                    separatedBy: "[container.local-declaration-unsupported]"
                ).count - 1 == 2
            )
            #expect(!result.stderr.contains("container.custom-init-unsupported"))
            #expect(!result.stdout.contains("schemaVersion"))
            #expect(!result.stdout.contains("DAG validation passed"))
        }
    }

    @Test("Renders mermaid, dot, and ascii formats")
    func rendersSupportedFormats() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let rootPath = fixtureURL.path(percentEncoded: false)

        let mermaid = try runCLI(["--root", rootPath, "--format", "mermaid"])
        #expect(mermaid.exitCode == 0)
        #expect(mermaid.stdout.contains("graph TD"))

        let dot = try runCLI(["--root", rootPath, "--format", "dot"])
        #expect(dot.exitCode == 0)
        #expect(dot.stdout.contains("digraph InnoDI"))

        let ascii = try runCLI(["--root", rootPath, "--format", "ascii"])
        #expect(ascii.exitCode == 0)
        #expect(ascii.stdout.contains("InnoDI Dependency Graph"))
    }

    @Test("Deferred Lazy/Provider edges reach the real CLI renderers")
    func rendersDeferredEdgesEndToEnd() throws {
        let fixtureURL = try makeDeferredEdgeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let rootPath = fixtureURL.path(percentEncoded: false)

        let mermaid = try runCLI(["--root", rootPath, "--format", "mermaid"])
        #expect(mermaid.exitCode == 0)
        #expect(mermaid.stdout.contains("-.->"))
        #expect(mermaid.stdout.contains("==>"))

        let dot = try runCLI(["--root", rootPath, "--format", "dot"])
        #expect(dot.exitCode == 0)
        #expect(dot.stdout.contains("style=dashed"))
        #expect(dot.stdout.contains("style=dotted"))

        let ascii = try runCLI(["--root", rootPath, "--format", "ascii"])
        #expect(ascii.exitCode == 0)
        #expect(ascii.stdout.contains("- ->"))
        #expect(ascii.stdout.contains("~~>"))
        #expect(ascii.stdout.contains("soft dependency (Lazy<T>)"))
        #expect(ascii.stdout.contains("provider (Provider<T>)"))
    }

    @Test("Qualified InnoDI provide attributes still contribute deferred edges end-to-end")
    func rendersQualifiedDeferredEdgesEndToEnd() throws {
        let fixtureURL = try makeQualifiedDeferredEdgeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let rootPath = fixtureURL.path(percentEncoded: false)

        let mermaid = try runCLI(["--root", rootPath, "--format", "mermaid"])
        #expect(mermaid.exitCode == 0)
        #expect(mermaid.stdout.contains("-.->"))
        #expect(mermaid.stdout.contains("==>"))

        let validation = try runCLI(["--root", rootPath, "--validate-dag"])
        #expect(validation.exitCode == 0)
        #expect(validation.stdout.contains("DAG validation passed."))
    }

    @Test("Writes graph output file with --output")
    func writesOutputFile() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let outputURL = fixtureURL.appendingPathComponent("graph.dot")
        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "dot",
            "--output", outputURL.path(percentEncoded: false)
        ])

        #expect(result.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(content.contains("digraph InnoDI"))
    }

    @Test("--output - writes graph output to stdout")
    func outputDashWritesGraphToStdout() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "json",
            "--output", "-"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("\"schemaVersion\""))
        #expect(result.stderr.isEmpty)
    }

    @Test("--output - writes DAG validation messages to stdout")
    func outputDashWritesValidationMessageToStdout() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag",
            "--output", "-"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
        #expect(result.stderr.isEmpty)
    }

    @Test("--output - preserves stderr for DAG validation failures")
    func outputDashPreservesValidationFailureStderr() throws {
        let fixtureURL = try makeCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag",
            "--output", "-"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("DAG validation failed."))
        #expect(result.stderr.contains("Detected dependency cycles:"))
    }

    @Test("--validate-dag fails strict source loading on invalid UTF-8")
    func validateDAGFailsStrictSourceLoadingOnInvalidUTF8() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        try Data([0xff, 0xfe, 0xfd]).write(to: fixtureURL.appendingPathComponent("Broken.swift"))

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("Error loading Swift sources"))
        #expect(!result.stderr.contains("DAG validation passed."))
    }

    @Test("Render mode warns and skips invalid UTF-8 sources")
    func renderModeWarnsAndSkipsInvalidUTF8Sources() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        try Data([0xff, 0xfe, 0xfd]).write(to: fixtureURL.appendingPathComponent("Broken.swift"))

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "json"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("\"schemaVersion\""))
        #expect(result.stderr.contains("Warning: failed to read 'Broken.swift'"))
    }

    @Test("Validation output files still mirror stderr diagnostics")
    func validationOutputFileStillMirrorsStderrDiagnostics() throws {
        let fixtureURL = try makeCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let outputURL = fixtureURL.appendingPathComponent("validation.txt")

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag",
            "--output", outputURL.path(percentEncoded: false)
        ])

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(result.exitCode == 3)
        #expect(content.contains("DAG validation failed."))
        #expect(result.stderr.contains("DAG validation failed."))
    }

    @Test("Unknown option fails with usage and no graph output")
    func unknownOptionFailsWithUsage() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--unknown",
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii"
        ])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("Error: Unknown option '--unknown'"))
        #expect(result.stdout.contains("Usage: InnoDI-DependencyGraph"))
        #expect(!result.stdout.contains("InnoDI Dependency Graph"))
    }

    @Test("Missing value for --root fails with usage")
    func missingRootValueFailsWithUsage() throws {
        let result = try runCLI([
            "--root",
            "--format", "ascii"
        ])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("Option --root requires a value"))
        #expect(result.stdout.contains("Usage: InnoDI-DependencyGraph"))
    }

    @Test("Invalid --format value fails with usage")
    func invalidFormatValueFailsWithUsage() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "invalid"
        ])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("Invalid --format value 'invalid'"))
        #expect(result.stdout.contains("Usage: InnoDI-DependencyGraph"))
    }

    @Test("PNG output handles Graphviz availability")
    func pngOutputHandlesGraphvizAvailability() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let outputURL = fixtureURL.appendingPathComponent("graph.png")
        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "dot",
            "--output", outputURL.path(percentEncoded: false)
        ])

        if result.exitCode == 0 {
            #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
            #expect(result.stdout.contains("PNG generated at"))
        } else {
            #expect(result.exitCode == 1)
            #expect(
                result.stderr.contains("dot command not found") || result.stderr.contains("Failed to generate PNG")
            )
        }
    }

    @Test("No container output write failure returns distinct exit code")
    func noContainerWriteFailureReturnsDistinctExitCode() throws {
        let fixtureURL = try makeNoContainerFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii",
            "--output", "/dev/null/nope.txt"
        ])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("Error writing to file"))
    }

    @Test("Validate DAG fails on container cycle")
    func validateDAGFailsOnCycle() throws {
        let fixtureURL = try makeCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("DAG validation failed."))
        #expect(result.stderr.contains("Detected dependency cycles:"))
    }

    @Test("Validate DAG skips root-level generated dependency directories")
    func validateDAGSkipsRootLevelGeneratedDependencyDirectories() throws {
        let fixtureURL = try makeRootSkippedDirectoryFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
        #expect(!result.stderr.contains("Detected dependency cycles:"))
    }

    @Test("Validate DAG treats provider edges as deferred end-to-end")
    func validateDAGPassesWhenProviderBreaksCycle() throws {
        let fixtureURL = try makeProviderDeferredCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
    }

    @Test("Validate DAG treats lazy edges as deferred end-to-end")
    func validateDAGPassesWhenLazyBreaksCycle() throws {
        let fixtureURL = try makeLazyDeferredCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
    }

    @Test("Validate DAG ignores deferred wrappers that target non-container services")
    func validateDAGIgnoresDeferredWrappersForServices() throws {
        let fixtureURL = try makeDeferredServiceWrapperFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
        #expect(!result.stderr.contains("[graph.unresolved-container-reference]"))
        #expect(!result.stderr.contains("[graph.ambiguous-container-reference]"))
        #expect(!result.stderr.contains("[graph.excluded-container-reference]"))
    }

    @Test("Validate DAG suppresses ambiguous deferred container references")
    func validateDAGSuppressesAmbiguousDeferredContainerReferences() throws {
        let fixtureURL = try makeAmbiguousDeferredReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
        #expect(!result.stderr.contains("[graph.ambiguous-container-reference]"))
        #expect(!result.stderr.contains("[graph.unresolved-container-reference]"))
        #expect(!result.stderr.contains("[graph.excluded-container-reference]"))
    }

    @Test("Validate DAG suppresses excluded deferred container references")
    func validateDAGSuppressesExcludedDeferredContainerReferences() throws {
        let fixtureURL = try makeExcludedDeferredReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
        #expect(!result.stderr.contains("[graph.ambiguous-container-reference]"))
        #expect(!result.stderr.contains("[graph.unresolved-container-reference]"))
        #expect(!result.stderr.contains("[graph.excluded-container-reference]"))
    }

    @Test("Validate DAG still reports unresolved deferred container references")
    func validateDAGReportsUnresolvedDeferredContainerReferences() throws {
        let fixtureURL = try makeDeferredUnresolvedReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("Unresolved container references:"))
        #expect(result.stderr.contains("[graph.unresolved-container-reference]"))
        #expect(result.stderr.contains("MissingFeatureContainer"))
    }

    @Test("Hard edge still wins when a provider edge shares the same source and destination")
    func validateDAGStillFailsWhenHardAndProviderEdgesCoexist() throws {
        let fixtureURL = try makeMixedHardAndProviderCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("Detected dependency cycles:"))
    }

    @Test("Validate DAG ignores opted-out containers")
    func validateDAGIgnoresOptedOutContainers() throws {
        let fixtureURL = try makeValidateDAGOptOutFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
    }

    @Test("Validate DAG fails on ambiguous container reference")
    func validateDAGFailsOnAmbiguousContainerReference() throws {
        let fixtureURL = try makeAmbiguousReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("Ambiguous container references:"))
        #expect(result.stderr.contains("FeatureContainer"))
    }

    @Test("Validate DAG ignores ambiguity when all matching destinations are opted out")
    func validateDAGIgnoresAmbiguousOptedOutDestinations() throws {
        let fixtureURL = try makeAmbiguousOptedOutReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
        #expect(!result.stderr.contains("Ambiguous container references:"))
    }

    @Test("Validate DAG resolves mixed eligibility duplicates and still detects cycle")
    func validateDAGResolvesMixedEligibilityAndDetectsCycle() throws {
        let fixtureURL = try makeMixedEligibilityDuplicateNameCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("Detected dependency cycles:"))
        #expect(result.stderr.contains("[graph.dependency-cycle]"))
        #expect(!result.stderr.contains("Ambiguous container references:"))
    }

    @Test("Validate DAG resolves top-level typealias container references")
    func validateDAGResolvesTopLevelTypeAliasReferences() throws {
        let fixtureURL = try makeTypeAliasReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
    }

    @Test("Validate DAG resolves nested typealias chains")
    func validateDAGResolvesNestedTypeAliasChains() throws {
        let fixtureURL = try makeNestedTypeAliasReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
    }

    @Test("Validate DAG resolves @SubContainer ownership edges through typealiases")
    func validateDAGResolvesSubContainerOwnershipTypeAliasReferences() throws {
        let fixtureURL = try makeSubContainerTypeAliasCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("Detected dependency cycles:"))
        #expect(result.stderr.contains("[graph.dependency-cycle]"))
        #expect(!result.stderr.contains("[graph.unresolved-container-reference]"))
        #expect(!result.stderr.contains("[graph.ambiguous-container-reference]"))
    }

    @Test("Ambiguous @SubContainer ownership references fail validation and are omitted from render output")
    func validateDAGFailsOnAmbiguousSubContainerOwnershipReference() throws {
        let fixtureURL = try makeAmbiguousSubContainerReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let validationResult = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(validationResult.exitCode == 3)
        #expect(validationResult.stderr.contains("Ambiguous container references:"))
        #expect(validationResult.stderr.contains("[graph.ambiguous-container-reference]"))
        #expect(validationResult.stderr.contains("FeatureContainer"))

        let asciiResult = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii"
        ])

        #expect(asciiResult.exitCode == 0)
        #expect(!asciiResult.stdout.contains("#=>"))
        #expect(!asciiResult.stdout.contains("owns,feature"))
    }

    @Test("Validate DAG reports unresolved semantic references")
    func validateDAGReportsUnresolvedSemanticReferences() throws {
        let fixtureURL = try makeUnresolvedReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("Unresolved container references:"))
        #expect(result.stderr.contains("[graph.unresolved-container-reference]"))
        #expect(result.stderr.contains("MissingFeatureContainer"))
    }

    @Test("@Provide service construction is not reported as a container edge")
    func validateDAGIgnoresProvideServiceConstruction() throws {
        let fixtureURL = try makeProvideConstructionFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
        #expect(!result.stderr.contains("[graph.unresolved-container-reference]"))
        #expect(!result.stderr.contains("[graph.ambiguous-container-reference]"))
        #expect(!result.stderr.contains("[graph.excluded-container-reference]"))
    }

    @Test("Render mode prunes to the root-reachable subgraph and follows ownership edges")
    func rootedRenderPrunesToReachableOwnershipSubgraph() throws {
        let fixtureURL = try makeRootedOwnershipRenderFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("AppContainer #=> FeatureContainer:owns,feature"))
        #expect(result.stdout.contains("#=> ownership (@SubContainer)"))
        #expect(!result.stdout.contains("\n  OrphanContainer"))
    }

    @Test("Render mode keeps the union of nodes reachable from multiple roots")
    func rootedRenderUsesUnionOfMultipleRoots() throws {
        let fixtureURL = try makeMultipleRootRenderFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("AppContainer #=> FeatureContainer:owns,feature"))
        #expect(result.stdout.contains("AdminContainer #=> AdminFeatureContainer:owns,adminFeature"))
        #expect(!result.stdout.contains("\n  OrphanContainer"))
    }

    @Test("Render mode keeps the full graph when no roots are declared")
    func renderWithoutRootsKeepsFullGraph() throws {
        let fixtureURL = try makeRootlessRenderFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("\n  AppContainer"))
        #expect(result.stdout.contains("\n  FeatureContainer"))
        #expect(result.stdout.contains("\n  OrphanContainer"))
    }
}

// CLI process helpers (runCLI, CLIRunResult, DataSink, ExecutableNotFound,
// dependencyGraphExecutableURL, packageRootURL) live in `CLIRunner.swift` as
// internal declarations so the snapshot tests can share the same invocation
// pipeline.

private func makeFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Fixture-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let appContainerSource = """
    import InnoDI

    protocol APIClientProtocol {}
    struct APIClient: APIClientProtocol {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var baseURL: String

        @Provide(.shared, factory: APIClient())
        var apiClient: any APIClientProtocol
    }
    """

    let featureContainerSource = """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var apiClient: any APIClientProtocol
    }

    func buildFeature(apiClient: any APIClientProtocol) {
        _ = FeatureContainer(apiClient: apiClient)
    }
    """

    try appContainerSource.write(
        to: fixtureURL.appendingPathComponent("AppContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    try featureContainerSource.write(
        to: fixtureURL.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeUnsupportedDeclarationFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "InnoDI-CLI-Unsupported-Declarations-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: fixtureURL,
        withIntermediateDirectories: true
    )

    let source = """
    import InnoDI

    @DIContainer
    final class ClassContainer {
        init() {}
    }

    @DIContainer
    struct GenericContainer<Value> {}

    struct ExtensionOuter {}
    extension ExtensionOuter {
        @DIContainer
        struct ExtensionNestedContainer {}
    }

    func declareLocalContainer() {
        @DIContainer
        struct LocalContainer {}
    }

    struct AccessorHost {
        var value: Int {
            @DIContainer
            struct AccessorContainer {}
            return 0
        }
    }

    @DIContainer(root: true)
    struct ValidContainer {}
    """
    try source.write(
        to: fixtureURL.appendingPathComponent("Containers.swift"),
        atomically: true,
        encoding: .utf8
    )
    return fixtureURL
}

private func makeUnsupportedNestedContainerFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "InnoDI-CLI-Unsupported-Nested-Usage-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: fixtureURL,
        withIntermediateDirectories: true
    )

    let source = """
    @DIContainer
    struct Parent {
        @DIContainer
        struct Unsupported<Value> {
            @Provide(.shared, factory: Child())
            var child: Child
        }

        @DIContainer
        protocol UnsupportedProtocol {
            @Provide(.shared, factory: Child())
            var child: Child { get }
        }
    }

    @DIContainer
    struct Child {}

    func first() {
        @DIContainer
        struct LocalContainer {
            @Provide(.input) var config: String
        }
    }

    func second() {
        @DIContainer
        struct LocalContainer {
            @Provide(.input) var count: Int
        }
    }

    let closure = {
        @DIContainer
        struct ClosureContainer {
            @Provide(.input) var flag: Bool
        }
    }

    struct AccessorHost {
        var value: Int {
            @DIContainer
            struct AccessorContainer {
                @Provide(.input) var token: String
            }
            return 0
        }
    }
    """
    try source.write(
        to: fixtureURL.appendingPathComponent("Containers.swift"),
        atomically: true,
        encoding: .utf8
    )
    return fixtureURL
}

private func makeDeferredEdgeFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Deferred-Edges-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    struct LazyConsumer {
        let admin: Lazy<AdminContainer>
        init(admin: Lazy<AdminContainer>) { self.admin = admin }
    }

    func buildFeatureContainer() -> FeatureContainer { fatalError() }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: buildFeatureContainer(), concrete: true)
        var feature: FeatureContainer

        @Provide(.input)
        var admin: AdminContainer

        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        }, concrete: true)
        var providerConsumer: ProviderConsumer

        @Provide(.shared, factory: { (admin: Lazy<AdminContainer>) in
            LazyConsumer(admin: admin)
        }, concrete: true)
        var lazyConsumer: LazyConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var seed: Int
    }

    @DIContainer
    struct AdminContainer {
        @Provide(.input)
        var seed: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("DeferredEdges.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeQualifiedDeferredEdgeFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Qualified-Deferred-Edges-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: InnoDI.Provider<FeatureContainer>
        init(feature: InnoDI.Provider<FeatureContainer>) { self.feature = feature }
    }

    struct LazyConsumer {
        let admin: InnoDI.Lazy<AdminContainer>
        init(admin: InnoDI.Lazy<AdminContainer>) { self.admin = admin }
    }

    func buildFeatureContainer() -> FeatureContainer { fatalError() }

    @InnoDI.DIContainer(root: true)
    struct AppContainer {
        @InnoDI.Provide(.transient, factory: buildFeatureContainer(), concrete: true)
        var feature: FeatureContainer

        @InnoDI.Provide(.input)
        var admin: AdminContainer

        @InnoDI.Provide(.shared, factory: { (feature: InnoDI.Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        }, concrete: true)
        var providerConsumer: ProviderConsumer

        @InnoDI.Provide(.shared, factory: { (admin: InnoDI.Lazy<AdminContainer>) in
            LazyConsumer(admin: admin)
        }, concrete: true)
        var lazyConsumer: LazyConsumer
    }

    @InnoDI.DIContainer
    struct FeatureContainer {
        @InnoDI.Provide(.input)
        var seed: Int
    }

    @InnoDI.DIContainer
    struct AdminContainer {
        @InnoDI.Provide(.input)
        var seed: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("QualifiedDeferredEdges.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeProvideConstructionFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Provide-Construction-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    protocol GreetingService {}
    struct LiveGreetingService: GreetingService {}
    struct APIClient {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: APIClient(), concrete: true)
        var apiClient: APIClient

        @Provide(.shared, factory: LiveGreetingService())
        var greetingService: any GreetingService
    }
    """.write(
        to: fixtureURL.appendingPathComponent("AppContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeRootedOwnershipRenderFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Rooted-Ownership-Render-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    struct AppConfig {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: AppConfig

        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct OrphanContainer {
        @Provide(.input)
        var config: AppConfig
    }
    """.write(
        to: fixtureURL.appendingPathComponent("RootedOwnership.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeMultipleRootRenderFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Multiple-Root-Render-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    struct AppConfig {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: AppConfig

        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }

    @DIContainer(root: true)
    struct AdminContainer {
        @Provide(.input)
        var config: AppConfig

        @SubContainer(scope: .shared)
        var adminFeature: AdminFeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct AdminFeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct OrphanContainer {
        @Provide(.input)
        var config: AppConfig
    }
    """.write(
        to: fixtureURL.appendingPathComponent("MultipleRoots.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeRootlessRenderFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Rootless-Render-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    struct AppConfig {}

    @DIContainer
    struct AppContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: AppConfig
    }

    @DIContainer
    struct OrphanContainer {
        @Provide(.input)
        var config: AppConfig
    }
    """.write(
        to: fixtureURL.appendingPathComponent("Rootless.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeTypeAliasReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-TypeAlias-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: String
    }

    typealias ActiveContainer = AppContainer

    func buildFeature(config: String) {
        _ = ActiveContainer(config: config)
    }
    """.write(
        to: fixtureURL.appendingPathComponent("TypeAliasFeature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeNestedTypeAliasReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Nested-TypeAlias-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    enum Feature {
        @DIContainer
        struct LiveContainer {
            @Provide(.input)
            var config: String
        }

        typealias ActiveContainer = LiveContainer
    }

    typealias RootAlias = Feature.ActiveContainer

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: String
    }

    func buildFeature(config: String) {
        _ = RootAlias(config: config)
    }
    """.write(
        to: fixtureURL.appendingPathComponent("NestedTypeAliasFeature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeSubContainerTypeAliasCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-SubContainer-TypeAlias-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    typealias FeatureAlias = FeatureContainer

    @DIContainer(root: true)
    struct AppContainer {
        @SubContainer(scope: .shared)
        var feature: FeatureAlias
    }
    """.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )

    try """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """.write(
        to: fixtureURL.appendingPathComponent("Feature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeUnresolvedReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Unresolved-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    try """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var config: String
        
        @Provide(.shared, factory: MissingFeatureContainer(config: config), concrete: true)
        var feature: MissingFeatureContainer
    }
    """.write(
        to: fixtureURL.appendingPathComponent("UnresolvedFeature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeProviderDeferredCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Provider-Deferred-Cycle-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    func buildFeatureContainer() -> FeatureContainer { fatalError() }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: buildFeatureContainer(), concrete: true)
        var feature: FeatureContainer

        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        }, concrete: true)
        var providerConsumer: ProviderConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("ProviderDeferredCycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeLazyDeferredCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Lazy-Deferred-Cycle-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct LazyConsumer {
        let feature: Lazy<FeatureContainer>
        init(feature: Lazy<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var feature: FeatureContainer

        @Provide(.shared, factory: { (feature: Lazy<FeatureContainer>) in
            LazyConsumer(feature: feature)
        }, concrete: true)
        var lazyConsumer: LazyConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("LazyDeferredCycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeDeferredServiceWrapperFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Deferred-Service-Wrapper-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    final class Request {}
    final class RequestLogger {
        let requests: Provider<Request>
        init(requests: Provider<Request>) { self.requests = requests }
    }

    final class TransientService {}
    final class ServiceHolder {
        let service: Lazy<TransientService>
        init(service: Lazy<TransientService>) { self.service = service }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: { Request() }, concrete: true)
        var request: Request

        @Provide(.shared, factory: { (request: Provider<Request>) in
            RequestLogger(requests: request)
        }, concrete: true)
        var logger: RequestLogger

        @Provide(.transient, factory: { TransientService() }, concrete: true)
        var service: TransientService

        @Provide(.shared, factory: { (service: Lazy<TransientService>) in
            ServiceHolder(service: service)
        }, concrete: true)
        var holder: ServiceHolder
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("DeferredServiceWrappers.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeAmbiguousDeferredReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-Deferred-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        }, concrete: true)
        var providerConsumer: ProviderConsumer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: Int
        }
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeExcludedDeferredReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Excluded-Deferred-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct LazyConsumer {
        let feature: Lazy<FeatureContainer>
        init(feature: Lazy<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: { (feature: Lazy<FeatureContainer>) in
            LazyConsumer(feature: feature)
        }, concrete: true)
        var consumer: LazyConsumer
    }

    @DIContainer(validateDAG: false)
    struct FeatureContainer {
        @Provide(.input)
        var value: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("ExcludedDeferred.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeDeferredUnresolvedReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Unresolved-Deferred-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct LazyConsumer {
        let feature: Lazy<MissingFeatureContainer>
        init(feature: Lazy<MissingFeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: { (feature: Lazy<MissingFeatureContainer>) in
            LazyConsumer(feature: feature)
        }, concrete: true)
        var consumer: LazyConsumer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("UnresolvedDeferred.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeNoContainerFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-NoContainer-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    struct PlainType {
        let value: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("Plain.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeMixedHardAndProviderCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Mixed-Hard-Provider-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    struct ProviderConsumer {
        let feature: Provider<FeatureContainer>
        init(feature: Provider<FeatureContainer>) { self.feature = feature }
    }

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.transient, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer

        @Provide(.shared, factory: { (feature: Provider<FeatureContainer>) in
            ProviderConsumer(feature: feature)
        }, concrete: true)
        var providerConsumer: ProviderConsumer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("MixedHardProviderCycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Cycle-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("Cycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeRootSkippedDirectoryFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Root-Skips-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var baseURL: String
    }
    """

    let skippedSource = """
    import InnoDI

    @DIContainer(root: true)
    struct SkippedA {
        @Provide(.shared, factory: SkippedB(), concrete: true)
        var b: SkippedB
    }

    @DIContainer
    struct SkippedB {
        @Provide(.shared, factory: SkippedA(), concrete: true)
        var a: SkippedA
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )

    for directoryName in ["Pods", "Derived", "Carthage"] {
        let directoryURL = fixtureURL.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try skippedSource.write(
            to: directoryURL.appendingPathComponent("Poison.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    return fixtureURL
}

private func makeValidateDAGOptOutFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Cycle-OptOut-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }

    @DIContainer(validateDAG: false)
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("CycleOptOut.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeAmbiguousReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: Int
        }
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeAmbiguousSubContainerReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-SubContainer-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @SubContainer(scope: .shared)
        var feature: FeatureContainer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer
        struct FeatureContainer {}
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer
        struct FeatureContainer {}
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeAmbiguousOptedOutReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-OptedOut-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }
    """

    let featureASource = """
    import InnoDI

    enum FeatureA {
        @DIContainer(validateDAG: false)
        struct FeatureContainer {
            @Provide(.input)
            var value: Int
        }
    }
    """

    let featureBSource = """
    import InnoDI

    enum FeatureB {
        @DIContainer(validateDAG: false)
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeMixedEligibilityDuplicateNameCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-MixedEligibility-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureDirectory = fixtureURL.appendingPathComponent("Feature", isDirectory: true)
    let namespaceDirectory = fixtureURL.appendingPathComponent("Namespace", isDirectory: true)
    try FileManager.default.createDirectory(at: featureDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: namespaceDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }
    """

    let eligibleFeatureSource = """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    let optedOutDuplicateSource = """
    import InnoDI

    enum Namespace {
        @DIContainer(validateDAG: false)
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try eligibleFeatureSource.write(
        to: featureDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try optedOutDuplicateSource.write(
        to: namespaceDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}
