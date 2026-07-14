import Foundation
import Testing
import InnoDIWorkspaceAnalysis
import InnoDITestSupport

@Suite("External SwiftPM consumer contracts", .serialized, .tags(.slow))
struct ExternalConsumerContractTests {
    @Test("Compile-pass fixtures build with strict concurrency")
    func compilePassFixturesBuild() throws {
        let fixtures = try externalConsumerFixtures(expectation: .pass)
        #expect(!fixtures.isEmpty)

        for fixture in fixtures {
            let materializedURL = try materializeExternalConsumerFixture(fixture)
            defer { try? FileManager.default.removeItem(at: materializedURL) }

            let result = try runStrictConcurrencyBuild(packageURL: materializedURL)
            let output = result.stdout + "\n" + result.stderr

            if result.timedOut || result.exitCode != 0 {
                Issue.record("Fixture '\(fixture.name)' failed:\n\(output)")
            }
            #expect(!result.timedOut, "Fixture '\(fixture.name)' timed out")
            #expect(result.exitCode == 0, "Fixture '\(fixture.name)' must compile")
            assertNoCompilerCrash(in: output, fixtureName: fixture.name)
        }
    }

    @Test("Compile-fail fixtures emit their expected diagnostics")
    func compileFailFixturesEmitExpectedDiagnostics() throws {
        let fixtures = try externalConsumerFixtures(expectation: .fail)
        #expect(!fixtures.isEmpty)

        for fixture in fixtures {
            let materializedURL = try materializeExternalConsumerFixture(fixture)
            defer { try? FileManager.default.removeItem(at: materializedURL) }

            let result = try runStrictConcurrencyBuild(packageURL: materializedURL)
            let output = result.stdout + "\n" + result.stderr
            let expectedDiagnostics = try expectedDiagnostics(for: fixture)

            if result.timedOut || result.exitCode == 0 {
                Issue.record("Fixture '\(fixture.name)' did not fail as expected:\n\(output)")
            }
            #expect(!result.timedOut, "Fixture '\(fixture.name)' timed out")
            #expect(result.exitCode != 0, "Fixture '\(fixture.name)' must fail compilation")
            for diagnostic in expectedDiagnostics {
                #expect(
                    output.contains(diagnostic),
                    "Fixture '\(fixture.name)' did not emit expected diagnostic: \(diagnostic)"
                )
            }
            assertNoCompilerCrash(in: output, fixtureName: fixture.name)
        }
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
}

private enum ExternalConsumerExpectation: String {
    case pass
    case fail
}

private struct ExternalConsumerFixture {
    let name: String
    let sourceURL: URL
    let expectation: ExternalConsumerExpectation
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
    let fixtureURLs = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !fixtureURLs.isEmpty else {
        throw ExternalConsumerFixtureError.emptyExpectation(expectation.rawValue)
    }

    return fixtureURLs.map { url in
        ExternalConsumerFixture(
            name: url.lastPathComponent,
            sourceURL: url,
            expectation: expectation
        )
    }
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
