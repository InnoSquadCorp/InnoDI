import Foundation
import InnoDICore
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIBuildSupport

@Suite("ValidationCoordinator")
struct ValidationCoordinatorTests {
    @Test("Whitespace and comments do not change the AST signature")
    func whitespaceAndCommentsDoNotChangeASTSignature() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let original = try collectValidationSignature(rootPath: fixture.rootURL.path(percentEncoded: false))

        try """
        // leading comment
        struct Feature {
            let value = 1
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )

        let rewritten = try collectValidationSignature(rootPath: fixture.rootURL.path(percentEncoded: false))

        #expect(original == rewritten)
    }

    @Test("Validation signature is deterministic regardless of file creation order")
    func validationSignatureIgnoresFileCreationOrder() throws {
        let firstRoot = try makeTemporaryRoot()
        let secondRoot = try makeTemporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        try "struct Alpha { let value = 1 }\n".write(
            to: firstRoot.appendingPathComponent("Alpha.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Beta { let value = 2 }\n".write(
            to: firstRoot.appendingPathComponent("Beta.swift"),
            atomically: true,
            encoding: .utf8
        )

        try "struct Beta { let value = 2 }\n".write(
            to: secondRoot.appendingPathComponent("Beta.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Alpha { let value = 1 }\n".write(
            to: secondRoot.appendingPathComponent("Alpha.swift"),
            atomically: true,
            encoding: .utf8
        )

        let firstSignature = try collectValidationSignature(rootPath: firstRoot.path(percentEncoded: false))
        let secondSignature = try collectValidationSignature(rootPath: secondRoot.path(percentEncoded: false))

        #expect(firstSignature == secondSignature)
    }

    @Test("Unchanged files reuse cached normalized AST digests")
    func unchangedFilesReuseCachedDigests() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        _ = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))
        let firstParseCount = parser.parseCount
        _ = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))

        #expect(firstParseCount == 1)
        #expect(parser.parseCount == 1)
        #expect(parser.parsedSources.count == 1)
    }

    @Test("Only changed and added files are reparsed, and deleted files drop from the manifest")
    func onlyChangedAndAddedFilesAreReparsed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try "struct Secondary { let value = 2 }\n".write(
            to: fixture.rootURL.appendingPathComponent("Secondary.swift"),
            atomically: true,
            encoding: .utf8
        )

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        _ = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))
        #expect(parser.parseCount == 2)

        try "struct Feature { let value = 200 }\n".write(
            to: fixture.rootURL.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Added { let value = 3 }\n".write(
            to: fixture.rootURL.appendingPathComponent("Added.swift"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.removeItem(at: fixture.rootURL.appendingPathComponent("Secondary.swift"))

        _ = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))

        #expect(parser.parseCount == 4)

        let manifest = try loadDigestManifest(at: fixture.stateURL.appendingPathComponent("ast-digest-cache.json"))
        #expect(manifest.files.keys.sorted() == ["Added.swift", "Feature.swift"])
    }

    @Test("Comment-only changes preserve the final package signature")
    func commentOnlyChangesPreservePackageSignature() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        let firstSignature = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))

        try """
        // updated comment only
        struct Feature {
            let value = 1
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )

