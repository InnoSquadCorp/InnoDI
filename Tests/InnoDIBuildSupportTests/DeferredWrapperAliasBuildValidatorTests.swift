import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIBuildSupport
@testable import InnoDIWorkspaceAnalysis

@Suite("DeferredWrapperAliasBuildValidator")
struct DeferredWrapperAliasBuildValidatorTests {

    private func makeSnapshot(
        _ files: [(path: String, source: String)],
        rootPath: String = "/workspace"
    ) -> WorkspaceSourceSnapshot {
        let rootURL = URL(fileURLWithPath: rootPath)
        let workspaceFiles = files.map { entry -> WorkspaceSourceFile in
            let syntax = Parser.parse(source: entry.source)
            let url = rootURL.appendingPathComponent(entry.path)
            return WorkspaceSourceFile(
                relativePath: entry.path,
                fileURL: url,
                syntax: syntax
            )
        }
        return WorkspaceSourceSnapshot(
            rootPath: rootPath,
            rootURL: rootURL,
            files: workspaceFiles
        )
    }

    @Test("snapshot without aliases produces no issues")
    func emptySnapshotProducesNoIssues() {
        let snapshot = makeSnapshot([
            ("Sources/Module/A.swift", "struct Foo {}\n")
        ])

        let report = DeferredWrapperAliasBuildValidator.validate(snapshot: snapshot)

        #expect(report.issues.isEmpty)
        #expect(report.hasFailures == false)
    }

    @Test("Lazy alias is reported as a warning with file location")
    func lazyAliasReportedAsWarning() throws {
        let snapshot = makeSnapshot([
            ("Sources/Feature/Aliases.swift", "typealias DeferredFoo = Lazy<Foo>\n")
        ])

        let report = DeferredWrapperAliasBuildValidator.validate(snapshot: snapshot)

        #expect(report.issues.count == 1)
        let issue = try #require(report.issues.first, "expected a single report issue")
        #expect(issue.code == "deferred-alias.workspace-finding")
        #expect(issue.severity == .warning)
        #expect(issue.location.filePath == "Sources/Feature/Aliases.swift")
        #expect(issue.location.line == 1)
        #expect(issue.metadata["aliasKind"] == "lazy")
        #expect(issue.metadata["aliasName"] == "DeferredFoo")
        #expect(issue.message.contains("Lazy<...>"))
    }

    @Test("Provider alias renames are reported with provider metadata")
    func providerAliasReportedWithMetadata() throws {
        let snapshot = makeSnapshot([
            ("Sources/Feature/Aliases.swift", "typealias FreshBar = InnoDI.Provider<Bar>\n")
        ])

        let report = DeferredWrapperAliasBuildValidator.validate(snapshot: snapshot)

        #expect(report.issues.count == 1)
        let issue = try #require(report.issues.first, "expected a single report issue")
        #expect(issue.metadata["aliasKind"] == "provider")
        #expect(issue.message.contains("Provider<...>"))
    }

    @Test("warning-only report does not promote to a failure command result")
    func warningsDoNotFailBuild() {
        let snapshot = makeSnapshot([
            ("Sources/Module/A.swift", "typealias DeferredFoo = Lazy<Foo>\n")
        ])

        let report = DeferredWrapperAliasBuildValidator.validate(snapshot: snapshot)

        #expect(!report.issues.isEmpty)
        #expect(report.hasFailures == false)
        #expect(report.asCommandResult() == nil)
    }

    @Test("findings across multiple files are sorted deterministically")
    func multipleFilesSortedDeterministically() {
        let snapshot = makeSnapshot([
            ("Sources/Z/Late.swift", "typealias LazyZ = Lazy<Z>\n"),
            ("Sources/A/Early.swift", "typealias LazyA = Lazy<A>\n")
        ])

        let report = DeferredWrapperAliasBuildValidator.validate(snapshot: snapshot)

        #expect(report.issues.count == 2)
        #expect(report.issues.first?.location.filePath == "Sources/A/Early.swift")
        #expect(report.issues.last?.location.filePath == "Sources/Z/Late.swift")
    }
}
