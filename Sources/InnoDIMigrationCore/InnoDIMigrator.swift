import Foundation
import InnoDICore
import SwiftParser
import SwiftSyntax

public struct InnoDIMigrator {
    public init() {}

    public func plan(root: URL) throws -> MigrationPlan {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: root.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw MigrationError.invalidRoot(root.path(percentEncoded: false))
        }

        let sourceURLs = try swiftSourceURLs(under: root)
        var parsedSources: [ParsedMigrationSource] = []
        var diagnostics: [MigrationDiagnostic] = []

        for url in sourceURLs {
            let relativePath = relativePath(for: url, under: root)
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw MigrationError.cannotRead(
                    path: relativePath,
                    reason: error.localizedDescription
                )
            }
            let hadUTF8ByteOrderMark = data.starts(with: utf8ByteOrderMark)
            let sourceData = hadUTF8ByteOrderMark ? data.dropFirst(utf8ByteOrderMark.count) : data[...]
            guard let source = String(data: sourceData, encoding: .utf8) else {
                throw MigrationError.cannotRead(
                    path: relativePath,
                    reason: "The source is not valid UTF-8."
                )
            }

            let syntax = Parser.parse(source: source)
            if Syntax(syntax).hasError {
                diagnostics.append(
                    MigrationDiagnostic(
                        code: "migrate.parse-error",
                        path: relativePath,
                        message: "The source contains invalid Swift syntax; no files were written."
                    )
                )
            }
            parsedSources.append(
                ParsedMigrationSource(
                    url: url,
                    path: relativePath,
                    source: source,
                    syntax: syntax,
                    hadUTF8ByteOrderMark: hadUTF8ByteOrderMark
                )
            )
        }

        guard diagnostics.isEmpty else {
            return MigrationPlan(
                scannedFileCount: parsedSources.count,
                changes: [],
                diagnostics: diagnostics
            )
        }

        let rootShadowedNames = parsedSources.reduce(into: Set<String>()) { names, parsed in
            names.formUnion(innoDIAttributeShadowNames(in: parsed.syntax))
        }
        var changes: [MigrationFileChange] = []
        for parsed in parsedSources {
            let attributeContext = unqualifiedInnoDIAttributeContext(
                in: parsed.syntax,
                additionalAmbiguousNames: rootShadowedNames
            )
            let rewriter = InnoDISourceMigrationRewriter(
                path: parsed.path,
                attributeContext: attributeContext
            )
            let rewritten = rewriter.rewrite(parsed.syntax)
            let migratedSource = rewritten.description
            diagnostics.append(contentsOf: rewriter.diagnostics)

            if migratedSource != parsed.source {
                changes.append(
                    MigrationFileChange(
                        path: parsed.path,
                        originalSource: parsed.source,
                        migratedSource: migratedSource,
                        hadUTF8ByteOrderMark: parsed.hadUTF8ByteOrderMark
                    )
                )
            }
        }

        return MigrationPlan(
            scannedFileCount: parsedSources.count,
            changes: changes.sorted { $0.path < $1.path },
            diagnostics: diagnostics
        )
    }

    @discardableResult
    public func run(root: URL, mode: MigrationMode) throws -> MigrationPlan {
        try run(
            root: root,
            mode: mode,
            beforeWritingChange: nil
        )
    }

    @discardableResult
    func run(
        root: URL,
        mode: MigrationMode,
        beforeWritingChange: ((MigrationFileChange, Int) throws -> Void)?
    ) throws -> MigrationPlan {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let anchoredRoot = try AnchoredMigrationRoot(url: root)
        defer { anchoredRoot.close() }
        let plan = try plan(root: root)
        guard mode == .write, plan.canWrite else {
            return plan
        }

        // Planning above parses and transforms every Swift source before this
        // first write. An ambiguous legacy shape therefore cannot leave the
        // package in a partially migrated state.
        let fileManager = FileManager.default
        for change in plan.changes {
            let file = try anchoredFile(for: change.path, under: anchoredRoot)
            defer { file.close() }
            let fileURL = root.appendingPathComponent(change.path)
            let directoryURL = fileURL.deletingLastPathComponent()
            guard fileManager.isWritableFile(atPath: fileURL.path(percentEncoded: false)),
                  fileManager.isWritableFile(atPath: directoryURL.path(percentEncoded: false)) else {
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "The file or its containing directory is not writable."
                )
            }
            guard try source(
                change.originalSource,
                for: change,
                matchesContentsOf: file
            ) else {
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "The source changed while the migration plan was being prepared; no files were written."
                )
            }
        }

        var writtenChanges: [MigrationFileChange] = []
        for (index, change) in plan.changes.enumerated() {
            do {
                try beforeWritingChange?(change, index)
                let file = try anchoredFile(for: change.path, under: anchoredRoot)
                defer { file.close() }
                guard try source(
                    change.originalSource,
                    for: change,
                    matchesContentsOf: file
                ) else {
                    throw MigrationError.cannotWrite(
                        path: change.path,
                        reason: "The source changed after write preflight; the remaining files were not written."
                    )
                }
                try write(change.migratedSource, for: change, to: file)
                writtenChanges.append(change)
            } catch {
                var rollbackFailures: [String] = []
                for written in writtenChanges.reversed() {
                    do {
                        let writtenFile = try anchoredFile(
                            for: written.path,
                            under: anchoredRoot
                        )
                        defer { writtenFile.close() }
                        guard try source(
                            written.migratedSource,
                            for: written,
                            matchesContentsOf: writtenFile
                        ) else {
                            rollbackFailures.append(written.path)
                            continue
                        }
                        try write(
                            written.originalSource,
                            for: written,
                            to: writtenFile
                        )
                    } catch {
                        rollbackFailures.append(written.path)
                    }
                }
                let rollbackNote = rollbackFailures.isEmpty
                    ? "All earlier writes were rolled back."
                    : "Rollback also failed for: \(rollbackFailures.joined(separator: ", "))."
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "\(migrationErrorDescription(error)) \(rollbackNote)"
                )
            }
        }
        return plan
    }
}
