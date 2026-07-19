import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftParser
import SwiftSyntax
import Testing
import Dispatch

@testable import InnoDIBuildSupport

@Suite("ValidationCoordinator")
struct ValidationCoordinatorTests {
    @Test("Validation state remains inside the invoking SwiftPM plugin work directory")
    func sharedValidationStateDirectoryRemainsInsidePluginWorkDirectory() {
        let sourcePluginOutput = URL(
            fileURLWithPath: "/tmp/build/plugins/outputs/Consumer/FeatureA/InnoDIDAGValidationPlugin",
            isDirectory: true
        )
        let alternatePluginOutput = URL(
            fileURLWithPath: "/tmp/build/plugins/outputs/Consumer/FeatureA/AlternateValidationPlugin",
            isDirectory: true
        )
        let outputsNamedTargetOutput = URL(
            fileURLWithPath: "/tmp/build/plugins/outputs/Consumer/outputs/InnoDIDAGValidationPlugin",
            isDirectory: true
        )
        let nestedPluginOutput = URL(
            fileURLWithPath: "/tmp/build/plugins/outputs/Consumer/FeatureA/InnoDIDAGValidationPlugin/work",
            isDirectory: true
        )
        for pluginWorkDirectory in [
            sourcePluginOutput,
            alternatePluginOutput,
            outputsNamedTargetOutput,
            nestedPluginOutput,
        ] {
            let expected = pluginWorkDirectory.appending(
                path: "innodi-dag-validation-state",
                directoryHint: .isDirectory
            )
            let actual = sharedValidationStateDirectory(
                forPluginOutputDirectory: pluginWorkDirectory
            )

            #expect(actual.standardizedFileURL.path == expected.standardizedFileURL.path)
            #expect(actual.deletingLastPathComponent().path == pluginWorkDirectory.path)
        }
    }

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

    @Test("Workspace snapshots can skip unreadable source files when requested")
    func workspaceSnapshotSkipsUnreadableSourceFilesWhenRequested() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try Data([0xff, 0xfe, 0xfd]).write(to: rootURL.appendingPathComponent("Broken.swift"), options: .atomic)
        try "struct Valid { let value = 1 }\n".write(
            to: rootURL.appendingPathComponent("Valid.swift"),
            atomically: true,
            encoding: .utf8
        )

        var skippedPaths: [String] = []
        let snapshot = try loadWorkspaceSourceSnapshot(rootPath: rootURL.path(percentEncoded: false)) { relativePath, _, _ in
            skippedPaths.append(relativePath)
        }

        var strictLoadFailed = false
        do {
            _ = try loadWorkspaceSourceSnapshot(rootPath: rootURL.path(percentEncoded: false))
        } catch {
            strictLoadFailed = true
        }

