import Foundation
import InnoDIDependencyGraphCore
import InnoDIWorkspaceAnalysis
import Testing

@testable import InnoDIDependencyGraphCLI

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

    @Test("A workspace without containers exits with the dedicated no-containers code")
    func workspaceWithoutContainersUsesDedicatedExitCode() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-CLI-No-Containers-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        try FileManager.default.createDirectory(
            at: fixtureURL,
            withIntermediateDirectories: true
        )
        try Data("struct PlainType {}\n".utf8).write(
            to: fixtureURL.appendingPathComponent("Plain.swift")
        )

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "all",
            "--format", "ascii",
        ])

        #expect(result.exitCode == ExitCode.noContainers)
        #expect(result.exitCode != ExitCode.failure)
        #expect(result.stderr.contains("No @DIContainer found in project."))
    }

    @Test("Unsupported container declarations fail render and validation preflight")
    func unsupportedDeclarationsFailEveryGraphMode() throws {
        let fixtureURL = try makeUnsupportedDeclarationFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let rootPath = fixtureURL.path(percentEncoded: false)

        for arguments in [
            [
                "--root", rootPath,
                "--root-pruning", "roots",
                "--format", "ascii",
            ],
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
                    separatedBy: "[container.private-access-unsupported]"
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

        let mermaid = try runCLI([
            "--root", rootPath,
            "--root-pruning", "roots",
            "--format", "mermaid",
        ])
        #expect(mermaid.exitCode == 0)
        #expect(mermaid.stdout.contains("graph TD"))

        let dot = try runCLI([
            "--root", rootPath,
            "--root-pruning", "roots",
            "--format", "dot",
        ])
        #expect(dot.exitCode == 0)
        #expect(dot.stdout.contains("digraph InnoDI"))

        let ascii = try runCLI([
            "--root", rootPath,
            "--root-pruning", "roots",
            "--format", "ascii",
        ])
        #expect(ascii.exitCode == 0)
        #expect(ascii.stdout.contains("InnoDI Dependency Graph"))
    }

    @Test("Deferred Lazy/Provider edges reach the real CLI renderers")
    func rendersDeferredEdgesEndToEnd() throws {
        let fixtureURL = try makeDeferredEdgeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let rootPath = fixtureURL.path(percentEncoded: false)

        let mermaid = try runCLI([
            "--root", rootPath,
            "--root-pruning", "roots",
            "--format", "mermaid",
        ])
        #expect(mermaid.exitCode == 0)
        #expect(mermaid.stdout.contains("-.->"))
        #expect(mermaid.stdout.contains("==>"))

        let dot = try runCLI([
            "--root", rootPath,
            "--root-pruning", "roots",
            "--format", "dot",
        ])
        #expect(dot.exitCode == 0)
        #expect(dot.stdout.contains("style=dashed"))
        #expect(dot.stdout.contains("style=dotted"))

        let ascii = try runCLI([
            "--root", rootPath,
            "--root-pruning", "roots",
            "--format", "ascii",
        ])
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

        let mermaid = try runCLI([
            "--root", rootPath,
            "--root-pruning", "roots",
            "--format", "mermaid",
        ])
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
            "--root-pruning", "roots",
            "--format", "dot",
            "--output", outputURL.path(percentEncoded: false)
        ])

        #expect(result.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(content.contains("digraph InnoDI"))
    }

    @Test("--output - writes text graph output to stdout")
    func outputDashWritesGraphToStdout() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "roots",
            "--format", "ascii",
            "--output", "-"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("InnoDI Dependency Graph"))
        #expect(result.stderr.isEmpty)
    }

    @Test("Manifest-backed JSON emits the schema-v2 scope and stable IDs")
    func manifestBackedJSONV2EndToEnd() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let manifest = try writeCLIAnalysisManifest(for: fixtureURL)

        let result = try runCLI([
            "--analysis-manifest", manifest.url.path(percentEncoded: false),
            "--root-pruning", "all",
            "--format", "json",
            "--output", "-",
        ])

        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        let document = try JSONDecoder().decode(
            GraphJSON.Document.self,
            from: Data(result.stdout.utf8)
        )
        #expect(document.schemaVersion == 2)
        #expect(document.scope.primaryTargetID == manifest.targetID.rawValue)
        #expect(document.scope.rootPruning == .all)
        #expect(
            document.nodes.map(\.id) == [
                "swiftpm:cli-fixture:FixtureApp::AppContainer",
                "swiftpm:cli-fixture:FixtureApp::FeatureContainer",
            ]
        )
        #expect(!result.stdout.contains(fixtureURL.path(percentEncoded: false)))

        let validation = try runCLI([
            "--analysis-manifest", manifest.url.path(percentEncoded: false),
            "--validate-dag",
        ])
        #expect(validation.exitCode == 0)
        #expect(validation.stdout.contains("DAG validation passed."))
    }

    @Test("Malformed manifests never fall back to a root scan")
    func malformedManifestIsTerminal() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let manifestURL = fixtureURL.appendingPathComponent(
            "broken-workspace-analysis.json"
        )
        try Data("not-json".utf8).write(to: manifestURL)

        let result = try runCLI([
            "--analysis-manifest", manifestURL.path(percentEncoded: false),
            "--root-pruning", "all",
            "--format", "ascii",
        ])

        #expect(result.exitCode == 1)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Error loading Swift sources"))
        #expect(result.stderr.contains("could not be decoded"))
        #expect(!result.stderr.contains("InnoDI Dependency Graph"))
    }

    @Test("Manifest render fails on duplicate semantic identities")
    func manifestRenderRejectsDuplicateSemanticIdentities() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-CLI-Duplicate-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: fixtureURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let source = """
        import InnoDI

        @DIContainer
        struct SharedContainer {}
        """
        try source.write(
            to: fixtureURL.appendingPathComponent("First.swift"),
            atomically: true,
            encoding: .utf8
        )
        try source.write(
            to: fixtureURL.appendingPathComponent("Second.swift"),
            atomically: true,
            encoding: .utf8
        )
        let manifest = try writeCLIAnalysisManifest(for: fixtureURL)

        let result = try runCLI([
            "--analysis-manifest", manifest.url.path(percentEncoded: false),
            "--root-pruning", "all",
            "--format", "ascii",
        ])

        #expect(result.exitCode == 3)
        #expect(result.stdout.isEmpty)
        #expect(
            result.stderr.contains("[graph.duplicate-semantic-identity]")
        )
    }

    @Test("Manifest DAG validation never broadens to sibling sources")
    func manifestValidationUsesOnlyDeclaredSources() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-CLI-Scope-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: fixtureURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let includedSource = """
        import InnoDI

        @DIContainer(root: true)
        struct IncludedContainer {}
        """
        let poisonSource = """
        import InnoDI

        @DIContainer
        private struct HiddenSiblingContainer {}
        """
        try includedSource.write(
            to: fixtureURL.appendingPathComponent("Included.swift"),
            atomically: true,
            encoding: .utf8
        )
        try poisonSource.write(
            to: fixtureURL.appendingPathComponent("Poison.swift"),
            atomically: true,
            encoding: .utf8
        )
        let manifest = try writeCLIAnalysisManifest(
            for: fixtureURL,
            includingSourcePaths: ["Included.swift"]
        )

        let targetScoped = try runCLI([
            "--analysis-manifest", manifest.url.path(percentEncoded: false),
            "--validate-dag",
        ])
        let legacyRoot = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag",
        ])

        #expect(targetScoped.exitCode == 0)
        #expect(targetScoped.stdout.contains("DAG validation passed."))
        #expect(legacyRoot.exitCode == 1)
        #expect(
            legacyRoot.stderr.contains(
                "[container.private-access-unsupported]"
            )
        )
    }

    @Test("Manifest JSON all and roots scopes select different payloads")
    func manifestJSONRootPruningMatchesScopeEnvelope() throws {
        let fixtureURL = try makeRootedOwnershipRenderFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let manifest = try writeCLIAnalysisManifest(for: fixtureURL)

        let allResult = try runCLI([
            "--analysis-manifest", manifest.url.path(percentEncoded: false),
            "--root-pruning", "all",
            "--format", "json",
        ])
        let rootsResult = try runCLI([
            "--analysis-manifest", manifest.url.path(percentEncoded: false),
            "--root-pruning", "roots",
            "--format", "json",
        ])

        #expect(allResult.exitCode == 0)
        #expect(rootsResult.exitCode == 0)
        let allDocument = try JSONDecoder().decode(
            GraphJSON.Document.self,
            from: Data(allResult.stdout.utf8)
        )
        let rootsDocument = try JSONDecoder().decode(
            GraphJSON.Document.self,
            from: Data(rootsResult.stdout.utf8)
        )
        #expect(allDocument.scope.rootPruning == .all)
        #expect(rootsDocument.scope.rootPruning == .roots)
        #expect(
            allDocument.nodes.contains { $0.semanticPath == "OrphanContainer" }
        )
        #expect(
            !rootsDocument.nodes.contains {
                $0.semanticPath == "OrphanContainer"
            }
        )
        #expect(allDocument.nodes.count > rootsDocument.nodes.count)
    }

    @Test("Maintenance commands dispatch without graph input or pruning")
    func maintenanceCommandsDispatchBeforeGraphValidation() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-CLI-Maintenance-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: fixtureURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let lockResult = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--diagnose-lock",
        ])
        let cacheResult = try runCLI(["--cache-stats"])

        #expect(lockResult.exitCode == 0)
        #expect(lockResult.stdout.contains("InnoDI lock diagnostic"))
        #expect(
            lockResult.stdout.contains(
                fixtureURL.appendingPathComponent(".build").path(
                    percentEncoded: false
                )
            )
        )
        #expect(cacheResult.exitCode == 0)
        #expect(cacheResult.stdout.contains("InnoDI cache statistics"))
        #expect(
            cacheResult.stdout.contains(
                packageRootURL().appendingPathComponent(".build").path(
                    percentEncoded: false
                )
            )
        )
    }

    @Test("Lock diagnosis reports valid and unreadable lock metadata")
    func lockDiagnosisReportsDiscoveredMetadata() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-CLI-Lock-Diagnosis-\(UUID().uuidString)",
                isDirectory: true
            )
        let scratchURL = fixtureURL.appendingPathComponent(
            ".innodi-state",
            isDirectory: true
        )
        let validLockURL = scratchURL
            .appendingPathComponent("a-signature", isDirectory: true)
            .appendingPathComponent("lock")
        let invalidLockURL = scratchURL
            .appendingPathComponent("b-signature", isDirectory: true)
            .appendingPathComponent("lock")
        try FileManager.default.createDirectory(
            at: validLockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: invalidLockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        try #"{"pid":4321,"createdAt":946684800,"bootID":99}"#.write(
            to: validLockURL,
            atomically: true,
            encoding: .utf8
        )
        try "not-json".write(
            to: invalidLockURL,
            atomically: true,
            encoding: .utf8
        )

        let relativeResult = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--diagnose-lock", ".innodi-state",
        ])
        let absoluteResult = try runCLI([
            "--diagnose-lock", scratchURL.path(percentEncoded: false),
        ])

        #expect(relativeResult.exitCode == ExitCode.success)
        #expect(relativeResult.stdout.contains("Lock files: 2 found"))
        #expect(relativeResult.stdout.contains("holder pid:  4321"))
        #expect(relativeResult.stdout.contains("boot id:     99"))
        #expect(relativeResult.stdout.contains("metadata:    <unavailable"))
        #expect(
            relativeResult.stdout.contains(
                scratchURL.path(percentEncoded: false)
            )
        )
        #expect(absoluteResult.exitCode == ExitCode.success)
        #expect(
            absoluteResult.stdout.contains(
                scratchURL.path(percentEncoded: false)
            )
        )
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

    @Test("Render mode fails strict source loading on invalid UTF-8")
    func renderModeFailsStrictSourceLoadingOnInvalidUTF8() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        try Data([0xff, 0xfe, 0xfd]).write(to: fixtureURL.appendingPathComponent("Broken.swift"))

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "roots",
            "--format", "ascii"
        ])

        #expect(result.exitCode == 1)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Error loading Swift sources"))
        #expect(!result.stderr.contains("InnoDI Dependency Graph"))
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
            "--root-pruning", "roots",
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
            "--root-pruning", "all",
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
            "--root-pruning", "roots",
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
            "--root-pruning", "roots",
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
            "--root-pruning", "roots",
            "--format", "ascii"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("AppContainer #=> FeatureContainer:owns,feature"))
        #expect(result.stdout.contains("AdminContainer #=> AdminFeatureContainer:owns,adminFeature"))
        #expect(!result.stdout.contains("\n  OrphanContainer"))
    }

    @Test("All scope keeps the full graph when no roots are declared")
    func renderWithoutRootsKeepsFullGraph() throws {
        let fixtureURL = try makeRootlessRenderFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "all",
            "--format", "ascii"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("\n  AppContainer"))
        #expect(result.stdout.contains("\n  FeatureContainer"))
        #expect(result.stdout.contains("\n  OrphanContainer"))
    }

    @Test("Root pruning fails when no graph roots are declared")
    func rootPruningRequiresRoots() throws {
        let fixtureURL = try makeRootlessRenderFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "roots",
            "--format", "ascii",
        ])

        #expect(result.exitCode == 3)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("[graph.root-pruning-no-roots]"))
    }
}
