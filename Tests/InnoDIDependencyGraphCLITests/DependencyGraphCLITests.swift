import Foundation
import Testing

@Suite("DependencyGraph CLI Integration")
struct DependencyGraphCLITests {
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

    @Test("Unknown option emits warning but continues")
    func unknownOptionWarnsAndContinues() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--unknown",
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stderr.contains("Warning: unrecognized option '--unknown'"))
        #expect(result.stdout.contains("InnoDI Dependency Graph"))
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
        #expect(!result.stderr.contains("Unresolved container references:"))
        #expect(!result.stderr.contains("APIClient"))
        #expect(!result.stderr.contains("LiveGreetingService"))
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
