import Foundation
import SwiftParser
import SwiftSyntax

package let workspaceSourceSkipTokens = [
    "/.build/",
    "/Derived/",
    "/Tuist/Dependencies/",
    "/.tuist/",
    "/.git/",
    "/Pods/",
    "/Carthage/",
    "/.swiftpm/",
    "/.xcodeproj/",
    "/.xcworkspace/"
]

package struct WorkspaceSourceFile {
    package let relativePath: String
    package let fileURL: URL
    package let source: String
    package let syntax: SourceFileSyntax

    package var filePath: String {
        fileURL.path(percentEncoded: false)
    }

    package init(relativePath: String, fileURL: URL, source: String, syntax: SourceFileSyntax) {
        self.relativePath = relativePath
        self.fileURL = fileURL
        self.source = source
        self.syntax = syntax
    }
}

package struct WorkspaceSourceSnapshot {
    package let rootPath: String
    package let rootURL: URL
    package let files: [WorkspaceSourceFile]

    private let filesByRelativePath: [String: WorkspaceSourceFile]

    package init(rootPath: String, rootURL: URL, files: [WorkspaceSourceFile]) {
        self.rootPath = rootPath
        self.rootURL = rootURL
        self.files = files
        self.filesByRelativePath = Dictionary(uniqueKeysWithValues: files.map { ($0.relativePath, $0) })
    }

    package func sourceFile(relativePath: String) -> WorkspaceSourceFile? {
        filesByRelativePath[relativePath]
    }
}

package func loadWorkspaceSourceSnapshot(rootPath: String) throws -> WorkspaceSourceSnapshot {
    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
    let sourceFiles = discoverWorkspaceSourceFiles(rootPath: rootPath)
    var files: [WorkspaceSourceFile] = []
    files.reserveCapacity(sourceFiles.count)

    for relativePath in sourceFiles {
        let fileURL = rootURL.appendingPathComponent(relativePath)
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let syntax = Parser.parse(source: source)
        files.append(
            WorkspaceSourceFile(
                relativePath: relativePath,
                fileURL: fileURL,
                source: source,
                syntax: syntax
            )
        )
    }

    return WorkspaceSourceSnapshot(rootPath: rootPath, rootURL: rootURL, files: files)
}

/// Discovers Swift source files that participate in workspace-wide validation.
///
/// The returned paths are relative to `rootPath` and sorted so callers can
/// build deterministic signatures or diagnostics independent of filesystem
/// enumeration order.
package func discoverWorkspaceSourceFiles(rootPath: String) -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: rootPath) else {
        return []
    }

    var sourceFiles: [String] = []

    while let item = enumerator.nextObject() as? String {
        if workspacePathShouldPruneDescendants(item) {
            enumerator.skipDescendants()
            continue
        }
        guard item.hasSuffix(".swift") else { continue }
        sourceFiles.append(item)
    }

    return sourceFiles.sorted()
}

package func workspacePathShouldPruneDescendants(_ path: String) -> Bool {
    workspacePathHasHiddenRootComponent(path) || workspacePathMatchesSkipToken(path)
}

package func workspaceRelativePath(of path: String, fromRoot rootPath: String) -> String {
    let rootURL = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().standardizedFileURL
    let pathURL = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL

    let root = rootURL.path(percentEncoded: false)
    let fullPath = pathURL.path(percentEncoded: false)

    if fullPath == root {
        return (fullPath as NSString).lastPathComponent
    }

    let rootPrefix = root.hasSuffix("/") ? root : root + "/"
    if fullPath.hasPrefix(rootPrefix) {
        return String(fullPath.dropFirst(rootPrefix.count))
    }

    let parentName = pathURL.deletingLastPathComponent().lastPathComponent
    let fileName = pathURL.lastPathComponent
    if parentName.isEmpty {
        return "__external__/\(fileName)"
    }
    return "__external__/\(parentName)/\(fileName)"
}

package func parseWorkspaceSourceFile(at path: String) throws -> SourceFileSyntax {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    return Parser.parse(source: source)
}

private func workspacePathHasHiddenRootComponent(_ path: String) -> Bool {
    guard let firstComponent = path.split(separator: "/").first else {
        return false
    }
    return firstComponent.hasPrefix(".")
}

private func workspacePathMatchesSkipToken(_ path: String) -> Bool {
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let normalizedPath = "/\(trimmedPath)/"
    for token in workspaceSourceSkipTokens where normalizedPath.contains(token) {
        return true
    }
    return false
}
