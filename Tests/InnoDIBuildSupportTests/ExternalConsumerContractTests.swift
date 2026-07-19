import Foundation
import Testing
import InnoDIWorkspaceAnalysis
import InnoDITestSupport

@Suite("External SwiftPM consumer contracts", .serialized, .tags(.slow))
struct ExternalConsumerContractTests {
    @Test("Compile-pass fixtures build and run with strict concurrency")
    func compilePassFixturesBuild() throws {
        let fixtures = try externalConsumerFixtures(expectation: .pass)
        #expect(!fixtures.isEmpty)
        // A macro-only consumer can use SwiftSyntax's prebuilt on matching
        // toolchains, while a DAG plugin consumer also builds non-macro
        // SwiftSyntax clients from source. The profile helper isolates those
        // incompatible graphs but coalesces older source-only toolchains.
        let scratchRoot = externalConsumerScratchRoot()

        for fixture in fixtures {
            let materializedURL = try materializeExternalConsumerFixture(fixture)
            defer { try? FileManager.default.removeItem(at: materializedURL) }

            let result = try runStrictConcurrencyBuild(
                packageURL: materializedURL,
                scratchPath: externalConsumerScratchPath(
                    for: fixture,
                    under: scratchRoot
                )
            )
            let output = result.stdout + "\n" + result.stderr

            if result.timedOut || result.exitCode != 0 {
                Issue.record("Fixture '\(fixture.name)' failed:\n\(output)")
            }
            #expect(!result.timedOut, "Fixture '\(fixture.name)' timed out")
            #expect(result.exitCode == 0, "Fixture '\(fixture.name)' must compile")
            assertNoCompilerCrash(in: output, fixtureName: fixture.name)

            guard !result.timedOut, result.exitCode == 0 else { continue }
            let execution = try runExternalConsumerExecutable(
                packageURL: materializedURL,
                scratchPath: externalConsumerScratchPath(
                    for: fixture,
                    under: scratchRoot
                )
            )
            let executionOutput = execution.stdout + "\n" + execution.stderr
            if execution.timedOut || execution.exitCode != 0 {
                Issue.record("Fixture '\(fixture.name)' failed at runtime:\n\(executionOutput)")
            }
            #expect(!execution.timedOut, "Fixture '\(fixture.name)' execution timed out")
            #expect(execution.exitCode == 0, "Fixture '\(fixture.name)' must run successfully")
            assertNoCompilerCrash(in: executionOutput, fixtureName: fixture.name)
        }
    }

    @Test("Published dependency graph executable runs from a fresh consumer")
    func dependencyGraphExecutableRunsFromFreshConsumer() throws {
        let fixture = try externalConsumerFixture(
            named: "basic-container",
            expectation: .pass
        )
        let materializedURL = try materializeExternalConsumerFixture(fixture)
        defer { try? FileManager.default.removeItem(at: materializedURL) }

        let result = try runExternalDependencyGraphExecutable(
            packageURL: materializedURL,
            // Running the CLI loads non-macro SwiftSyntax clients even though
            // this fixture's app target is macro-only. Keep that source graph
            // out of the matching-toolchain prebuilt scratch.
            scratchPath: externalConsumerScratchPath(
                for: .dagPluginSource,
                under: externalConsumerScratchRoot()
            )
        )
        let output = result.stdout + "\n" + result.stderr

        if result.timedOut || result.exitCode != 0 {
            Issue.record("Dependency graph executable failed from a fresh consumer:\n\(output)")
        }
        #expect(!result.timedOut, "Dependency graph executable timed out")
        #expect(result.exitCode == 0, "Dependency graph executable must run successfully")
        #expect(result.stdout.contains("InnoDI Dependency Graph"))
        #expect(result.stdout.contains("AppContainer"))
        #expect(result.stdout.contains("FeatureContainer"))
        assertNoCompilerCrash(in: output, fixtureName: fixture.name)
    }

