import Foundation
import SwiftParser
import SwiftSyntax

let validationSkipTokens = [
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

protocol ValidationSyntaxParsing: Sendable {
    func parse(source: String) -> SourceFileSyntax
}

struct LiveValidationSyntaxParser: ValidationSyntaxParsing {
    func parse(source: String) -> SourceFileSyntax {
        Parser.parse(source: source)
    }
}

struct ValidationFileFingerprint: Codable, Equatable, Sendable {
    let fileSize: Int
    let modifiedAt: TimeInterval
}

struct ValidationFileDigestRecord: Codable, Equatable, Sendable {
    let fingerprint: ValidationFileFingerprint
    let contentHash: String
    let digest: String
}

struct ValidationDigestManifest: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let files: [String: ValidationFileDigestRecord]

    init(version: Int = currentVersion, files: [String: ValidationFileDigestRecord]) {
        self.version = version
        self.files = files
    }
}

private struct LoadedValidationDigestManifest {
    let manifest: ValidationDigestManifest
    let invalidatedByVersion: Bool
}

struct ValidationSignatureCollector<Parser: ValidationSyntaxParsing> {
    let stateDirectoryPath: String
    let parser: Parser

    func collect(rootPath: String) throws -> String {
        try collectWithMetrics(rootPath: rootPath).signature
    }

    func collectWithMetrics(rootPath: String) throws -> ValidationSignatureCollectionResult {
        let fileManager = FileManager.default
        let stateDirectoryURL = URL(fileURLWithPath: stateDirectoryPath, isDirectory: true)
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)

        let manifestURL = stateDirectoryURL.appendingPathComponent("ast-digest-cache.json")
        let loadedManifest = try loadManifest(at: manifestURL)
        let existingManifest = loadedManifest.manifest
        let sourceFiles = discoverValidationSourceFiles(rootPath: rootPath)
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

        let manifest = ValidationDigestManifest(files: updatedRecords)
        try persistManifest(manifest, to: manifestURL)

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

func collectValidationSignature(
    rootPath: String,
    stateDirectoryPath: String? = nil
) throws -> String {
    try collectValidationSignatureWithMetrics(
        rootPath: rootPath,
        stateDirectoryPath: stateDirectoryPath
    ).signature
}

func collectValidationSignatureWithMetrics(
    rootPath: String,
    stateDirectoryPath: String? = nil
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
    .collectWithMetrics(rootPath: rootPath)
}

func discoverValidationSourceFiles(rootPath: String) -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: rootPath) else {
        return []
    }

    var sourceFiles: [String] = []

    while let item = enumerator.nextObject() as? String {
        if item.hasPrefix(".") { continue }
        if shouldSkipValidationPath(item) { continue }
        guard item.hasSuffix(".swift") else { continue }
        sourceFiles.append(item)
    }

    return sourceFiles.sorted()
}

private func shouldSkipValidationPath(_ path: String) -> Bool {
    for token in validationSkipTokens where path.contains(token) {
        return true
    }
    return false
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

private func loadManifest(at url: URL) throws -> LoadedValidationDigestManifest {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return LoadedValidationDigestManifest(
            manifest: ValidationDigestManifest(files: [:]),
            invalidatedByVersion: false
        )
    }

    let data = try Data(contentsOf: url)
    let manifest = try JSONDecoder().decode(ValidationDigestManifest.self, from: data)
    if manifest.version == ValidationDigestManifest.currentVersion {
        return LoadedValidationDigestManifest(manifest: manifest, invalidatedByVersion: false)
    }
    return LoadedValidationDigestManifest(
        manifest: ValidationDigestManifest(files: [:]),
        invalidatedByVersion: true
    )
}

private func persistManifest(_ manifest: ValidationDigestManifest, to url: URL) throws {
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: url, options: .atomic)
}

struct StableHasher {
    private var state: UInt64 = 14_695_981_039_346_656_037

    mutating func combine(_ value: String) {
        for byte in value.utf8 {
            state ^= UInt64(byte)
            state &*= 1_099_511_628_211
        }
    }

    mutating func combine(_ data: Data) {
        for byte in data {
            state ^= UInt64(byte)
            state &*= 1_099_511_628_211
        }
    }

    func finalize() -> String {
        String(state, radix: 16)
    }
}