        let secondSignature = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))

        #expect(firstSignature == secondSignature)
        #expect(parser.parseCount == 2)
    }

    @Test("Metadata-only changes reuse cached AST digests after content hash check")
    func metadataOnlyChangesReuseCachedDigests() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        _ = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))
        #expect(parser.parseCount == 1)

        let featureURL = fixture.rootURL.appendingPathComponent("Feature.swift")
        try touch(featureURL, modifiedAt: Date().addingTimeInterval(10))

        _ = try collector.collect(rootPath: fixture.rootURL.path(percentEncoded: false))

        #expect(parser.parseCount == 1)
    }

    @Test("Signature collector reports cache hits, content reuse, and reparses")
    func signatureCollectorReportsMetrics() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        let first = try collector.collectWithMetrics(rootPath: fixture.rootURL.path(percentEncoded: false))
        #expect(first.metrics.scannedFileCount == 1)
        #expect(first.metrics.metadataCacheHitCount == 0)
        #expect(first.metrics.contentHashReuseCount == 0)
        #expect(first.metrics.astReparseCount == 1)

        let second = try collector.collectWithMetrics(rootPath: fixture.rootURL.path(percentEncoded: false))
        #expect(second.metrics.metadataCacheHitCount == 1)
        #expect(second.metrics.contentHashReuseCount == 0)
        #expect(second.metrics.astReparseCount == 0)

        let featureURL = fixture.rootURL.appendingPathComponent("Feature.swift")
        try touch(featureURL, modifiedAt: Date().addingTimeInterval(5))
        let third = try collector.collectWithMetrics(rootPath: fixture.rootURL.path(percentEncoded: false))
        #expect(third.metrics.metadataCacheHitCount == 0)
        #expect(third.metrics.contentHashReuseCount == 1)
        #expect(third.metrics.astReparseCount == 0)
    }

    @Test("Success result is reused for identical input signature")
    func successResultIsReused() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let first = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )
        let second = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(first.wasCached == false)
        #expect(second.wasCached == true)
        #expect(runner.invocationCount == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.outputAURL.appendingPathComponent("dag-validation-stamp.txt").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: fixture.outputBURL.appendingPathComponent("dag-validation-stamp.txt").path(percentEncoded: false)))
    }

    @Test("Coordinator writes metrics artifacts for live and cached executions")
    func coordinatorWritesMetricsArtifacts() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let first = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            verboseLoggingEnabled: true
        )
        let second = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
            runner: runner,
            verboseLoggingEnabled: false
        )

        let firstArtifact = try loadMetricsArtifact(at: fixture.outputAURL.appendingPathComponent("dag-validation-metrics.json"))
        let secondArtifact = try loadMetricsArtifact(at: fixture.outputBURL.appendingPathComponent("dag-validation-metrics.json"))
        let firstSummary = try String(
            contentsOf: fixture.outputAURL.appendingPathComponent("dag-validation-summary.md"),
            encoding: .utf8
        )

        #expect(first.metricsArtifact == firstArtifact)
        #expect(second.metricsArtifact == secondArtifact)
        #expect(firstArtifact.wasCached == false)
        #expect(secondArtifact.wasCached == true)
        #expect(firstArtifact.signatureMetrics.scannedFileCount == 1)
        #expect(firstArtifact.humanSummarySource == "dag-validation-summary.md")
        #expect(firstArtifact.reasonCodes.contains(.liveRunDAGValidation))
        #expect(firstArtifact.fileChanges.newFiles == ["Feature.swift"])
        #expect(firstArtifact.fileChanges.reparsedFiles == ["Feature.swift"])
        #expect(firstSummary.contains("# InnoDI Validation Summary"))
        #expect(firstSummary.contains("cache-miss-new-file"))
        #expect(firstSummary.contains("### Reparsed files"))
        #expect(firstSummary.contains("`Feature.swift`"))
        #expect(first.verboseSummary?.contains("[InnoDI]") == true)
        #expect(second.verboseSummary == nil)
    }

    @Test("Failure result is reused for identical input signature")
    func failureResultIsReused() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 3, stdout: "", stderr: "DAG validation failed.\n")
            ]
        )

        let first = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/false",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )
        let second = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/false",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(first.result.exitCode == 3)
        #expect(second.result.exitCode == 3)
        #expect(first.wasCached == false)
        #expect(second.wasCached == true)
        #expect(second.result.stderr == "DAG validation failed.\n")
        #expect(runner.invocationCount == 1)
    }

    @Test("Concurrent requests share one live validation run")
    func concurrentRequestsShareOneLiveValidationRun() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ],
            delay: 0.2
        )

        let outputCURL = fixture.rootURL.appendingPathComponent("output-c", isDirectory: true)
        let outputDURL = fixture.rootURL.appendingPathComponent("output-d", isDirectory: true)

        let results = try await withThrowingTaskGroup(of: ValidationExecutionOutcome.self) { group in
            group.addTask {
                try ValidationCoordinator.coordinate(
                    rootPath: fixture.rootURL.path(percentEncoded: false),
                    toolPath: "/usr/bin/true",
                    stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                    outputDirectoryPath: outputCURL.path(percentEncoded: false),
                    runner: runner
                )
            }
            group.addTask {
                try ValidationCoordinator.coordinate(
                    rootPath: fixture.rootURL.path(percentEncoded: false),
                    toolPath: "/usr/bin/true",
                    stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                    outputDirectoryPath: outputDURL.path(percentEncoded: false),
                    runner: runner
                )
            }

            var collected: [ValidationExecutionOutcome] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(results.count == 2)
        #expect(runner.invocationCount == 1)
        #expect(results.contains { $0.wasCached })
        #expect(results.contains { !$0.wasCached })
    }

    @Test("Changing source input invalidates the cached result")
    func changingSourceInputInvalidatesCache() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "first\n", stderr: ""),
                ValidationCommandResult(exitCode: 0, stdout: "second\n", stderr: "")
            ]
        )

        let first = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        try "struct Feature { let value = 2 }\n".write(
            to: fixture.rootURL.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )

        let second = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(first.wasCached == false)
        #expect(second.wasCached == false)
        #expect(first.signature != second.signature)
        #expect(runner.invocationCount == 2)
    }

    @Test("Cross-file custom init validation fails before DAG runner executes")
    func crossFileCustomInitValidationFailsBeforeRunnerExecutes() throws {
        let fixture = try makeCrossFileCustomInitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("container.custom-init-unsupported"))
        #expect(outcome.result.stderr.contains("extension"))
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunCustomInitFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Same-file custom init conflicts remain outside build-stage validation")
    func sameFileCustomInitConflictsDoNotShortCircuitBuildValidator() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let outcome = try ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 0)
        #expect(runner.invocationCount == 1)
    }

    @Test("Cross-file validator matches nested paths exactly and ignores generic or constrained extensions")
    func crossFileValidatorRespectsExtensionMatchingBoundaries() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        struct Outer {
            @DIContainer
            struct NestedContainer {
                @Provide(.input)
                var config: Config
            }
        }

        @DIContainer
        struct GenericContainer<T> {
            @Provide(.input)
            var config: Config
        }
        """.write(
            to: rootURL.appendingPathComponent("Containers.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        extension Outer.NestedContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }

        extension GenericContainer<String> {
            init(config: Config, preview: Bool) {
                self.init(config: config)
            }
        }

        extension GenericContainer where T: Sendable {
            init(config: Config, retries: Int) {
                self.init(config: config)
            }
        }
        """.write(
            to: rootURL.appendingPathComponent("Extensions.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CustomInitBuildValidator.validate(rootPath: rootURL.path(percentEncoded: false))

        #expect(result.issues.count == 1)
        #expect(result.issues.first?.metadata["containerPath"] == "Outer.NestedContainer")
    }

    @Test("Semantic resolver expands top-level aliases and unique suffix matches conservatively")
    func semanticResolverExpandsAliasesAndSuffixes() {
        let resolver = SemanticResolverIndex(
            nominalTypes: [
                SemanticNominalTypeRecord(path: "Feature.AppContainer", components: ["Feature", "AppContainer"]),
                SemanticNominalTypeRecord(path: "Admin.AppContainer", components: ["Admin", "AppContainer"]),
                SemanticNominalTypeRecord(path: "Feature.Nested.AppContainer", components: ["Feature", "Nested", "AppContainer"])
            ],
            topLevelTypeAliases: [
                SemanticTypeAliasRecord(
                    path: "ActiveContainer",
                    components: ["ActiveContainer"],
                    target: SemanticTypeReference(
                        displayPath: "Feature.AppContainer",
                        components: ["Feature", "AppContainer"]
                    )
                ),
                SemanticTypeAliasRecord(
                    path: "Aliases.Active",
                    components: ["Aliases", "Active"],
                    target: SemanticTypeReference(
                        displayPath: "Feature.Nested.AppContainer",
                        components: ["Feature", "Nested", "AppContainer"]
                    )
                ),
                SemanticTypeAliasRecord(
                    path: "NestedAlias",
                    components: ["NestedAlias"],
                    target: SemanticTypeReference(
                        displayPath: "Aliases.Active",
                        components: ["Aliases", "Active"]
                    )
                )
            ]
        )

        let aliasResolved = resolver.resolvePath(
            for: SemanticTypeReference(displayPath: "ActiveContainer", components: ["ActiveContainer"]),
            candidatePaths: ["Feature.AppContainer"]
        )
        let suffixResolved = resolver.resolvePath(
            for: SemanticTypeReference(
                displayPath: "PreviewModule.Feature.AppContainer",
                components: ["PreviewModule", "Feature", "AppContainer"]
            ),
            candidatePaths: ["Feature.AppContainer"]
        )
        let ambiguousSuffix = resolver.resolvePath(
            for: SemanticTypeReference(displayPath: "AppContainer", components: ["AppContainer"]),
            candidatePaths: ["Feature.AppContainer", "Admin.AppContainer"]
        )
        let nestedAliasResolved = resolver.resolvePath(
            for: SemanticTypeReference(displayPath: "NestedAlias", components: ["NestedAlias"]),
            candidatePaths: ["Feature.Nested.AppContainer"]
        )

        #expect(aliasResolved.state == .resolved)
        #expect(aliasResolved.resolvedPath == "Feature.AppContainer")
        #expect(aliasResolved.aliasExpansionTrace == ["ActiveContainer"])
        #expect(suffixResolved.state == .resolved)
        #expect(suffixResolved.resolvedPath == "Feature.AppContainer")
        #expect(suffixResolved.usedSuffixFallback == true)
        #expect(ambiguousSuffix.state == .ambiguous)
        #expect(ambiguousSuffix.candidates == ["Admin.AppContainer", "Feature.AppContainer"])
        #expect(nestedAliasResolved.state == .resolved)
        #expect(nestedAliasResolved.resolvedPath == "Feature.Nested.AppContainer")
        #expect(nestedAliasResolved.aliasExpansionTrace == ["NestedAlias", "Aliases.Active"])
    }
}