    @Test("Compile-fail fixtures emit their expected diagnostics")
    func compileFailFixturesEmitExpectedDiagnostics() throws {
        let fixtures = try externalConsumerFixtures(expectation: .fail)
        #expect(!fixtures.isEmpty)
        // SwiftPM invalidates each materialized root target while retaining
        // compatible dependency products. The profile helper still separates
        // prebuilt and full-source SwiftSyntax graphs.
        let scratchRoot = externalConsumerScratchRoot()

        for fixture in fixtures {
            let materializedURL = try materializeExternalConsumerFixture(fixture)
            defer { try? FileManager.default.removeItem(at: materializedURL) }

            let result = try runStrictConcurrencyBuild(
                packageURL: materializedURL,
                scratchPath: externalConsumerScratchPath(
                    for: fixture,
                    under: scratchRoot
                )
            )
            let output = result.stdout + "\n" + result.stderr
            let expectedDiagnostics = try expectedDiagnostics(for: fixture)

            if result.timedOut || result.exitCode == 0 {
                Issue.record("Fixture '\(fixture.name)' did not fail as expected:\n\(output)")
            }
            #expect(!result.timedOut, "Fixture '\(fixture.name)' timed out")
            #expect(result.exitCode != 0, "Fixture '\(fixture.name)' must fail compilation")
            let normalization = normalizeCompilerSourceErrors(in: output)
            #expect(
                normalization.inconsistentPhaseCounts.isEmpty,
                "Fixture '\(fixture.name)' emitted an unsupported source-diagnostic phase count:\n\(formatDiagnosticMultiset(normalization.inconsistentPhaseCounts))"
            )
            let actualCounts = diagnosticMultiset(normalization.messages)
            let expectedCounts = diagnosticMultiset(expectedDiagnostics)
            #expect(
                actualCounts == expectedCounts,
                "Fixture '\(fixture.name)' emitted a different exact diagnostic multiset.\nExpected:\n\(formatDiagnosticMultiset(expectedCounts))\nActual:\n\(formatDiagnosticMultiset(actualCounts))"
            )
            assertNoCompilerCrash(in: output, fixtureName: fixture.name)
        }
    }

    @Test("The 5.0 signature rejects the removed concrete argument")
    func staleConcreteArgumentFailsCompilation() throws {
        let fixture = try externalConsumerFixture(
            named: "stale-concrete-argument",
            expectation: .signature
        )
        let materializedURL = try materializeExternalConsumerFixture(fixture)
        defer { try? FileManager.default.removeItem(at: materializedURL) }

        let result = try runStrictConcurrencyBuild(
            packageURL: materializedURL,
            scratchPath: externalConsumerScratchPath(
                for: fixture,
                under: externalConsumerScratchRoot()
            )
        )
        let output = result.stdout + "\n" + result.stderr

        if result.timedOut || result.exitCode == 0 {
            Issue.record("Stale concrete argument did not fail as expected:\n\(output)")
        }
        #expect(!result.timedOut, "Stale concrete argument fixture timed out")
        #expect(result.exitCode != 0, "The removed concrete argument must not compile")

        let normalization = normalizeCompilerSourceErrors(in: output)
        #expect(
            normalization.messages.contains { $0.contains("concrete") },
            "A compiler diagnostic must identify the removed concrete argument:\n\(output)"
        )
        assertNoCompilerCrash(in: output, fixtureName: fixture.name)
    }

    @Test("Structured plugin diagnostics preserve raw multiplicity")
    func compilerDiagnosticNormalizationPreservesStructuredPluginMultiplicity() {
        let output = """
        /tmp/Fixture.swift:4:3: error: [container.local-declaration-unsupported] plugin validation failed
        /tmp/Fixture.swift:4:3: error: [container.local-declaration-unsupported] plugin validation failed
        """

        let normalization = normalizeCompilerSourceErrors(in: output)
        #expect(normalization.inconsistentPhaseCounts.isEmpty)
        #expect(
            diagnosticMultiset(normalization.messages) == [
                "[container.local-declaration-unsupported] plugin validation failed": 2,
            ]
        )
    }

    @Test("Attached macro diagnostics collapse frontend phase copies")
    func compilerDiagnosticNormalizationCollapsesMacroPhaseCopies() {
        let output = """
        /tmp/Fixture.swift:4:3: error: one macro diagnostic (from macro 'DIContainer')
        /tmp/Fixture.swift:4:3: error: one macro diagnostic (from macro 'DIContainer')
        /tmp/Fixture.swift:5:3: error: duplicate macro diagnostic (from macro 'DIComponent')
        /tmp/Fixture.swift:5:3: error: duplicate macro diagnostic (from macro 'DIComponent')
        /tmp/Fixture.swift:5:3: error: duplicate macro diagnostic (from macro 'DIComponent')
        /tmp/Fixture.swift:5:3: error: duplicate macro diagnostic (from macro 'DIComponent')
        """

        let normalization = normalizeCompilerSourceErrors(in: output)
        #expect(normalization.inconsistentPhaseCounts.isEmpty)
        #expect(
            diagnosticMultiset(normalization.messages) == [
                "one macro diagnostic": 1,
                "duplicate macro diagnostic": 2,
            ]
        )
    }

    @Test("Raw Swift diagnostics preserve multiplicity without phase provenance")
    func compilerDiagnosticNormalizationPreservesRawSwiftMultiplicity() {
        let output = """
        /tmp/Fixture.swift:6:3: error: raw compiler diagnostic [#ActorIsolatedCall]
        /tmp/Fixture.swift:6:3: error: raw compiler diagnostic [#ActorIsolatedCall]
        /tmp/Fixture.swift:7:1: warning: ignored warning
        unrelated: error: ignored non-source error
        """

        let normalization = normalizeCompilerSourceErrors(in: output)
        #expect(normalization.inconsistentPhaseCounts.isEmpty)
        #expect(
            diagnosticMultiset(normalization.messages) == [
                "raw compiler diagnostic": 2,
            ]
        )
    }

    @Test("Committed fixture templates are invisible to workspace source discovery")
    func fixtureTemplatesDoNotPolluteWorkspaceAnalysis() throws {
        let sources = try discoverWorkspaceSourceFiles(
            rootPath: packageRootURL().path(percentEncoded: false)
        )

        #expect(
            !sources.contains { $0.hasPrefix("Tests/ExternalConsumerFixtures/") },
            "External consumer templates must use .swift.fixture names"
        )
    }

    @Test("External fixture scratch follows the SwiftSyntax build mode")
    func externalFixtureScratchFollowsBuildMode() throws {
        let macroOnly = try externalConsumerFixture(
            named: "basic-container",
            expectation: .pass
        )
        let plugin = try externalConsumerFixture(
            named: "generated-qualifier-usage-sensitive-shadows",
            expectation: .pass
        )
        let scratchRoot = URL(fileURLWithPath: "/tmp/innodi-external-scratch-test")
        let defaultRoot = externalConsumerScratchRoot(environment: [:])
        let overriddenRoot = externalConsumerScratchRoot(
            environment: ["INNODI_EXTERNAL_SCRATCH_PATH": "/tmp/custom-innodi-scratch"]
        )

        #expect(
            defaultRoot == packageRootURL()
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("external-consumer-contracts", isDirectory: true)
        )
        #expect(
            overriddenRoot
                == URL(fileURLWithPath: "/tmp/custom-innodi-scratch", isDirectory: true)
        )

        #if compiler(>=6.3.3)
        #expect(macroOnly.scratchProfile == .macroOnlyPrebuilt)
        #expect(plugin.scratchProfile == .dagPluginSource)
        #expect(
            externalConsumerScratchPath(for: macroOnly, under: scratchRoot)
                != externalConsumerScratchPath(for: plugin, under: scratchRoot)
        )
        #else
        #expect(macroOnly.scratchProfile == .sharedSource)
        #expect(plugin.scratchProfile == .sharedSource)
        #expect(
            externalConsumerScratchPath(for: macroOnly, under: scratchRoot)
                == externalConsumerScratchPath(for: plugin, under: scratchRoot)
        )
        #endif
    }
}

