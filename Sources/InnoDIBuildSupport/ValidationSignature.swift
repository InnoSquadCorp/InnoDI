import Foundation
import InnoDIWorkspaceAnalysis
import SwiftParser
import SwiftSyntax

/// Minimal parsing abstraction so signature tests can inject deterministic
/// syntax parsers without touching the filesystem cache behavior.
protocol ValidationSyntaxParsing: Sendable {
    func parse(source: String) -> SourceFileSyntax
}

/// Live parser used by build-support signature collection.
struct LiveValidationSyntaxParser: ValidationSyntaxParsing {
    func parse(source: String) -> SourceFileSyntax {
        Parser.parse(source: source)
    }
}

/// Cheap file metadata used for the first-stage cache hit check before any
/// source bytes are loaded.
struct ValidationFileFingerprint: Codable, Equatable, Sendable {
    let fileSize: Int
    let modifiedAt: TimeInterval
}

/// Cached digest entry for one Swift source file.
///
/// The collector first compares `fingerprint`, then falls back to
/// `contentHash`, and only reparses the AST when both differ.
struct ValidationFileDigestRecord: Codable, Equatable, Sendable {
    let fingerprint: ValidationFileFingerprint
    let contentHash: String
    let digest: String
}

/// Manifest persisted under `.build/innodi-ast-digest-cache`.
///
/// This is the durable source of truth for the three-stage cache flow:
/// metadata fingerprint -> raw content hash -> normalized AST digest.
struct ValidationDigestManifest: Codable, Equatable, Sendable {
    static let currentVersion = 3

    let version: Int
    let files: [String: ValidationFileDigestRecord]

    init(version: Int = currentVersion, files: [String: ValidationFileDigestRecord]) {
        self.version = version
        self.files = files
    }
}

package struct LoadedValidationDigestManifest {
    let manifest: ValidationDigestManifest
    let invalidatedByCorruption: Bool
    let invalidatedByVersion: Bool
}

/// Collects the normalized package signature that keys shared validation runs.
///
/// The collector intentionally ignores whitespace/comments through the
/// normalized AST digest, skips dependency/build directories listed in
/// `validationSkipTokens`, and uses a stable hasher so equivalent source trees
/// produce the same signature regardless of file creation order.
struct ValidationSignatureCollector<Parser: ValidationSyntaxParsing> {
    let stateDirectoryPath: String
    let parser: Parser

    /// Returns only the final signature string while still updating the
    /// manifest cache on disk.
    func collect(rootPath: String) throws -> String {
        try collectWithMetrics(rootPath: rootPath).signature
    }

