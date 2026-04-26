import Foundation
import SwiftParser
import SwiftSyntax

func loadSwiftFiles(rootPath: String) -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: rootPath) else { return [] }

    var results: [String] = []
    while let item = enumerator.nextObject() as? String {
        let fullPath = (rootPath as NSString).appendingPathComponent(item)
        if item.hasPrefix(".") || shouldSkip(path: item) {
            if isDirectory(at: fullPath, fileManager: fileManager) {
                enumerator.skipDescendants()
            }
            continue
        }
        if item.hasSuffix(".swift") {
            results.append(fullPath)
        }
    }

    return results.sorted()
}

func shouldSkip(path: String) -> Bool {
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !trimmedPath.isEmpty else {
        return false
    }
    let normalizedPath = "/\(trimmedPath)/"
    let skipTokens = [
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

    for token in skipTokens where normalizedPath.contains(token) {
        return true
    }
    return false
}

private func isDirectory(at path: String, fileManager: FileManager) -> Bool {
    var isDirectory: ObjCBool = false
    return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
}

func parseSourceFile(at path: String) throws -> SourceFileSyntax {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    return Parser.parse(source: source)
}

func relativePath(of path: String, fromRoot rootPath: String) -> String {
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
