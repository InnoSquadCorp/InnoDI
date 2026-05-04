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
    "/.swiftpm/"
]

// Xcode bundle names include project-specific prefixes, such as Sample.xcodeproj.
private let workspaceSourceSkippedPathComponentSuffixes = [
    ".xcodeproj",
    ".xcworkspace"
]

package struct WorkspaceSourceFile {
    package let relativePath: String
    package let fileURL: URL
    package let syntax: SourceFileSyntax

    package var filePath: String {
        fileURL.path(percentEncoded: false)
    }

    package init(relativePath: String, fileURL: URL, syntax: SourceFileSyntax) {
        self.relativePath = relativePath
        self.fileURL = fileURL
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

package func loadWorkspaceSourceSnapshot(
    rootPath: String,
    onFileReadError: ((String, URL, Error) -> Void)? = nil
) throws -> WorkspaceSourceSnapshot {
    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
    let sourceFiles = discoverWorkspaceSourceFiles(rootPath: rootPath)
    var files: [WorkspaceSourceFile] = []
    files.reserveCapacity(sourceFiles.count)

    for relativePath in sourceFiles {
        let fileURL = rootURL.appendingPathComponent(relativePath)
        let source: String
        do {
            source = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            if let onFileReadError {
                onFileReadError(relativePath, fileURL, error)
                continue
            }
            throw error
        }
        let syntax = Parser.parse(source: source)
        files.append(
            WorkspaceSourceFile(
                relativePath: relativePath,
                fileURL: fileURL,
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

    let hash = stableWorkspacePathHash(fullPath)
    let parentName = pathURL.deletingLastPathComponent().lastPathComponent
    let fileName = pathURL.lastPathComponent
    if parentName.isEmpty {
        return "__external__/\(hash)/\(fileName)"
    }
    return "__external__/\(hash)/\(parentName)/\(fileName)"
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
    let pathComponents = trimmedPath.split(separator: "/")
    for component in pathComponents {
        if workspaceSourceSkippedPathComponentSuffixes.contains(where: { component.hasSuffix($0) }) {
            return true
        }
    }
    return false
}

private func stableWorkspacePathHash(_ path: String) -> String {
    var highState: UInt64 = 14_695_981_039_346_656_037
    var lowState: UInt64 = 1_099_511_628_211

    for byte in path.utf8 {
        highState ^= UInt64(byte)
        highState = highState &* 1_099_511_628_211

        lowState ^= UInt64(byte) &+ 0x9e37_79b9_7f4a_7c15
        lowState = lowState &* 1_099_511_628_211
    }

    return paddedHex(highState) + paddedHex(lowState)
}

private func paddedHex(_ value: UInt64) -> String {
    let hex = String(value, radix: 16)
    return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
}