private enum ExternalConsumerExpectation: String {
    case pass
    case fail
    case signature
}

private struct ExternalConsumerFixture {
    let name: String
    let sourceURL: URL
    let expectation: ExternalConsumerExpectation
    let scratchProfile: ExternalConsumerScratchProfile
}

private enum ExternalConsumerScratchProfile: String {
    case sharedSource = "shared-source"
    case macroOnlyPrebuilt = "macro-only-prebuilt"
    case dagPluginSource = "dag-plugin-source"
}

private enum ExternalConsumerFixtureError: Error, CustomStringConvertible {
    case missingDirectory(String)
    case emptyExpectation(String)
    case unexpectedFixtureEntry(String)
    case unexpectedTemplate(String)
    case unresolvedPlaceholder(String)
    case missingMaterializedFile(String)
    case missingDiagnostics(String)

    var description: String {
        switch self {
        case .missingDirectory(let path):
            return "Missing external consumer fixture directory: \(path)"
        case .emptyExpectation(let expectation):
            return "No external consumer fixtures found for expectation: \(expectation)"
        case .unexpectedFixtureEntry(let path):
            return "Only fixture directories are allowed directly under pass/fail: \(path)"
        case .unexpectedTemplate(let path):
            return "Fixture files must end in .fixture or be expected-diagnostics.txt: \(path)"
        case .unresolvedPlaceholder(let path):
            return "Fixture contains an unresolved InnoDI placeholder: \(path)"
        case .missingMaterializedFile(let path):
            return "Materialized external consumer fixture is missing: \(path)"
        case .missingDiagnostics(let name):
            return "Compile-fail fixture has no expected diagnostics: \(name)"
        }
    }
}

