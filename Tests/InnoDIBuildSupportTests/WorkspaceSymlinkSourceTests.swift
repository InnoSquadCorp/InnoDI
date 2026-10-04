import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@Suite("Workspace declared symlink sources")
struct WorkspaceSymlinkSourceTests {
    @Test("An in-package directory symlink retains the plugin's logical path")
    func inPackageSourceDirectorySymlinkLoadsItsDeclaredSpelling() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let link = fixture.rootURL.appendingPathComponent("Sources/LinkedApp")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: fixture.appSourceURL.deletingLastPathComponent()
        )
        let source = WorkspaceAnalysisSource(
            filePath: link.appendingPathComponent("App.swift").path,
            logicalPath: "Sources/LinkedApp/App.swift",
            origin: .declared
        )
        let manifest = try replacingAppSources([source], in: fixture)

        let validated = try ValidatedWorkspaceAnalysisManifest(validating: manifest)
        let snapshot = try loadWorkspaceSourceSnapshot(validated: validated)
        let loaded = try #require(snapshot.sourceFile(sourceIdentity: source.identity(in: fixture.appID)))
        #expect(loaded.relativePath == "Sources/LinkedApp/App.swift")
        #expect(loaded.filePath == source.filePath)
        #expect(loaded.syntax.description == "struct App {}\n")
    }

    @Test("Symlink aliases still cannot claim the same physical file twice")
    func canonicalDuplicateOwnershipRemainsEnforced() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let link = fixture.rootURL.appendingPathComponent("Sources/LinkedApp")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: fixture.appSourceURL.deletingLastPathComponent()
        )
        let original = WorkspaceAnalysisSource(
            filePath: fixture.appSourceURL.path,
            logicalPath: "Sources/App/App.swift",
            origin: .declared
        )
        let alias = WorkspaceAnalysisSource(
            filePath: link.appendingPathComponent("App.swift").path,
            logicalPath: "Sources/LinkedApp/App.swift",
            origin: .declared
        )
        let manifest = try replacingAppSources([original, alias], in: fixture)
        #expect(throws: WorkspaceAnalysisManifestError.duplicateSourcePath(fixture.appID, alias.filePath)) {
            try ValidatedWorkspaceAnalysisManifest(validating: manifest)
        }
    }

    @Test("A lexical in-package link cannot admit an external source")
    func externalSourceDirectorySymlinkRemainsRejected() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let external = try ManifestFixture()
        defer { external.remove() }
        let link = fixture.rootURL.appendingPathComponent("Sources/ExternalApp")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: external.appSourceURL.deletingLastPathComponent()
        )
        let source = WorkspaceAnalysisSource(
            filePath: link.appendingPathComponent("App.swift").path,
            logicalPath: "Sources/ExternalApp/App.swift",
            origin: .declared
        )
        let manifest = try replacingAppSources([source], in: fixture)
        #expect(throws: WorkspaceAnalysisManifestError.declaredSourceOutsidePackage(
            target: fixture.appID,
            filePath: source.filePath,
            packageDirectory: fixture.rootPath
        )) {
            try ValidatedWorkspaceAnalysisManifest(validating: manifest)
        }
    }

    @Test("A symlink alias cannot transfer physical ownership to another target")
    func canonicalCrossTargetOwnershipRemainsEnforced() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let link = fixture.rootURL.appendingPathComponent("Sources/LinkedApp")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: fixture.appSourceURL.deletingLastPathComponent()
        )
        let alias = WorkspaceAnalysisSource(
            filePath: link.appendingPathComponent("App.swift").path,
            logicalPath: "Sources/LinkedApp/App.swift",
            origin: .declared
        )
        let manifest = makeValidManifest(fixture: fixture)
        let invalid = replacingManifest(
            manifest,
            targets: manifest.targets.map {
                $0.id == fixture.supportID ? replacingTarget($0, sources: [alias]) : $0
            }
        )
        #expect(throws: WorkspaceAnalysisManifestError.duplicateSourceOwnership(
            filePath: alias.filePath,
            firstTarget: fixture.appID,
            secondTarget: fixture.supportID
        )) {
            try ValidatedWorkspaceAnalysisManifest(validating: invalid)
        }
    }

    @Test("A symlink's declared logical path must match its lexical source path")
    func mismatchedSymlinkLogicalPathRemainsRejected() throws {
        let fixture = try ManifestFixture()
        defer { fixture.remove() }
        let link = fixture.rootURL.appendingPathComponent("Sources/LinkedApp")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: fixture.appSourceURL.deletingLastPathComponent()
        )
        let source = WorkspaceAnalysisSource(
            filePath: link.appendingPathComponent("App.swift").path,
            logicalPath: "Sources/App/App.swift",
            origin: .declared
        )
        let manifest = try replacingAppSources([source], in: fixture)
        #expect(throws: WorkspaceAnalysisManifestError.declaredSourceLogicalPathMismatch(
            target: fixture.appID,
            expected: "Sources/LinkedApp/App.swift",
            actual: source.logicalPath
        )) {
            try ValidatedWorkspaceAnalysisManifest(validating: manifest)
        }
    }

    private func replacingAppSources(
        _ sources: [WorkspaceAnalysisSource],
        in fixture: ManifestFixture
    ) throws -> WorkspaceAnalysisManifest {
        let manifest = makeValidManifest(fixture: fixture)
        let app = try #require(target(in: manifest, id: fixture.appID))
        return replacingManifest(
            manifest,
            targets: manifest.targets.map {
                $0.id == fixture.appID ? replacingTarget(app, sources: sources) : $0
            }
        )
    }
}
