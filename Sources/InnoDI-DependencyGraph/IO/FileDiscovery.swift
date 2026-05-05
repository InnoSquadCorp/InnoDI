import Foundation
import InnoDIWorkspaceAnalysis
import SwiftSyntax

func loadSwiftFiles(rootPath: String) throws -> [String] {
    try discoverWorkspaceSourceFiles(rootPath: rootPath)
        .map { (rootPath as NSString).appendingPathComponent($0) }
}

func shouldSkip(path: String) -> Bool {
    workspacePathShouldPruneDescendants(path)
}

func parseSourceFile(at path: String) throws -> SourceFileSyntax {
    try parseWorkspaceSourceFile(at: path)
}

func relativePath(of path: String, fromRoot rootPath: String) -> String {
    workspaceRelativePath(of: path, fromRoot: rootPath)
}