private final class MockValidationSyntaxParser: @unchecked Sendable, ValidationSyntaxParsing {
    private(set) var parsedSources: [String] = []

    var parseCount: Int {
        parsedSources.count
    }

    func parse(source: String) -> SourceFileSyntax {
        parsedSources.append(source)
        return Parser.parse(source: source)
    }
}

private struct FixturePaths {
    let rootURL: URL
    let stateURL: URL
    let outputAURL: URL
    let outputBURL: URL
}

private func loadDigestManifest(at url: URL) throws -> ValidationDigestManifest {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ValidationDigestManifest.self, from: data)
}

private func loadMetricsArtifact(at url: URL) throws -> ValidationMetricsArtifact {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ValidationMetricsArtifact.self, from: data)
}

private func makeFixture() throws -> FixturePaths {
    let rootURL = try makeTemporaryRoot()
    let stateURL = rootURL.appendingPathComponent("state", isDirectory: true)
    let outputAURL = rootURL.appendingPathComponent("output-a", isDirectory: true)
    let outputBURL = rootURL.appendingPathComponent("output-b", isDirectory: true)

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputAURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputBURL, withIntermediateDirectories: true)

    try "struct Feature { let value = 1 }\n".write(
        to: rootURL.appendingPathComponent("Feature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return FixturePaths(
        rootURL: rootURL,
        stateURL: stateURL,
        outputAURL: outputAURL,
        outputBURL: outputBURL
    )
}