private func externalConsumerFixtures(
    expectation: ExternalConsumerExpectation
) throws -> [ExternalConsumerFixture] {
    let directoryURL = packageRootURL()
        .appendingPathComponent("Tests/ExternalConsumerFixtures", isDirectory: true)
        .appendingPathComponent(expectation.rawValue, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
        atPath: directoryURL.path(percentEncoded: false),
        isDirectory: &isDirectory
    ), isDirectory.boolValue else {
        throw ExternalConsumerFixtureError.missingDirectory(
            directoryURL.path(percentEncoded: false)
        )
    }

    let entries = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    for entry in entries {
        guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ExternalConsumerFixtureError.unexpectedFixtureEntry(
                entry.path(percentEncoded: false)
            )
        }
    }
    let sortedFixtureURLs = entries.sorted {
        $0.lastPathComponent < $1.lastPathComponent
    }
    // Local reproducer escape hatch. CI leaves this unset and always executes
    // the complete pass/fail matrix.
    let requestedFixture = ProcessInfo.processInfo.environment[
        "INNODI_EXTERNAL_FIXTURE"
    ]
    let fixtureURLs = sortedFixtureURLs.filter { url in
        requestedFixture == nil || url.lastPathComponent == requestedFixture
    }

    guard !fixtureURLs.isEmpty else {
        throw ExternalConsumerFixtureError.emptyExpectation(expectation.rawValue)
    }

    return try fixtureURLs.map { url in
        ExternalConsumerFixture(
            name: url.lastPathComponent,
            sourceURL: url,
            expectation: expectation,
            scratchProfile: try externalConsumerScratchProfile(for: url)
        )
    }
}

private func externalConsumerFixture(
    named name: String,
    expectation: ExternalConsumerExpectation
) throws -> ExternalConsumerFixture {
    let sourceURL = packageRootURL()
        .appendingPathComponent("Tests/ExternalConsumerFixtures", isDirectory: true)
        .appendingPathComponent(expectation.rawValue, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
        atPath: sourceURL.path(percentEncoded: false),
        isDirectory: &isDirectory
    ), isDirectory.boolValue else {
        throw ExternalConsumerFixtureError.missingDirectory(
            sourceURL.path(percentEncoded: false)
        )
    }
    return ExternalConsumerFixture(
        name: name,
        sourceURL: sourceURL,
        expectation: expectation,
        scratchProfile: try externalConsumerScratchProfile(for: sourceURL)
    )
}

private func externalConsumerScratchProfile(
    for fixtureSourceURL: URL
) throws -> ExternalConsumerScratchProfile {
    let manifestURL = fixtureSourceURL.appendingPathComponent("Package.swift.fixture")
    guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
        throw ExternalConsumerFixtureError.missingMaterializedFile(
            manifestURL.path(percentEncoded: false)
        )
    }
    let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
    #if compiler(>=6.3.3)
    // SwiftSyntax 603.0.2 first has a matching Apple prebuilt on Swift 6.3.3.
    // A DAG plugin loads non-macro SwiftSyntax clients and therefore remains a
    // source graph; do not let its products contaminate macro-only fixtures.
    return manifest.contains("InnoDIDAGValidationPlugin")
        ? .dagPluginSource
        : .macroOnlyPrebuilt
    #else
    // Swift 6.2 and 6.3.2 compile both graphs from source, so sharing avoids a
    // second cold SwiftSyntax build without mixing binary modes.
    return .sharedSource
    #endif
}

