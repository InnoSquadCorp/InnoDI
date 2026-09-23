import Foundation
import Darwin
import SwiftSyntax

// Filesystem discovery, encoding, atomic writes, and rollback support.
extension InnoDIMigrator {
    struct AnchoredMigrationRoot {
        let descriptor: Int32

        init(url: URL) throws {
            descriptor = Darwin.open(
                url.path(percentEncoded: false),
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                throw MigrationError.cannotWrite(
                    path: url.path(percentEncoded: false),
                    reason: "Could not anchor the migration root: \(String(cString: strerror(errno)))."
                )
            }
        }

        func close() {
            Darwin.close(descriptor)
        }
    }

    struct AnchoredMigrationFile {
        let directoryDescriptor: Int32
        let name: String

        func close() {
            Darwin.close(directoryDescriptor)
        }
    }

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
        replacing expectedSource: String,
        for change: MigrationFileChange,
        to file: AnchoredMigrationFile,
        beforePublish: (() throws -> Void)? = nil
    ) throws -> String {
        let data = try encodedData(source, for: change)
        let originalDescriptor = Darwin.openat(
            file.directoryDescriptor,
            file.name,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard originalDescriptor >= 0 else {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not open the verified source before replacement: \(String(cString: strerror(errno)))."
            )
        }
        defer { Darwin.close(originalDescriptor) }
        var originalStatus = stat()
        guard Darwin.fstat(originalDescriptor, &originalStatus) == 0,
              originalStatus.st_mode & S_IFMT == S_IFREG else {
            let reason = String(cString: strerror(errno))
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not inspect the verified source before replacement: \(reason)."
            )
        }
        // After the exchange this name owns the displaced directory entry.
        // Keep it even on success: a non-cooperating editor may still write
        // through an already-open descriptor after our last content check.
        let temporaryName = ".innodi-migrate-recovery-\(file.name)-\(UUID().uuidString)"
        let recoveryPath = (change.path as NSString).deletingLastPathComponent
        let relativeRecoveryPath = recoveryPath.isEmpty
            ? temporaryName : "\(recoveryPath)/\(temporaryName)"
        let temporaryDescriptor = Darwin.openat(
            file.directoryDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard temporaryDescriptor >= 0 else {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not create an anchored temporary file: \(String(cString: strerror(errno)))."
            )
        }
        var shouldRemoveTemporary = true
        defer {
            Darwin.close(temporaryDescriptor)
            if shouldRemoveTemporary {
                _ = temporaryName.withCString {
                    Darwin.unlinkat(file.directoryDescriptor, $0, 0)
                }
            }
        }

        try data.withUnsafeBytes { bytes in
            var remaining = bytes.count
            var base = bytes.baseAddress
            while remaining > 0 {
                let written = Darwin.write(temporaryDescriptor, base, remaining)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else {
                    throw MigrationError.cannotWrite(
                        path: change.path,
                        reason: "Could not write the anchored temporary file: \(String(cString: strerror(errno)))."
                    )
                }
                remaining -= written
                base = base?.advanced(by: written)
            }
        }
        // open(O_CREAT, mode) is filtered by umask; restore the source mode
        // explicitly after writing (which may itself clear special bits).
        guard Darwin.fchmod(temporaryDescriptor, originalStatus.st_mode & 0o7777) == 0 else {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not preserve the source permissions: \(String(cString: strerror(errno)))."
            )
        }
        guard Darwin.fsync(temporaryDescriptor) == 0 else {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not synchronize the anchored temporary file: \(String(cString: strerror(errno)))."
            )
        }
        try beforePublish?()
        let renameResult = temporaryName.withCString { temporaryPointer in
            file.name.withCString { destinationPointer in
                Darwin.renameatx_np(
                    file.directoryDescriptor,
                    temporaryPointer,
                    file.directoryDescriptor,
                    destinationPointer,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        guard renameResult == 0 else {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not atomically exchange the source in its anchored directory: \(String(cString: strerror(errno))). No overwrite fallback was attempted."
            )
        }
        shouldRemoveTemporary = false
        do {
            let displaced = AnchoredMigrationFile(
                directoryDescriptor: file.directoryDescriptor,
                name: temporaryName
            )
            var displacedStatus = stat()
            guard Darwin.fstatat(file.directoryDescriptor, temporaryName, &displacedStatus, AT_SYMLINK_NOFOLLOW) == 0,
                  displacedStatus.st_dev == originalStatus.st_dev,
                  displacedStatus.st_ino == originalStatus.st_ino,
                  try self.source(expectedSource, for: change, matchesContentsOf: displaced) else {
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "Concurrent source replacement or edit detected during publication."
                )
            }
            guard Darwin.fsync(file.directoryDescriptor) == 0 else {
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "Could not synchronize the source directory: \(String(cString: strerror(errno)))."
                )
            }
        } catch {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "\(migrationErrorDescription(error)) The displaced entry is preserved at \(relativeRecoveryPath). The source may contain migration output; review both paths. No automatic conflict overwrite was attempted."
            )
        }
        return relativeRecoveryPath
    }

    func source(
        _ source: String,
        for change: MigrationFileChange,
        matchesContentsOf file: AnchoredMigrationFile
    ) throws -> Bool {
        let descriptor = Darwin.openat(
            file.directoryDescriptor,
            file.name,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw MigrationError.cannotWrite(
                path: change.path,
                reason: "Could not open the source through the anchored root: \(String(cString: strerror(errno)))."
            )
        }
        let currentData = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            .readDataToEndOfFile()
        let expectedData = try encodedData(source, for: change)
        return currentData == expectedData
    }

    func anchoredFile(
        for relativePath: String,
        under root: AnchoredMigrationRoot
    ) throws -> AnchoredMigrationFile {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MigrationError.cannotWrite(
                path: relativePath,
                reason: "The planned source path is not a safe relative path."
            )
        }

        var directoryDescriptor = Darwin.dup(root.descriptor)
        guard directoryDescriptor >= 0 else {
            throw MigrationError.cannotWrite(
                path: relativePath,
                reason: "Could not duplicate the anchored migration root: \(String(cString: strerror(errno)))."
            )
        }
        do {
            for component in components.dropLast() {
                let nextDescriptor = Darwin.openat(
                    directoryDescriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
                guard nextDescriptor >= 0 else {
                    throw MigrationError.cannotWrite(
                        path: relativePath,
                        reason: "A source directory changed or became a symbolic link after planning: \(String(cString: strerror(errno)))."
                    )
                }
                Darwin.close(directoryDescriptor)
                directoryDescriptor = nextDescriptor
            }
            return AnchoredMigrationFile(
                directoryDescriptor: directoryDescriptor,
                name: components.last.unsafelyUnwrapped
            )
        } catch {
            Darwin.close(directoryDescriptor)
            throw error
        }
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
