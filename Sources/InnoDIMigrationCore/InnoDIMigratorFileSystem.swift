import Foundation
import SwiftSyntax

// Filesystem discovery, encoding, atomic writes, and rollback support.
extension InnoDIMigrator {
    struct ParsedMigrationSource {
        let url: URL
        let path: String
        let source: String
        let syntax: SourceFileSyntax
        let hadUTF8ByteOrderMark: Bool
    }

    var utf8ByteOrderMark: Data { Data([0xEF, 0xBB, 0xBF]) }

    func write(
        _ source: String,
        for change: MigrationFileChange,
        to url: URL
    ) throws {
        let data = try encodedData(source, for: change)
        try data.write(to: url, options: .atomic)
    }

    func source(
        _ source: String,
        for change: MigrationFileChange,
        matchesContentsOf url: URL
    ) throws -> Bool {
        let currentData = try Data(contentsOf: url)
        let expectedData = try encodedData(source, for: change)
        return currentData == expectedData
    }

    func migrationErrorDescription(_ error: Error) -> String {
        if let migrationError = error as? MigrationError {
            return migrationError.description
        }
        return error.localizedDescription
    }

    func encodedData(
        _ source: String,
        for change: MigrationFileChange
    ) throws -> Data {
        guard var data = source.data(using: .utf8) else {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not encode migrated source as UTF-8."
            )
        }
        if change.hadUTF8ByteOrderMark {
            data.insert(contentsOf: utf8ByteOrderMark, at: data.startIndex)
        }
        return data
    }

    func swiftSourceURLs(under root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        var enumerationFailure: (path: String, reason: String)?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { url, error in
                enumerationFailure = (
                    url.path(percentEncoded: false),
                    error.localizedDescription
                )
                return false
            }
        ) else {
            throw MigrationError.cannotEnumerateRoot(
                path: root.path(percentEncoded: false),
                reason: "FileManager did not create a directory enumerator."
            )
        }

        let excludedDirectories: Set<String> = [".build", ".git", ".swiftpm"]
        var sources: [URL] = []
        var nestedRepositoryRoots: [URL] = []
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(keys))
            } catch {
                throw MigrationError.cannotEnumerateRoot(
                    path: url.path(percentEncoded: false),
                    reason: error.localizedDescription
                )
            }
            if excludedDirectories.contains(url.lastPathComponent) {
                if url.lastPathComponent == ".git" {
                    let repositoryRoot = url.deletingLastPathComponent().standardizedFileURL
                    if repositoryRoot != root {
                        nestedRepositoryRoots.append(repositoryRoot)
                    }
                }
                if values.isDirectory == true || values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
            }
            if values.isDirectory == true {
                let gitBoundary = url.appendingPathComponent(".git")
                if FileManager.default.fileExists(
                    atPath: gitBoundary.path(percentEncoded: false)
                ) {
                    nestedRepositoryRoots.append(url.standardizedFileURL)
                    enumerator.skipDescendants()
                }
                continue
            }
            if values.isSymbolicLink == true {
                var destinationIsDirectory: ObjCBool = false
                let destinationExists = FileManager.default.fileExists(
                    atPath: url.resolvingSymlinksInPath().path(percentEncoded: false),
                    isDirectory: &destinationIsDirectory
                )
                if url.pathExtension == "swift" || (destinationExists && destinationIsDirectory.boolValue) {
                    throw MigrationError.cannotEnumerateRoot(
                        path: url.path(percentEncoded: false),
                        reason: "Symbolic-link sources are not rewritten automatically. Replace the link with an in-root source or migrate its resolved target explicitly."
                    )
                }
                continue
            }
            if values.isRegularFile == true, url.pathExtension == "swift" {
                sources.append(url.standardizedFileURL)
            }
        }
        if let enumerationFailure {
            throw MigrationError.cannotEnumerateRoot(
                path: enumerationFailure.path,
                reason: enumerationFailure.reason
            )
        }
        return sources.filter { source in
            !nestedRepositoryRoots.contains { repositoryRoot in
                isDescendant(source, of: repositoryRoot)
            }
        }.sorted {
            $0.path(percentEncoded: false) < $1.path(percentEncoded: false)
        }
    }

    func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let directoryPath = directory.standardizedFileURL.path(percentEncoded: false)
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return path.hasPrefix(prefix)
    }

    func relativePath(for fileURL: URL, under root: URL) -> String {
        let rootPath = root.path(percentEncoded: false)
        let filePath = fileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return fileURL.lastPathComponent }
        return String(filePath.dropFirst(prefix.count))
    }
}