        #expect(snapshot.files.map(\.relativePath) == ["Valid.swift"])
        #expect(skippedPaths == ["Broken.swift"])
        #expect(strictLoadFailed)
    }

    @Test("Workspace snapshots reject missing and non-directory roots")
    func workspaceSnapshotRejectsInvalidRoots() throws {
        let missingRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-Missing-Root-\(UUID().uuidString)", isDirectory: true)

        do {
            _ = try loadWorkspaceSourceSnapshot(rootPath: missingRootURL.path(percentEncoded: false))
            Issue.record("Expected missing workspace root to throw")
        } catch {
            #expect(error.localizedDescription.contains("does not exist"))
        }

        let fileRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-File-Root-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: fileRootURL) }
        try "struct NotADirectory {}\n".write(to: fileRootURL, atomically: true, encoding: .utf8)

        do {
            _ = try loadWorkspaceSourceSnapshot(rootPath: fileRootURL.path(percentEncoded: false))
            Issue.record("Expected file workspace root to throw")
        } catch {
            #expect(error.localizedDescription.contains("not a directory"))
        }

        if geteuid() != 0 {
            let unreadableRootURL = try makeTemporaryRoot()
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: unreadableRootURL.path(percentEncoded: false)
                )
                try? FileManager.default.removeItem(at: unreadableRootURL)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000],
                ofItemAtPath: unreadableRootURL.path(percentEncoded: false)
            )

            do {
                _ = try loadWorkspaceSourceSnapshot(rootPath: unreadableRootURL.path(percentEncoded: false))
                Issue.record("Expected unreadable workspace root to throw")
            } catch {
                #expect(error.localizedDescription.contains("not readable"))
            }
        }
    }

    @Test("Workspace discovery prunes Xcode project and workspace bundles")
    func workspaceDiscoveryPrunesXcodeBundles() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceDirectory = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let projectDirectory = rootURL.appendingPathComponent("Sample.xcodeproj", isDirectory: true)
        let workspaceDirectory = rootURL.appendingPathComponent("Sample.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)

        try "struct AppSource {}\n".write(
            to: sourceDirectory.appendingPathComponent("AppSource.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct ProjectGenerated {}\n".write(
            to: projectDirectory.appendingPathComponent("ProjectGenerated.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct WorkspaceGenerated {}\n".write(
            to: workspaceDirectory.appendingPathComponent("WorkspaceGenerated.swift"),
            atomically: true,
            encoding: .utf8
        )

        let files = try discoverWorkspaceSourceFiles(rootPath: rootURL.path(percentEncoded: false))

        #expect(files == ["Sources/AppSource.swift"])
    }

    @Test("External workspace relative paths include a stable full-path discriminator")
    func externalWorkspaceRelativePathsAreCollisionResistant() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstExternal = rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("First", isDirectory: true)
            .appendingPathComponent("Generated", isDirectory: true)
            .appendingPathComponent("Feature.swift")
        let secondExternal = rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("Second", isDirectory: true)
            .appendingPathComponent("Generated", isDirectory: true)
            .appendingPathComponent("Feature.swift")

        let first = workspaceRelativePath(
            of: firstExternal.path(percentEncoded: false),
            fromRoot: rootURL.path(percentEncoded: false)
        )
        let second = workspaceRelativePath(
            of: secondExternal.path(percentEncoded: false),
            fromRoot: rootURL.path(percentEncoded: false)
        )

        #expect(first.hasPrefix("__external__/"))
        #expect(second.hasPrefix("__external__/"))
        #expect(first.hasSuffix("/Generated/Feature.swift"))
        #expect(second.hasSuffix("/Generated/Feature.swift"))
        #expect(first != second)
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

    @Test("Corrupted AST digest manifests are treated as cache misses and rewritten")
    func corruptedManifestIsRecoveredAsCacheMiss() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let manifestURL = fixture.stateURL.appendingPathComponent("ast-digest-cache.json")
        try Data("{".utf8).write(to: manifestURL, options: .atomic)

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        let result = try collector.collectWithMetrics(rootPath: fixture.rootURL.path(percentEncoded: false))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: manifestURL.path(percentEncoded: false)
        )
        let manifest = try loadDigestManifest(at: manifestURL)

        #expect(result.reasonCodes.contains(.cacheMissManifestCorrupted))
        #expect(result.reasonCodes.contains(.cacheMissManifestVersion) == false)
        #expect(result.metrics.astReparseCount == 1)
        #expect(parser.parseCount == 1)
        #expect(manifest.version == ValidationDigestManifest.currentVersion)
        #expect(manifest.files.keys.sorted() == ["Feature.swift"])
    }

    @Test("Unreadable AST digest manifests do not count as corruption")
    func unreadableManifestFallsBackWithoutCorruptionReason() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let manifestURL = fixture.stateURL.appendingPathComponent("ast-digest-cache.json")
        let expectedManifest = ValidationDigestManifest(
            files: [
                "Feature.swift": ValidationFileDigestRecord(
                    fingerprint: ValidationFileFingerprint(fileSize: 1, modifiedAt: 1),
                    contentHash: "hash",
                    digest: "digest"
                )
            ]
        )
        try JSONEncoder().encode(expectedManifest).write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: manifestURL.path(percentEncoded: false)
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: manifestURL.path(percentEncoded: false)
            )
        }

        let loaded = try loadManifest(at: manifestURL)

        #expect(!loaded.invalidatedByCorruption)
        #expect(!loaded.invalidatedByVersion)
        #expect(loaded.manifest.files.isEmpty)
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

    @Test("Signature output retains only syntax trees parsed by the current collection")
    func signatureOutputRetainsCurrentReparses() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        let first = try collector.collectOutput(
            rootPath: fixture.rootURL.path(percentEncoded: false)
        )
        #expect(first.result.metrics.astReparseCount == 1)
        #expect(first.parsedSources.keys.sorted() == ["Feature.swift"])

        let second = try collector.collectOutput(
            rootPath: fixture.rootURL.path(percentEncoded: false)
        )
        #expect(second.result.metrics.metadataCacheHitCount == 1)
        #expect(second.result.metrics.astReparseCount == 0)
        #expect(second.parsedSources.isEmpty)

        try "struct Feature { let value = 2 }\n".write(
            to: fixture.rootURL.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )
        let third = try collector.collectOutput(
            rootPath: fixture.rootURL.path(percentEncoded: false)
        )
        #expect(third.result.metrics.astReparseCount == 1)
        #expect(third.parsedSources.keys.sorted() == ["Feature.swift"])
        #expect(
            third.parsedSources["Feature.swift"]?.description.contains(
                "let value = 2"
            ) == true
        )
    }

    @Test("One-shot signature collection ignores existing AST digest manifests")
    func oneShotSignatureCollectionIgnoresExistingManifestCache() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let featureURL = fixture.rootURL.appendingPathComponent("Feature.swift")
        let resourceValues = try featureURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let manifestURL = fixture.stateURL.appendingPathComponent("ast-digest-cache.json")
        let staleManifest = ValidationDigestManifest(
            files: [
                "Feature.swift": ValidationFileDigestRecord(
                    fingerprint: ValidationFileFingerprint(
                        fileSize: resourceValues.fileSize ?? 0,
                        modifiedAt: resourceValues.contentModificationDate?.timeIntervalSince1970 ?? 0
                    ),
                    contentHash: "stale-content-hash",
                    digest: "stale-normalized-digest"
                )
            ]
        )
        try JSONEncoder().encode(staleManifest).write(to: manifestURL, options: .atomic)

        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            parser: parser
        )

        let result = try collector.collectWithMetrics(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            persistManifestUpdates: false,
            useManifestCache: false
        )
        let manifestAfter = try loadDigestManifest(at: manifestURL)

        #expect(parser.parseCount == 1)
        #expect(result.metrics.metadataCacheHitCount == 0)
        #expect(result.metrics.contentHashReuseCount == 0)
        #expect(result.metrics.astReparseCount == 1)
        #expect(result.reasonCodes.contains(.cacheHitMetadata) == false)
        #expect(result.reasonCodes.contains(.cacheHitContentHash) == false)
        #expect(manifestAfter == staleManifest)
    }

    @Test("One-shot signature collection does not create a missing state directory")
    func oneShotSignatureCollectionAvoidsStateDirectoryCreation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let missingStateURL = fixture.rootURL.appendingPathComponent("missing-state", isDirectory: true)
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: missingStateURL.path(percentEncoded: false),
            parser: MockValidationSyntaxParser()
        )

        let result = try collector.collectWithMetrics(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            persistManifestUpdates: false
        )

        #expect(result.metrics.astReparseCount == 1)
        #expect(FileManager.default.fileExists(atPath: missingStateURL.path(percentEncoded: false)) == false)
    }

    @Test("Validation signature collection result is codable")
    func validationSignatureCollectionResultIsCodable() throws {
        let result = ValidationSignatureCollectionResult(
            signature: "abc123",
            metrics: ValidationSignatureMetrics(
                scannedFileCount: 3,
                metadataCacheHitCount: 1,
                contentHashReuseCount: 1,
                astReparseCount: 1
            ),
            reasonCodes: [.cacheHitMetadata, .cacheMissContentChanged],
            fileChanges: ValidationFileChangeDetails(
                newFiles: ["Added.swift"],
                deletedFiles: ["Removed.swift"],
                reparsedFiles: ["Feature.swift"],
                contentHashReusedFiles: ["Stable.swift"]
            )
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ValidationSignatureCollectionResult.self, from: data)

        #expect(decoded == result)
    }

    @Test("Validation issue renderer emits an empty stderr string for no issues")
    func validationIssueRendererReturnsEmptyStringForNoIssues() {
        #expect(ValidationIssueRenderer.renderStderr(issues: []) == "")
    }

    @Test("Validation issue renderer sanitizes markdown and stderr content")
    func validationIssueRendererSanitizesRenderedContent() {
        let issue = ValidationIssue(
            code: "validation.issue",
            severity: .error,
            message: "bad `message`\nnext line",
            location: ValidationIssueLocation(filePath: "Sources/Feature`\n.swift", line: 3, column: 7),
            notes: [
                ValidationIssueNote(
                    message: "note with\nbreak",
                    location: ValidationIssueLocation(filePath: "Sources/Note.swift", line: 1, column: 2)
                )
            ],
            remediation: "fix\nthis",
            metadata: ["reason": "uses `code`\nblock"]
        )

        let markdown = ValidationIssueRenderer.renderMarkdown(issues: [issue])
        let stderr = ValidationIssueRenderer.renderStderr(issues: [issue])

        #expect(markdown.contains("bad 'message' next line"))
        #expect(markdown.contains("Sources/Feature' .swift:3:7"))
        #expect(markdown.contains("uses 'code' block"))
        #expect(stderr.contains("[validation.issue] bad 'message' next line"))
        #expect(stderr.contains("note: note with break"))
    }

    @Test("Validation issue renderer markdown always ends with a trailing newline")
    func validationIssueRendererMarkdownAlwaysEndsWithTrailingNewline() {
        let issue = ValidationIssue(
            code: "validation.issue",
            severity: .error,
            message: "needs newline",
            location: ValidationIssueLocation(filePath: "Feature.swift", line: 1, column: 1)
        )

        let markdown = ValidationIssueRenderer.renderMarkdown(issues: [issue])

        #expect(markdown.hasSuffix("\n"))
    }

    @Test("Validation sleep propagates task cancellation")
    func validationSleepPropagatesCancellation() async {
        let task = Task {
            do {
                try await validationSleep(5)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        task.cancel()

        #expect(await task.value)
    }

    @Test("Validation issue report only fails on error severity")
    func validationIssueReportOnlyFailsOnErrors() {
        let location = ValidationIssueLocation(filePath: "Feature.swift", line: 1, column: 1)
        let warning = ValidationIssue(
            code: "validation.warning",
            severity: .warning,
            message: "warning only",
            location: location
        )
        let note = ValidationIssue(
            code: "validation.note",
            severity: .note,
            message: "note only",
            location: location
        )
        let error = ValidationIssue(
            code: "validation.error",
            severity: .error,
            message: "error only",
            location: location
        )

        let nonFailingReport = ValidationIssueReport(issues: [warning, note])
        #expect(nonFailingReport.hasFailures == false)
        #expect(nonFailingReport.asCommandResult() == nil)

        let failingReport = ValidationIssueReport(issues: [warning, error, note])
        let commandResult = failingReport.asCommandResult()
        #expect(failingReport.hasFailures == true)
        #expect(commandResult?.exitCode == 1)
        #expect(commandResult?.stderr.contains("[validation.error] error only") == true)
        #expect(commandResult?.stderr.contains("[validation.warning]") == false)
    }

    @Test("Live validation command runner drains large process output without deadlock")
    func liveValidationCommandRunnerHandlesLargeOutput() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let scriptURL = fixture.rootURL.appendingPathComponent("emit-large-output.sh")
        try """
        #!/bin/sh
        i=0
        while [ "$i" -lt 3000 ]; do
          printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\\n'
          i=$((i + 1))
        done
        printf 'stderr complete\\n' >&2
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path(percentEncoded: false)
        )

        let result = try LiveValidationCommandRunner().runValidationTool(
            toolPath: scriptURL.path(percentEncoded: false),
            rootPath: fixture.rootURL.path(percentEncoded: false)
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.count > 150_000)
        #expect(result.stderr.contains("stderr complete"))
    }

    @Test("Default coordinator honors an external validation tool path")
    func defaultCoordinatorHonorsExternalToolPath() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let scriptURL = fixture.rootURL.appendingPathComponent("external-validator.sh")
        try """
        #!/bin/sh
        printf 'external validator marker\\n'
        exit 0
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path(percentEncoded: false)
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: scriptURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false)
        )

        #expect(outcome.result.exitCode == 0)
        #expect(outcome.result.stdout.contains("external validator marker"))
    }

    @Test("Default coordinator falls back to in-process validation without a tool path")
    func defaultCoordinatorFallsBackToInProcessWithoutToolPath() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: nil,
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false)
        )

        #expect(outcome.result.exitCode == 0)
        #expect(outcome.result.stdout.contains("DAG validation passed"))
    }

    @Test("Success result is reused for identical input signature")
    func successResultIsReused() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let first = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )
        let second = try await ValidationCoordinator.coordinate(
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
    func coordinatorWritesMetricsArtifacts() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let first = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            verboseLoggingEnabled: true
        )
        let second = try await ValidationCoordinator.coordinate(
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
        #expect(firstArtifact.reasonCodes.contains(.liveRunSemanticValidation))
        #expect(firstArtifact.reasonCodes.contains(.liveRunDAGValidation))
        #expect(firstArtifact.liveRunMetrics.semanticValidationMilliseconds >= 0)
        #expect(firstArtifact.fileChanges.newFiles == ["Feature.swift"])
        #expect(firstArtifact.fileChanges.reparsedFiles == ["Feature.swift"])
        #expect(firstSummary.contains("# InnoDI Validation Summary"))
        #expect(firstSummary.contains("cache-miss-new-file"))
        #expect(firstSummary.contains("live-run-semantic-validation"))
        #expect(firstSummary.contains("Semantic validation"))
        #expect(firstSummary.contains("### Reparsed files"))
        #expect(firstSummary.contains("`Feature.swift`"))
        #expect(first.verboseSummary?.contains("semantic-ms=") == true)
        #expect(first.verboseSummary?.contains("[InnoDI]") == true)
        #expect(second.verboseSummary == nil)
    }

    @Test("Semantic validation fails on same-module Lazy and Provider collisions before DAG runner executes")
    func semanticValidationFailsOnLocalWrapperCollisions() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct Config {}
        struct Service {}
        struct Lazy<T> {}
        struct Provider<T> {}

        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { (lazyConfig: Lazy<Config>, serviceProvider: Provider<Service>) in
                Service()
            })
            var service: Service
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("SemanticWrappers.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("provide.deferred-wrapper-qualification-required"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.count == 2)
        #expect(outcome.metricsArtifact.liveRunMetrics.semanticValidationMilliseconds >= 0)
        #expect(outcome.metricsArtifact.liveRunMetrics.dagValidationMilliseconds == 0)
        #expect(outcome.metricsArtifact.issues.contains { $0.metadata["writtenHead"] == "Lazy" })
        #expect(outcome.metricsArtifact.issues.contains { $0.metadata["writtenHead"] == "Provider" })
        #expect(runner.invocationCount == 0)
    }

    @Test("Semantic validation rejects wrapper aliases before DAG runner executes")
    func semanticValidationRejectsWrapperAliases() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct Config {}
        struct Service {}
        typealias DeferredLazy<T> = InnoDI.Lazy<T>
        typealias DeferredProvider<T> = InnoDI.Provider<T>

        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { (lazyConfig: DeferredLazy<Config>, serviceProvider: DeferredProvider<Service>) in
                Service()
            })
            var service: Service
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("SemanticWrapperAliases.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("provide.deferred-wrapper-alias-unsupported"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.filter { $0.severity == .error }.count == 2)
        #expect(outcome.metricsArtifact.issues.contains { $0.metadata["writtenHead"] == "DeferredLazy" })
        #expect(outcome.metricsArtifact.issues.contains { $0.metadata["writtenHead"] == "DeferredProvider" })
        // Alias warnings must surface in the markdown-summary artifact alongside
        // the JSON metrics; the sharedArtifact path previously dropped them.
        #expect(outcome.metricsArtifact.issues.contains {
            $0.code == "deferred-alias.workspace-finding" && $0.severity == .warning
        })
        let summary = try String(
            contentsOf: fixture.outputAURL.appendingPathComponent("dag-validation-summary.md"),
            encoding: .utf8
        )
        #expect(summary.contains("deferred-alias.workspace-finding"))
        #expect(runner.invocationCount == 0)
    }

    @Test("Qualified InnoDI deferred wrappers pass semantic validation and reach the DAG runner")
    func qualifiedDeferredWrappersPassSemanticValidation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct Config {}
        struct Service {}

        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { (lazyConfig: InnoDI.Lazy<Config>, serviceProvider: InnoDI.Provider<Service>) in
                Service()
            })
            var service: Service
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("QualifiedDeferredWrappers.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 0)
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticValidation))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunDAGValidation))
        #expect(outcome.metricsArtifact.issues.isEmpty)
        #expect(runner.invocationCount == 1)
    }

    @Test("Qualified InnoDI containers still reject wrapper aliases before DAG runner executes")
    func qualifiedContainerWrapperAliasesAreRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct Config {}
        struct Service {}
        typealias DeferredLazy<T> = InnoDI.Lazy<T>
        typealias DeferredProvider<T> = InnoDI.Provider<T>

        @InnoDI.DIContainer
        struct AppContainer {
            @InnoDI.Provide(.shared, factory: { (lazyConfig: DeferredLazy<Config>, serviceProvider: DeferredProvider<Service>) in
                Service()
            })
            var service: Service
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("QualifiedSemanticWrapperAliases.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("provide.deferred-wrapper-alias-unsupported"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.filter { $0.severity == .error }.count == 2)
        #expect(outcome.metricsArtifact.issues.contains { $0.metadata["writtenHead"] == "DeferredLazy" })
        #expect(outcome.metricsArtifact.issues.contains { $0.metadata["writtenHead"] == "DeferredProvider" })
        #expect(runner.invocationCount == 0)
    }

    @Test("Semantic validation rejects bindings: that target an unknown child input")
    func semanticValidationRejectsUnknownChildInputBinding() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct AppConfig {}

        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var config: AppConfig
        }

        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var appConfig: AppConfig

            @SubContainer(
                scope: .shared,
                bindings: [(child: \\FeatureContainer.missing, parent: \\AppContainer.appConfig)]
            )
            var feature: FeatureContainer
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("UnknownChildInputBinding.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("sub.unknown-child-input"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(outcome.metricsArtifact.issues.first?.metadata["childContainerPath"] == "FeatureContainer")
        #expect(runner.invocationCount == 0)
    }

    @Test("Semantic validation preserves malformed bindings as an error")
    func semanticValidationRejectsMalformedBindings() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct AppConfig {}

        let explicitBindings = [(child: \\FeatureContainer.config, parent: \\AppContainer.appConfig)]

        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var config: AppConfig
        }

        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var appConfig: AppConfig

            @SubContainer(scope: .shared, bindings: explicitBindings)
            var feature: FeatureContainer
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("MalformedBindings.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("sub.invalid-bindings"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(outcome.metricsArtifact.issues.first?.metadata["subContainerMemberName"] == "feature")
        #expect(runner.invocationCount == 0)
    }

    @Test("Semantic validation rejects duplicate binding tuple labels before DAG runner executes")
    func semanticValidationRejectsDuplicateBindingTupleLabels() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct AppConfig {}

        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var config: AppConfig
        }

        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var appConfig: AppConfig

            @SubContainer(
                scope: .shared,
                bindings: [(child: \\.config, child: \\.appConfig)]
            )
            var feature: FeatureContainer
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("DuplicateBindingLabels.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("sub.invalid-bindings"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(runner.invocationCount == 0)
    }

    @Test("Qualified InnoDI containers still reject bindings: that target an unknown child input")
    func qualifiedContainersRejectUnknownChildInputBinding() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct AppConfig {}

        @InnoDI.DIContainer
        struct FeatureContainer {
            @InnoDI.Provide(.input)
            var config: AppConfig
        }

        @InnoDI.DIContainer
        struct AppContainer {
            @InnoDI.Provide(.input)
            var appConfig: AppConfig

            @InnoDI.SubContainer(
                scope: .shared,
                bindings: [(child: \\FeatureContainer.missing, parent: \\AppContainer.appConfig)]
            )
            var feature: FeatureContainer
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("QualifiedUnknownChildInputBinding.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("sub.unknown-child-input"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(outcome.metricsArtifact.issues.first?.metadata["childContainerPath"] == "FeatureContainer")
        #expect(runner.invocationCount == 0)
    }

    @Test("Semantic validation still rejects unknown child input bindings when validateDAG is false")
    func semanticValidationStillRejectsUnknownChildInputBindingForOptedOutContainer() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct AppConfig {}

        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var config: AppConfig
        }

        @DIContainer(validateDAG: false)
        struct AppContainer {
            @Provide(.input)
            var appConfig: AppConfig

            @SubContainer(
                scope: .shared,
                bindings: [(child: \\FeatureContainer.missing, parent: \\AppContainer.appConfig)]
            )
            var feature: FeatureContainer
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("OptedOutUnknownChildInputBinding.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("sub.unknown-child-input"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(outcome.metricsArtifact.issues.first?.metadata["childContainerPath"] == "FeatureContainer")
        #expect(runner.invocationCount == 0)
    }

    @Test("Legacy shared-run cache directories without a version salt are ignored")
    func legacySharedRunCacheDirectoriesAreIgnored() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let legacyDirectory = fixture.stateURL.appendingPathComponent(signature, isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try persistJSON(
            ValidationCommandResult(exitCode: 0, stdout: "legacy\n", stderr: ""),
            to: legacyDirectory.appendingPathComponent("result.json")
        )
        try persistJSON(
            SharedValidationRunRecord(
                liveRunMetrics: ValidationLiveRunMetrics(
                    customInitValidationMilliseconds: 1,
                    semanticValidationMilliseconds: 1,
                    hierarchyValidationMilliseconds: 0,
                    dagValidationMilliseconds: 1
                ),
                reasonCodes: [.liveRunSemanticValidation, .liveRunDAGValidation],
                issues: []
            ),
            to: legacyDirectory.appendingPathComponent("validation-metrics.json")
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "fresh\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.wasCached == false)
        #expect(outcome.result.stdout == "fresh\n")
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticValidation))
        #expect(runner.invocationCount == 1)
        #expect(FileManager.default.fileExists(atPath: legacyDirectory.path(percentEncoded: false)) == false)
    }

    @Test("Corrupt current-version shared-run metrics fall back to a live validation run")
    func corruptCurrentVersionSharedRunMetricsFallBackToLiveRun() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)
        try persistJSON(
            ValidationCommandResult(exitCode: 0, stdout: "legacy\n", stderr: ""),
            to: sharedRunDirectory.appendingPathComponent("result.json")
        )
        try Data("{\"liveRunMetrics\":{}}".utf8).write(
            to: sharedRunDirectory.appendingPathComponent("validation-metrics.json"),
            options: .atomic
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "fresh\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.wasCached == false)
        #expect(outcome.result.stdout == "fresh\n")
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticValidation))
        #expect(runner.invocationCount == 1)

        let repairedRecord = try loadSharedValidationRunRecord(
            at: sharedRunDirectory.appendingPathComponent("validation-metrics.json")
        )
        #expect(repairedRecord.liveRunMetrics.semanticValidationMilliseconds >= 0)
    }

    @Test("Dead-owner lock files are recovered before live validation continues")
    func deadOwnerLockIsRecoveredBeforeLiveValidation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let clock = ManualValidationCoordinatorClock(
            startUptime: 100,
            startDate: Date(timeIntervalSince1970: 10_000)
        )
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: clock.currentDate.addingTimeInterval(-120).timeIntervalSince1970
            ),
            to: sharedRunDirectory.appendingPathComponent("lock")
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: .default,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [4242])
        )

        #expect(outcome.result.exitCode == 0)
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.staleLockRecovered))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.liveRunDAGValidation))
        #expect(runner.invocationCount == 1)
        #expect(clock.sleptDurations.isEmpty)
    }

    @Test("Corrupt legacy lock files older than the stale threshold are recovered")
    func corruptLegacyLockFileIsRecovered() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let clock = ManualValidationCoordinatorClock(
            startUptime: 50,
            startDate: Date(timeIntervalSince1970: 20_000)
        )
        let lockURL = sharedRunDirectory.appendingPathComponent("lock")
        try Data("legacy-lock".utf8).write(to: lockURL, options: .atomic)
        try touch(lockURL, modifiedAt: clock.currentDate.addingTimeInterval(-120))

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: .default,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [4242])
        )

        #expect(outcome.result.exitCode == 0)
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.staleLockRecovered))
        #expect(runner.invocationCount == 1)
        #expect(clock.sleptDurations.isEmpty)
    }

    @Test("releaseLock removes the matching lock file")
    func releaseLockRemovesMatchingLockFile() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let descriptor = try #require(try acquireLock(at: lockURL))

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)))

        releaseLock(descriptor: descriptor, at: lockURL)

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)) == false)
    }

    @Test("acquireLock holds an advisory flock that blocks a second acquirer on the same descriptor")
    func acquireLockHoldsAdvisoryFlock() throws {
        // Item 1.C — `acquireLock` layers `flock(LOCK_EX | LOCK_NB)`
        // on top of `O_CREAT | O_EXCL`. We assert the advisory layer
        // is actually held by opening the same path independently
        // (without O_EXCL, so the open itself does not contend) and
        // confirming flock reports `EWOULDBLOCK`.
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let descriptor = try #require(try acquireLock(at: lockURL))
        defer { releaseLock(descriptor: descriptor, at: lockURL) }

        // Independent descriptor pointing at the same inode.
        let path = lockURL.path(percentEncoded: false)
        let secondDescriptor = path.withCString { open($0, O_RDWR) }
        try #require(secondDescriptor >= 0)
        defer { close(secondDescriptor) }

        let result = flock(secondDescriptor, LOCK_EX | LOCK_NB)
        let savedErrno = errno
        #expect(result == -1, "Expected flock contention; got result \(result)")
        #expect(
            savedErrno == EWOULDBLOCK || savedErrno == EAGAIN,
            "Expected EWOULDBLOCK/EAGAIN; got errno \(savedErrno)"
        )
    }

    @Test("acquireLock removes the lock file after release and allows reacquire")
    func acquireLockDoesNotLeaveLockFileAfterReleaseAndReacquire() throws {
        // Indirect coverage: O_EXCL prevents directly reproducing a lone
        // advisory-flock failure in acquireLock. This exercises the cleanup
        // path around ValidationCoordinator+Locking.swift's close/removeItem
        // pairing by acquiring, releasing, confirming the file is gone, and
        // reacquiring at the same path.
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let first = try #require(try acquireLock(at: lockURL))
        releaseLock(descriptor: first, at: lockURL)

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)) == false)

        let second = try #require(try acquireLock(at: lockURL))
        releaseLock(descriptor: second, at: lockURL)
    }

    @Test("lock policy warns on invalid allow-unsafe environment value")
    func lockPolicyWarnsOnInvalidAllowUnsafeEnvironmentValue() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.allowUnsafeLock: "maybe"
            ],
            warningHandler: { warnings.append($0) }
        )

        #expect(policy.allowUnsafeFilesystem == false)
        #expect(warnings == [
            "InnoDI: ignoring invalid INNODI_ALLOW_UNSAFE_LOCK=maybe; falling back to false."
        ])
    }

    @Test("releaseLock does not delete a replacement file recreated at the same path")
    func releaseLockDoesNotDeleteReplacementFile() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let descriptor = try #require(try acquireLock(at: lockURL))

        try FileManager.default.removeItem(at: lockURL)
        try Data("replacement".utf8).write(to: lockURL, options: .atomic)

        releaseLock(descriptor: descriptor, at: lockURL)

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)))
        let contents = try String(contentsOf: lockURL, encoding: .utf8)
        #expect(contents == "replacement")
    }

    @Test("Stale-lock recovery is serialized before a fresh live lock is acquired")
    func staleLockRecoveryIsSerializedBeforeFreshLiveLock() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let lockURL = sharedRunDirectory.appendingPathComponent("lock")
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: Date().addingTimeInterval(-120).timeIntervalSince1970
            ),
            to: lockURL
        )

        let recoveryPointReached = LockedFlag()
        let allowRecovery = DispatchSemaphore(value: 0)
        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ],
            delay: 0.2
        )
        let policy = ValidationCoordinatorLockPolicy(
            // maxWaitSeconds is a bail-out, not a measured behavior: this
            // test asserts recovery serialization, and a small wait budget
            // lets CPU-starved CI runs time out the contender while the
            // holder's live run is still in flight.
            maxWaitSeconds: 30,
            staleLockAgeSeconds: 0.1,
            initialBackoffSeconds: 0.01,
            maxBackoffSeconds: 0.05
        )

        let runtimeA = ValidationCoordinatorRuntime(
            monotonicNow: validationNow,
            currentDate: Date.init,
            sleep: validationSleep,
            currentProcessID: { 2001 },
            processExists: { [2001, 2002].contains($0) },
            beforeStaleLockRemoval: { _ in
                recoveryPointReached.markTrue()
                // Generous bail-out only: the test signals as soon as the
                // contender reaches its wait loop. A short timeout here lets
                // a CPU-starved CI runner break the intended interleaving by
                // resuming recovery before the contender ever runs.
                _ = allowRecovery.wait(timeout: .now() + .seconds(60))
            }
        )
        // Marks the moment the contender enters a coordinator wait loop: its
        // first backoff sleep can only happen after it observed the lock
        // state A is holding, which is the readiness point the test needs
        // before letting A's recovery proceed.
        let contenderReachedBackoff = LockedFlag()
        let runtimeB = ValidationCoordinatorRuntime(
            monotonicNow: validationNow,
            currentDate: Date.init,
            sleep: { interval in
                contenderReachedBackoff.markTrue()
                try await validationSleep(interval)
            },
            currentProcessID: { 2002 },
            processExists: { [2001, 2002].contains($0) }
        )

            let outcomes = try await withThrowingTaskGroup(of: ValidationExecutionOutcome.self) { group in
            group.addTask {
                try await ValidationCoordinator.coordinate(
                    rootPath: fixture.rootURL.path(percentEncoded: false),
                    toolPath: "/usr/bin/true",
                    stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                    outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
                    runner: runner,
                    lockPolicy: policy,
                    runtime: runtimeA
                )
            }

            // The 60-second ceilings below are pure bail-outs; both loops
            // normally exit within milliseconds. Parallel CI runs have
            // starved this suite for minutes, so a ~1-second readiness
            // window flakes even though the interleaving itself is sound.
            for _ in 0..<6000 {
                if recoveryPointReached.isSet {
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }

            #expect(recoveryPointReached.isSet)

            group.addTask {
                try await ValidationCoordinator.coordinate(
                    rootPath: fixture.rootURL.path(percentEncoded: false),
                    toolPath: "/usr/bin/true",
                    stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                    outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
                    runner: runner,
                    lockPolicy: policy,
                    runtime: runtimeB
                )
            }

            for _ in 0..<6000 {
                if contenderReachedBackoff.isSet {
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }

            #expect(contenderReachedBackoff.isSet)
            allowRecovery.signal()

            var collected: [ValidationExecutionOutcome] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(outcomes.count == 2)
        #expect(runner.invocationCount == 1)
        #expect(outcomes.contains { !$0.wasCached })
        #expect(outcomes.contains { $0.wasCached })
        #expect(outcomes.allSatisfy { $0.result.exitCode == 0 })
        #expect(outcomes.allSatisfy { $0.metricsArtifact.reasonCodes.contains(ValidationReasonCode.staleLockRecovered) })
        #expect(FileManager.default.fileExists(atPath: lockURL.appendingPathExtension("recovering").path(percentEncoded: false)) == false)
    }

    @Test("Terminal reconciliation returns a cached result written during the final backoff")
    func terminalReconciliationReturnsCachedResultWrittenDuringFinalBackoff() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let policy = ValidationCoordinatorLockPolicy(
            maxWaitSeconds: 0.3,
            staleLockAgeSeconds: 0.1,
            initialBackoffSeconds: 0.05,
            maxBackoffSeconds: 0.2
        )
        let cachedResult = ValidationCommandResult(exitCode: 0, stdout: "cached\n", stderr: "")
        let cachedRecord = SharedValidationRunRecord(
            liveRunMetrics: ValidationLiveRunMetrics(
                customInitValidationMilliseconds: 1,
                semanticValidationMilliseconds: 2,
                hierarchyValidationMilliseconds: 0,
                dagValidationMilliseconds: 3
            ),
            reasonCodes: [.liveRunSemanticValidation, .liveRunDAGValidation],
            issues: []
        )
        let lockURL = sharedRunDirectory.appendingPathComponent("lock")
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: Date(timeIntervalSince1970: 30_000).timeIntervalSince1970
            ),
            to: lockURL
        )

        let cacheWriteState = SleepThresholdState(threshold: policy.maxWaitSeconds)
        let clock = ManualValidationCoordinatorClock(
            startUptime: 10,
            startDate: Date(timeIntervalSince1970: 30_000),
            onSleep: { interval in
                guard cacheWriteState.shouldTrigger(afterSleeping: interval) else {
                    return
                }

                try! persistJSON(cachedRecord, to: sharedRunDirectory.appendingPathComponent("validation-metrics.json"))
                try! persistJSON(cachedResult, to: sharedRunDirectory.appendingPathComponent("result.json"))
                try? FileManager.default.removeItem(at: lockURL)
            }
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: policy,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [1111, 4242])
        )

        #expect(outcome.wasCached == true)
        #expect(outcome.result == cachedResult)
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.liveRunSemanticValidation))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.liveRunDAGValidation))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.lockContentionTimeout) == false)
        #expect(clock.sleptDurations.count == 3)
        #expect(runner.invocationCount == 0)
    }

    @Test("Active locks time out predictably instead of retrying indefinitely")
    func activeLockTimesOutPredictably() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let clock = ManualValidationCoordinatorClock(
            startUptime: 10,
            startDate: Date(timeIntervalSince1970: 30_000)
        )
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: clock.currentDate.timeIntervalSince1970
            ),
            to: sharedRunDirectory.appendingPathComponent("lock")
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )
        let policy = ValidationCoordinatorLockPolicy(
            maxWaitSeconds: 0.3,
            staleLockAgeSeconds: 0.1,
            initialBackoffSeconds: 0.05,
            maxBackoffSeconds: 0.2
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: policy,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [1111, 4242])
        )

        let summary = try String(
            contentsOf: fixture.outputAURL.appendingPathComponent("dag-validation-summary.md"),
            encoding: .utf8
        )

        #expect(outcome.wasCached == false)
        #expect(outcome.result.exitCode == 1)
        // The lock-timeout stderr block is documented in
        // `Sources/InnoDI/InnoDI.docc/lock-safety.md`. Assert on the
        // structural elements rather than the exact wording so future
        // copy edits do not require lockstep test changes.
        let stderr = outcome.result.stderr
        #expect(stderr.contains("Timed out waiting"))
        #expect(stderr.contains("InnoDI validation coordinator lock"))
        #expect(stderr.contains("path:"))
        #expect(stderr.contains("waited:"))
        #expect(stderr.contains("Suggested actions:"))
        #expect(stderr.contains("INNODI_LOCK_TIMEOUT"))
        #expect(stderr.contains("--scratch-path"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.lockContentionTimeout))
        #expect(outcome.metricsArtifact.issues.isEmpty)
        #expect(outcome.metricsArtifact.liveRunMetrics.customInitValidationMilliseconds == 0)
        #expect(outcome.metricsArtifact.liveRunMetrics.semanticValidationMilliseconds == 0)
        #expect(outcome.metricsArtifact.liveRunMetrics.dagValidationMilliseconds == 0)
        #expect(summary.contains("lock-contention-timeout"))
        #expect(summary.contains("timed out waiting for an active lock"))
        #expect(clock.sleptDurations.count == 3)
        #expect(clock.totalSlept >= policy.maxWaitSeconds)
        #expect(runner.invocationCount == 0)
    }

    @Test("Failure result is reused for identical input signature")
    func failureResultIsReused() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 3, stdout: "", stderr: "DAG validation failed.\n")
            ]
        )

        let first = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/false",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )
        let second = try await ValidationCoordinator.coordinate(
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
                try await ValidationCoordinator.coordinate(
                    rootPath: fixture.rootURL.path(percentEncoded: false),
                    toolPath: "/usr/bin/true",
                    stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                    outputDirectoryPath: outputCURL.path(percentEncoded: false),
                    runner: runner
                )
            }
            group.addTask {
                try await ValidationCoordinator.coordinate(
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
        #expect(results.reduce(0) { $0 + $1.metricsArtifact.signatureMetrics.astReparseCount } == 1)
        #expect(results.contains { $0.metricsArtifact.signatureMetrics.metadataCacheHitCount == 1 })
    }

    @Test("Changing source input invalidates the cached result")
    func changingSourceInputInvalidatesCache() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "first\n", stderr: ""),
                ValidationCommandResult(exitCode: 0, stdout: "second\n", stderr: "")
            ]
        )

        let first = try await ValidationCoordinator.coordinate(
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

        let second = try await ValidationCoordinator.coordinate(
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
    func crossFileCustomInitValidationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeCrossFileCustomInitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
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

    @Test("Full-source qualifier validation fails before DAG runner executes")
    func qualifierValidationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIContainer(mainActor: true)
        struct AppContainer {
            @Provide(.input) var value: Int
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Swift {}\n".write(
            to: fixture.rootURL.appendingPathComponent("QualifierShadow.swift"),
            atomically: true,
            encoding: .utf8
        )
        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(
                    exitCode: 0,
                    stdout: "unexpected\n",
                    stderr: ""
                )
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(
            outcome.metricsArtifact.issues.map(\.code) == [
                "container.reserved-module-name"
            ]
        )
        #expect(
            outcome.metricsArtifact.reasonCodes.contains(
                .liveRunSemanticFailure
            )
        )
        #expect(runner.invocationCount == 0)
    }

    @Test("Unsupported container declarations fail once before downstream validation")
    func unsupportedContainerDeclarationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIComponent
        @DIContainer
        final class UnsupportedContainer {
            @Provide(.input)
            var config: String = ""

            @SubContainer(scope: .shared)
            var child: ChildContainer = ChildContainer()

            init() {}
        }

        @DIContainer
        struct ChildContainer {}
        """.write(
            to: fixture.rootURL.appendingPathComponent("UnsupportedContainer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == "container.unsupported-declaration-kind"
        )
        #expect(!outcome.result.stderr.contains("container.custom-init-unsupported"))
        #expect(!outcome.result.stderr.contains("sub."))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Private container declarations fail before downstream validation")
    func privateContainerDeclarationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIContainer
        private struct PrivateContainer {}
        """.write(
            to: fixture.rootURL.appendingPathComponent("PrivateContainer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == "container.private-access-unsupported"
        )
        #expect(
            outcome.metricsArtifact.issues.first?.message.contains(
                "'PrivateContainer' cannot be declared private"
            ) == true
        )
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Full-source preflight rejects containers inside computed-property accessors")
    func accessorLocalContainerFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct AccessorHost {
            var value: Int {
                @DIContainer
                struct AccessorContainer {}
                return 0
            }
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("AccessorContainer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == "container.local-declaration-unsupported"
        )
        #expect(
            outcome.metricsArtifact.issues.first?.message.contains(
                "'AccessorContainer' is declared in an executable code scope"
            ) == true
        )
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Same-file extension custom init conflicts fail before compilation")
    func sameFileCustomInitConflictsShortCircuitBuildValidator() async throws {
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

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == "container.custom-init-unsupported"
        )
        #expect(outcome.result.stderr.contains("extension"))
        #expect(runner.invocationCount == 0)
    }

    @Test("Conditional same-file extension initializers participate in build validation")
    func conditionalSameFileExtensionInitializersAreRejected() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer {
            #if os(macOS)
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
            #endif
        }
        """.write(
            to: rootURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CustomInitBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(result.issues.count == 1)
        #expect(result.issues.first?.code == "container.custom-init-unsupported")
        #expect(result.issues.first?.metadata["containerPath"] == "AppContainer")
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

        // Syntax-only validator boundary fixture. InnoDI 5.0 rejects this
        // declaration during macro expansion; it is not a supported example.
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

    @Test("Qualified InnoDI containers participate in custom-init build validation")
    func qualifiedContainersParticipateInCustomInitBuildValidation() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        struct Config {}

        @InnoDI.DIContainer
        struct AppContainer {
            @InnoDI.Provide(.input)
            var config: Config
        }
        """.write(
            to: rootURL.appendingPathComponent("QualifiedContainer.swift"),
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
            to: rootURL.appendingPathComponent("QualifiedContainer+Debug.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CustomInitBuildValidator.validate(rootPath: rootURL.path(percentEncoded: false))

        #expect(result.issues.count == 1)
        #expect(result.issues.first?.code == "container.custom-init-unsupported")
        #expect(result.issues.first?.metadata["containerPath"] == "AppContainer")
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
        let shortReverseSuffix = resolver.resolvePath(
            for: SemanticTypeReference(
                displayPath: "PreviewModule.AppContainer",
                components: ["PreviewModule", "AppContainer"]
            ),
            candidatePaths: ["AppContainer"]
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
        #expect(shortReverseSuffix.state == .unresolved)
    }
}

private final class MockValidationSyntaxParser: @unchecked Sendable, ValidationSyntaxParsing {
    private let lock = NSLock()
    private var storage: [String] = []

    var parsedSources: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var parseCount: Int {
        parsedSources.count
    }

    func parse(source: String) -> SourceFileSyntax {
        lock.lock()
        storage.append(source)
        lock.unlock()
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

private func loadSharedValidationRunRecord(at url: URL) throws -> SharedValidationRunRecord {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(SharedValidationRunRecord.self, from: data)
}

private func persistJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
    let data = try JSONEncoder().encode(value)
    try data.write(to: url, options: .atomic)
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

private func makeTestRuntime(
    clock: ManualValidationCoordinatorClock,
    currentPID: Int32,
    activePIDs: Set<Int32>,
    beforeStaleLockRemoval: @escaping @Sendable (URL) -> Void = { _ in }
) -> ValidationCoordinatorRuntime {
    ValidationCoordinatorRuntime(
        monotonicNow: { clock.monotonicNow },
        currentDate: { clock.currentDate },
        sleep: { interval in clock.sleep(interval) },
        currentProcessID: { currentPID },
        processExists: { activePIDs.contains($0) },
        beforeStaleLockRemoval: beforeStaleLockRemoval
    )
}

private final class ManualValidationCoordinatorClock: @unchecked Sendable {
    private let lock = NSLock()
    private let onSleep: (@Sendable (TimeInterval) -> Void)?
    private var uptime: TimeInterval
    private var date: Date
    private var recordedSleeps: [TimeInterval] = []

    init(
        startUptime: TimeInterval,
        startDate: Date,
        onSleep: (@Sendable (TimeInterval) -> Void)? = nil
    ) {
        self.onSleep = onSleep
        self.uptime = startUptime
        self.date = startDate
    }

    var monotonicNow: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return uptime
    }

    var currentDate: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    var sleptDurations: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSleeps
    }

    var totalSlept: TimeInterval {
        sleptDurations.reduce(0, +)
    }

    func sleep(_ interval: TimeInterval) {
        lock.lock()
        uptime += interval
        date = date.addingTimeInterval(interval)
        recordedSleeps.append(interval)
        let onSleep = self.onSleep
        lock.unlock()

        onSleep?(interval)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func markTrue() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private final class SleepThresholdState: @unchecked Sendable {
    private let lock = NSLock()
    private let threshold: TimeInterval
    private var totalSlept: TimeInterval = 0
    private var didTrigger = false

    init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    func shouldTrigger(afterSleeping interval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        totalSlept += interval
        guard didTrigger == false, totalSlept >= threshold else {
            return false
        }

        didTrigger = true
        return true
    }
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

    func runValidationTool(
        toolPath: String?,
        rootPath: String,
        snapshot: WorkspaceSourceSnapshot
    ) throws -> ValidationCommandResult {
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