    /// Returns the signature plus cache-hit diagnostics used by coordinator
    /// metrics artifacts and release tooling.
    func collectWithMetrics(
        rootPath: String,
        persistManifestUpdates: Bool = true,
        useManifestCache: Bool = true
    ) throws -> ValidationSignatureCollectionResult {
        let fileManager = FileManager.default
        let stateDirectoryURL = URL(fileURLWithPath: stateDirectoryPath, isDirectory: true)
        if persistManifestUpdates {
            try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        }

        let manifestURL = stateDirectoryURL.appendingPathComponent("ast-digest-cache.json")
        let loadedManifest: LoadedValidationDigestManifest
        if useManifestCache {
            loadedManifest = try loadManifest(at: manifestURL)
        } else {
            loadedManifest = LoadedValidationDigestManifest(
                manifest: ValidationDigestManifest(files: [:]),
                invalidatedByCorruption: false,
                invalidatedByVersion: false
            )
        }
        let existingManifest = loadedManifest.manifest
        let sourceFiles = try discoverValidationSourceFiles(rootPath: rootPath)
        var updatedRecords: [String: ValidationFileDigestRecord] = [:]
        var metadataCacheHitCount = 0
        var contentHashReuseCount = 0
        var astReparseCount = 0
        var reasonCodes: Set<ValidationReasonCode> = []
        var newFiles: [String] = []
        var deletedFiles: [String] = []
        var reparsedFiles: [String] = []
        var contentHashReusedFiles: [String] = []

        if loadedManifest.invalidatedByVersion {
            reasonCodes.insert(.cacheMissManifestVersion)
        }
        if loadedManifest.invalidatedByCorruption {
            reasonCodes.insert(.cacheMissManifestCorrupted)
        }

        let deletedFileSet = Set(existingManifest.files.keys).subtracting(sourceFiles)
        if !deletedFileSet.isEmpty {
            reasonCodes.insert(.cacheMissDeletedFile)
        }
        deletedFiles = deletedFileSet.sorted()

        for relativePath in sourceFiles {
            let fileURL = URL(fileURLWithPath: rootPath).appendingPathComponent(relativePath)
            let fingerprint = try makeFingerprint(for: fileURL)
            let wasCached = existingManifest.files[relativePath] != nil

            if !wasCached {
                reasonCodes.insert(.cacheMissNewFile)
                newFiles.append(relativePath)
            }

            if let cached = existingManifest.files[relativePath], cached.fingerprint == fingerprint {
                updatedRecords[relativePath] = cached
                metadataCacheHitCount += 1
                reasonCodes.insert(.cacheHitMetadata)
                continue
            }

            let data = try Data(contentsOf: fileURL)
            let contentHash = rawContentHash(for: data)

            if let cached = existingManifest.files[relativePath], cached.contentHash == contentHash {
                updatedRecords[relativePath] = ValidationFileDigestRecord(
                    fingerprint: fingerprint,
                    contentHash: contentHash,
                    digest: cached.digest
                )
                contentHashReuseCount += 1
                contentHashReusedFiles.append(relativePath)
                reasonCodes.insert(.cacheHitContentHash)
                continue
            }

            let source = String(decoding: data, as: UTF8.self)
            let syntax = parser.parse(source: source)
            let digest = normalizedDigest(for: syntax)
            astReparseCount += 1
            reparsedFiles.append(relativePath)
            reasonCodes.insert(.cacheMissContentChanged)
            updatedRecords[relativePath] = ValidationFileDigestRecord(
                fingerprint: fingerprint,
                contentHash: contentHash,
                digest: digest
            )
        }

        if persistManifestUpdates {
            let manifest = ValidationDigestManifest(files: updatedRecords)
            try persistManifest(manifest, to: manifestURL)
        }

        var hasher = StableHasher()
        hasher.combine("count:\(sourceFiles.count)")

        for relativePath in sourceFiles {
            hasher.combine("file:\(relativePath)")
            hasher.combine("digest:\(updatedRecords[relativePath]?.digest ?? "missing")")
        }

        return ValidationSignatureCollectionResult(
            signature: hasher.finalize(),
            metrics: ValidationSignatureMetrics(
                scannedFileCount: sourceFiles.count,
                metadataCacheHitCount: metadataCacheHitCount,
                contentHashReuseCount: contentHashReuseCount,
                astReparseCount: astReparseCount
            ),
            reasonCodes: reasonCodes.sorted { $0.rawValue < $1.rawValue },
            fileChanges: ValidationFileChangeDetails(
                newFiles: newFiles.sorted(),
                deletedFiles: deletedFiles,
                reparsedFiles: reparsedFiles.sorted(),
                contentHashReusedFiles: contentHashReusedFiles.sorted()
            )
        )
    }
}

/// Convenience entry point used by callers that only need the final signature.
func collectValidationSignature(
    rootPath: String,
    stateDirectoryPath: String? = nil
) throws -> String {
    try collectValidationSignatureWithMetrics(
        rootPath: rootPath,
        stateDirectoryPath: stateDirectoryPath
    ).signature
}

/// Computes the current package signature and the cache metrics that explain
/// why it was reused or rebuilt.
func collectValidationSignatureWithMetrics(
    rootPath: String,
    stateDirectoryPath: String? = nil,
    persistManifestUpdates: Bool = true,
    useManifestCache: Bool = true
) throws -> ValidationSignatureCollectionResult {
    let resolvedStateDirectoryPath: String
    if let stateDirectoryPath {
        resolvedStateDirectoryPath = stateDirectoryPath
    } else {
        resolvedStateDirectoryPath = URL(fileURLWithPath: rootPath)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("innodi-ast-digest-cache", isDirectory: true)
            .path(percentEncoded: false)
    }

    return try ValidationSignatureCollector(
        stateDirectoryPath: resolvedStateDirectoryPath,
        parser: LiveValidationSyntaxParser()
    )
    .collectWithMetrics(
        rootPath: rootPath,
        persistManifestUpdates: persistManifestUpdates,
        useManifestCache: useManifestCache
    )
}