private func materializeExternalConsumerFixture(
    _ fixture: ExternalConsumerFixture
) throws -> URL {
    let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "InnoDI-ExternalConsumer-\(fixture.expectation.rawValue)-\(fixture.name)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )
    var didFinishMaterializing = false
    defer {
        if !didFinishMaterializing {
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    guard let enumerator = FileManager.default.enumerator(
        at: fixture.sourceURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw ExternalConsumerFixtureError.missingDirectory(
            fixture.sourceURL.path(percentEncoded: false)
        )
    }

    let fixtureSourcePath = fixture.sourceURL.path(percentEncoded: false)
    let sourcePrefix = fixtureSourcePath.hasSuffix("/")
        ? fixtureSourcePath
        : fixtureSourcePath + "/"
    for case let sourceURL as URL in enumerator {
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        let sourcePath = sourceURL.path(percentEncoded: false)
        let relativePath = String(sourcePath.dropFirst(sourcePrefix.count))

        if values.isDirectory == true {
            try FileManager.default.createDirectory(
                at: destinationURL.appendingPathComponent(relativePath, isDirectory: true),
                withIntermediateDirectories: true
            )
            continue
        }

        if sourceURL.lastPathComponent == "expected-diagnostics.txt" {
            continue
        }
        guard relativePath.hasSuffix(".fixture") else {
            throw ExternalConsumerFixtureError.unexpectedTemplate(relativePath)
        }

        let outputRelativePath = String(relativePath.dropLast(".fixture".count))
        let outputURL = destinationURL.appendingPathComponent(outputRelativePath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var contents = try String(contentsOf: sourceURL, encoding: .utf8)
        contents = contents.replacingOccurrences(
            of: "{{INNODI_PACKAGE_PATH}}",
            with: escapedSwiftString(packageRootURL().path(percentEncoded: false))
        )
        contents = contents.replacingOccurrences(
            of: "{{INNODI_PACKAGE_IDENTITY}}",
            with: packageIdentity(for: packageRootURL())
        )
        guard !contents.contains("{{INNODI_") else {
            throw ExternalConsumerFixtureError.unresolvedPlaceholder(relativePath)
        }
        try contents.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    for requiredPath in ["Package.swift", "Sources/FixtureApp/FixtureApp.swift"] {
        let requiredURL = destinationURL.appendingPathComponent(requiredPath)
        guard FileManager.default.fileExists(
            atPath: requiredURL.path(percentEncoded: false)
        ) else {
            throw ExternalConsumerFixtureError.missingMaterializedFile(requiredPath)
        }
    }

    didFinishMaterializing = true
    return destinationURL
}

/// A stable scratch root lets independent contract tests and repeated local
/// invocations reuse SwiftPM-validated dependency products. The materialized
/// consumer roots remain disposable, so their own sources are always checked.
/// `swift package clean` removes the default cache when a true cold run is
/// required; CI can also supply an isolated absolute override.
private func externalConsumerScratchRoot(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> URL {
    if let override = environment[
        "INNODI_EXTERNAL_SCRATCH_PATH"
    ], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    return packageRootURL()
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("external-consumer-contracts", isDirectory: true)
}

private func externalConsumerScratchPath(
    for fixture: ExternalConsumerFixture,
    under root: URL
) -> URL {
    externalConsumerScratchPath(for: fixture.scratchProfile, under: root)
}

private func externalConsumerScratchPath(
    for profile: ExternalConsumerScratchProfile,
    under root: URL
) -> URL {
    root.appendingPathComponent(profile.rawValue, isDirectory: true)
}

private func expectedDiagnostics(
    for fixture: ExternalConsumerFixture
) throws -> [String] {
    let diagnosticsURL = fixture.sourceURL.appendingPathComponent("expected-diagnostics.txt")
    guard FileManager.default.fileExists(
        atPath: diagnosticsURL.path(percentEncoded: false)
    ) else {
        throw ExternalConsumerFixtureError.missingDiagnostics(fixture.name)
    }

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !diagnostics.isEmpty else {
        throw ExternalConsumerFixtureError.missingDiagnostics(fixture.name)
    }
    return diagnostics
}

private func assertNoCompilerCrash(in output: String, fixtureName: String) {
    let crashMarkers = [
        "Stack dump:",
        "Swift frontend command failed due to signal",
        "compile command failed due to signal",
        "Fatal error:",
    ]
    for marker in crashMarkers {
        #expect(
            !output.contains(marker),
            "Fixture '\(fixtureName)' emitted crash marker: \(marker)"
        )
    }
}

private enum CompilerSourceErrorProvenance: Hashable {
    case structuredPlugin
    case attachedMacro(name: String)
    case rawSwift
}

private struct CompilerSourceError: Hashable {
    let sourceLocation: String
    let message: String
    let provenance: CompilerSourceErrorProvenance
}

private struct CompilerSourceErrorNormalization {
    let messages: [String]
    let inconsistentPhaseCounts: [String: Int]
}

/// Attached-macro diagnostics identify their provenance, so paired frontend-phase
/// copies can be normalized without conflating different producers. Structured
/// plugin diagnostics preserve their raw multiplicity because each stable-code
/// record is intentional. Raw Swift diagnostics also preserve raw multiplicity:
/// compiler output has no phase identifier, and collapsing identical records could
/// hide genuine duplicate semantic errors.
private func normalizeCompilerSourceErrors(
    in output: String
) -> CompilerSourceErrorNormalization {
    let errors: [CompilerSourceError] = output.components(
        separatedBy: .newlines
    ).compactMap { line in
        guard line.contains(".swift:") || line.contains("macro expansion "),
              let marker = line.range(of: ": error: ") else {
            return nil
        }
        let sourceLocation = String(line[..<marker.lowerBound])
        var message = String(line[marker.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isStructuredPluginDiagnostic = hasStableDiagnosticCodePrefix(message)
        let macroSuffix = message.range(
            of: " (from macro '",
            options: .backwards
        )
        let provenance: CompilerSourceErrorProvenance
        if isStructuredPluginDiagnostic {
            provenance = .structuredPlugin
        } else if let macroSuffix, message.hasSuffix("')") {
            let macroNameEnd = message.index(message.endIndex, offsetBy: -2)
            provenance = .attachedMacro(
                name: String(message[macroSuffix.upperBound..<macroNameEnd])
            )
            message = String(message[..<macroSuffix.lowerBound])
        } else {
            provenance = .rawSwift
        }
        if message.hasSuffix("]"),
           let diagnosticCode = message.range(
               of: " [#",
               options: .backwards
           ) {
            message = String(message[..<diagnosticCode.lowerBound])
        }
        return CompilerSourceError(
            sourceLocation: sourceLocation,
            message: message,
            provenance: provenance
        )
    }

    let rawCounts = Dictionary(errors.map { ($0, 1) }, uniquingKeysWith: +)
    var messages: [String] = []
    var inconsistentPhaseCounts: [String: Int] = [:]
    for (error, rawCount) in rawCounts {
        let semanticCount: Int
        switch error.provenance {
        case .structuredPlugin, .rawSwift:
            semanticCount = rawCount
        case let .attachedMacro(name):
            switch rawCount {
            case 1, 2:
                semanticCount = 1
            case let count where count.isMultiple(of: 2):
                semanticCount = count / 2
            default:
                semanticCount = (rawCount + 1) / 2
                inconsistentPhaseCounts[
                    "\(error.sourceLocation): \(error.message) (from macro '\(name)')"
                ] = rawCount
            }
        }
        messages.append(contentsOf: repeatElement(error.message, count: semanticCount))
    }

    return CompilerSourceErrorNormalization(
        messages: messages,
        inconsistentPhaseCounts: inconsistentPhaseCounts
    )
}

private func hasStableDiagnosticCodePrefix(_ message: String) -> Bool {
    guard message.first == "[",
          let closingBracket = message.firstIndex(of: "]") else {
        return false
    }
    let codeStart = message.index(after: message.startIndex)
    guard codeStart < closingBracket else {
        return false
    }
    let code = message[codeStart..<closingBracket]
    guard code.allSatisfy({ character in
        character.isLetter
            || character.isNumber
            || character == "."
            || character == "-"
            || character == "_"
    }) else {
        return false
    }
    let suffixStart = message.index(after: closingBracket)
    return suffixStart == message.endIndex || message[suffixStart].isWhitespace
}

private func diagnosticMultiset(_ messages: [String]) -> [String: Int] {
    Dictionary(messages.map { ($0, 1) }, uniquingKeysWith: +)
}

private func formatDiagnosticMultiset(_ counts: [String: Int]) -> String {
    counts.keys.sorted().map { message in
        "\(counts[message, default: 0])x \(message)"
    }.joined(separator: "\n")
}

private func escapedSwiftString(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func packageIdentity(for packageURL: URL) -> String {
    var identity = packageURL.lastPathComponent.lowercased()
    if identity.hasSuffix(".git") {
        identity.removeLast(".git".count)
    }
    return identity
}