private func makeCrossFileCustomInitFixture() throws -> FixturePaths {
    let fixture = try makeFixture()

    try """
    @DIContainer
    struct AppContainer {
        @Provide(.input)
        var config: Config
    }
    """.write(
        to: fixture.rootURL.appendingPathComponent("Container.swift"),
        atomically: true,
        encoding: .utf8
    )

    try """
    extension AppContainer {
        init(config: Config, debug: Bool) {
            self.init(config: config)
        }
    }
    """.write(
        to: fixture.rootURL.appendingPathComponent("Container+Debug.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixture
}

private func makeTemporaryRoot() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-BuildSupport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
}

private func touch(_ url: URL, modifiedAt: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path(percentEncoded: false))
}

private final class MockValidationRunner: ValidationCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let results: [ValidationCommandResult]
    private let delay: TimeInterval
    private var currentInvocationCount = 0

    init(results: [ValidationCommandResult], delay: TimeInterval = 0) {
        self.results = results
        self.delay = delay
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentInvocationCount
    }

    func runValidationTool(toolPath: String, rootPath: String) throws -> ValidationCommandResult {
        lock.lock()
        let invocationIndex = currentInvocationCount
        currentInvocationCount += 1
        lock.unlock()

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }

        if invocationIndex < results.count {
            return results[invocationIndex]
        }

        return results.last ?? ValidationCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}
