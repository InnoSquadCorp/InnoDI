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

    @Test("Parallel workspace snapshots preserve deterministic discovery order")
    func parallelWorkspaceSnapshotPreservesDiscoveryOrder() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let expectedPaths = (0..<128).map {
            String(format: "Source-%03d.swift", $0)
        }
        for (index, relativePath) in expectedPaths.reversed().enumerated() {
            try "struct Source\(index) {}\n".write(
                to: rootURL.appendingPathComponent(relativePath),
                atomically: true,
                encoding: .utf8
            )
        }

        let snapshot = try loadWorkspaceSourceSnapshot(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(snapshot.files.map(\.relativePath) == expectedPaths)
        #expect(snapshot.files.allSatisfy { !$0.syntax.statements.isEmpty })
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

    @Test("Workspace discovery does not prune siblings after skipped files")
    func workspaceDiscoveryDoesNotPruneSiblingsAfterSkippedFiles() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try "ignored\n".write(
            to: rootURL.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        let sourceDirectory = rootURL.appendingPathComponent(
            "Sources",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try "struct AppSource {}\n".write(
            to: sourceDirectory.appendingPathComponent("AppSource.swift"),
            atomically: true,
            encoding: .utf8
        )

        let files = try discoverWorkspaceSourceFiles(
            rootPath: rootURL.path(percentEncoded: false)
        )

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
        #expect(
            outcome.metricsArtifact.issues.first?.message
                == MacroBuildDiagnosticContract.subUnknownChildInputMessage(
                    memberName: "feature",
                    childInputName: "missing",
                    childContainerName: "FeatureContainer"
                )
        )
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
        #expect(
            outcome.metricsArtifact.issues.first?.message
                == MacroBuildDiagnosticContract.subInvalidBindingsMessage(
                    memberName: "feature"
                )
        )
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

}