/// Discovers Swift source files that participate in build validation.
///
/// The returned paths are relative to `rootPath` and sorted so the final
/// stable hash does not depend on directory enumeration order.
func discoverValidationSourceFiles(rootPath: String) throws -> [String] {
    try discoverWorkspaceSourceFiles(rootPath: rootPath)
}

func validationPathShouldPruneDescendants(_ path: String) -> Bool {
    workspacePathShouldPruneDescendants(path)
}

private func makeFingerprint(for fileURL: URL) throws -> ValidationFileFingerprint {
    let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    return ValidationFileFingerprint(
        fileSize: resourceValues.fileSize ?? 0,
        modifiedAt: resourceValues.contentModificationDate?.timeIntervalSince1970 ?? 0
    )
}

private func normalizedDigest(for syntax: SourceFileSyntax) -> String {
    var hasher = StableHasher()
    appendNormalizedSyntax(Syntax(syntax), to: &hasher)
    return hasher.finalize()
}

private func rawContentHash(for data: Data) -> String {
    var hasher = StableHasher()
    hasher.combine(data)
    return hasher.finalize()
}

private func appendNormalizedSyntax(_ node: Syntax, to hasher: inout StableHasher) {
    hasher.combine("(\(String(describing: node.kind))")

    if let token = node.as(TokenSyntax.self) {
        hasher.combine("|\(String(describing: token.tokenKind))")
        hasher.combine("|\(token.text)")
    }

    for child in node.children(viewMode: .all) {
        appendNormalizedSyntax(child, to: &hasher)
    }

    hasher.combine(")")
}

package func loadManifest(at url: URL) throws -> LoadedValidationDigestManifest {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return LoadedValidationDigestManifest(
            manifest: ValidationDigestManifest(files: [:]),
            invalidatedByCorruption: false,
            invalidatedByVersion: false
        )
    }

    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        return LoadedValidationDigestManifest(
            manifest: ValidationDigestManifest(files: [:]),
            invalidatedByCorruption: false,
            invalidatedByVersion: false
        )
    }

    do {
        let manifest = try JSONDecoder().decode(ValidationDigestManifest.self, from: data)
        if manifest.version == ValidationDigestManifest.currentVersion {
            return LoadedValidationDigestManifest(
                manifest: manifest,
                invalidatedByCorruption: false,
                invalidatedByVersion: false
            )
        }
        return LoadedValidationDigestManifest(
            manifest: ValidationDigestManifest(files: [:]),
            invalidatedByCorruption: false,
            invalidatedByVersion: true
        )
    } catch {
        return LoadedValidationDigestManifest(
            manifest: ValidationDigestManifest(files: [:]),
            invalidatedByCorruption: true,
            invalidatedByVersion: false
        )
    }
}

private func persistManifest(_ manifest: ValidationDigestManifest, to url: URL) throws {
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: url, options: .atomic)
}

struct StableHasher {
    private var highState: UInt64 = 14_695_981_039_346_656_037
    private var lowState: UInt64 = 1_099_511_628_211

    mutating func combine(_ value: String) {
        for byte in value.utf8 {
            combine(byte)
        }
    }

    mutating func combine(_ data: Data) {
        for byte in data {
            combine(byte)
        }
    }

    func finalize() -> String {
        paddedHex(highState) + paddedHex(lowState)
    }

    private mutating func combine(_ byte: UInt8) {
        highState ^= UInt64(byte)
        highState &*= 1_099_511_628_211

        lowState &+= UInt64(byte) &* 0x9e37_79b9_7f4a_7c15
        lowState ^= lowState >> 33
        lowState &*= 0xff51_afd7_ed55_8ccd
        lowState ^= lowState >> 33
    }

    private func paddedHex(_ value: UInt64) -> String {
        let raw = String(value, radix: 16)
        guard raw.count < 16 else {
            return raw
        }
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
