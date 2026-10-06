import Foundation
import InnoDICore
import SwiftParser
import SwiftSyntax

public struct InnoDIMigrator {
    /// Imported modules treated like Apple frameworks: the user asserts they
    /// declare no attribute or macro named like an InnoDI attribute.
    public let trustedModules: Set<String>
    public let swiftUIImportAccess: MigrationSwiftUIImportAccess?

    public init(
        trustedModules: Set<String> = [],
        swiftUIImportAccess: MigrationSwiftUIImportAccess? = nil
    ) {
        self.trustedModules = trustedModules
        self.swiftUIImportAccess = swiftUIImportAccess
    }

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

        var rootShadowedNames: Set<String> = []
        var reexportedUntrustedModules: [String: Set<String>] = [:]
        for parsed in parsedSources {
            let context = innoDIAttributeShadowContext(in: parsed.syntax)
            rootShadowedNames.formUnion(context.names)
            for (name, modules) in context.modules {
                reexportedUntrustedModules[name, default: []].formUnion(modules)
            }
        }
        var changes: [MigrationFileChange] = []
        // This source-tree API has no authoritative target map. Treat an
        // explicit import anywhere in the requested root as a possible peer
        // rather than guessing that it belongs to another target.
        let hasExplicitSwiftUIImports = parsedSources.contains {
            containsExplicitSwiftUIImport(in: $0.syntax)
        }
        let implicitSwiftUIImportPaths = Set(parsedSources.filter {
            containsImplicitSwiftUIImport(in: $0.syntax)
        }.map(\.path))
        var outputHasImplicitSwiftUIImport = false
        var introducedNonPublicSwiftUIImportPaths: [String] = []
        for parsed in parsedSources {
            let attributeContext = unqualifiedInnoDIAttributeContext(
                in: parsed.syntax,
                additionalAmbiguousNames: rootShadowedNames,
                reexportedUntrustedModules: reexportedUntrustedModules
            )
            let rewriter = InnoDISourceMigrationRewriter(
                path: parsed.path,
                attributeContext: attributeContext,
                swiftUIImportAccess: swiftUIImportAccess,
                hasOtherExplicitSwiftUIImports: hasExplicitSwiftUIImports,
                hasOtherImplicitSwiftUIImports: implicitSwiftUIImportPaths.count
                    > (implicitSwiftUIImportPaths.contains(parsed.path) ? 1 : 0)
            )
            let rewritten = rewriter.rewrite(parsed.syntax)
            outputHasImplicitSwiftUIImport = outputHasImplicitSwiftUIImport
                || containsImplicitSwiftUIImport(in: rewritten)
            if containsNonPublicExplicitSwiftUIImport(in: rewritten),
               !containsNonPublicExplicitSwiftUIImport(in: parsed.syntax) {
                introducedNonPublicSwiftUIImportPaths.append(parsed.path)
            }
            let migratedSource = rewritten.description
            diagnostics.append(contentsOf: rewriter.diagnostics)
            if migratedSource != parsed.source, migratedSourceHasSyntaxErrors(migratedSource) {
                diagnostics.append(
                    MigrationDiagnostic(
                        code: "migrate.output-parse-error",
                        path: parsed.path,
                        message: "The migrated source would contain invalid Swift syntax, which is an InnoDI-Migrate defect; no files were written. Please report it with this file."
                    )
                )
            }

            if migratedSource != parsed.source {
                changes.append(
                    MigrationFileChange(
                        path: parsed.path,
                        originalSource: parsed.source,
                        migratedSource: migratedSource,
                        hadUTF8ByteOrderMark: parsed.hadUTF8ByteOrderMark,
                        rules: rewriter.appliedRules.sorted()
                    )
                )
            }
        }

        // Two files can introduce the conflicting imports in the same plan,
        // even when neither spelling existed in the original source tree.
        // Validate their combined proposed output before permitting any write.
        if outputHasImplicitSwiftUIImport {
            for path in introducedNonPublicSwiftUIImportPaths {
                diagnostics.append(MigrationDiagnostic(
                    code: "migrate.swiftui-import-access-ambiguous",
                    path: path,
                    message: mixedSwiftUIImportAccessMessage
                ))
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
        beforeWritingChange: ((MigrationFileChange, Int) throws -> Void)?,
        beforePublishingChange: ((MigrationFileChange, Bool) throws -> Void)? = nil
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
        var recoveryPaths: [String] = []
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
                recoveryPaths.append(try write(
                    change.migratedSource,
                    replacing: change.originalSource,
                    for: change,
                    to: file,
                    beforePublish: { try beforePublishingChange?(change, false) }
                ))
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
                        recoveryPaths.append(try write(
                            written.originalSource,
                            replacing: written.migratedSource,
                            for: written,
                            to: writtenFile,
                            beforePublish: { try beforePublishingChange?(written, true) }
                        ))
                    } catch {
                        rollbackFailures.append("\(written.path): \(migrationErrorDescription(error))")
                    }
                }
                let rollbackNote = rollbackFailures.isEmpty
                    ? "All earlier writes were rolled back."
                    : "Rollback also failed for: \(rollbackFailures.joined(separator: ", "))."
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "\(migrationErrorDescription(error)) \(rollbackNote) Retained recovery files: \(recoveryPaths.joined(separator: ", "))."
                )
            }
        }
        return MigrationPlan(
            scannedFileCount: plan.scannedFileCount,
            changes: plan.changes,
            diagnostics: plan.diagnostics,
            recoveryPaths: recoveryPaths
        )
    }
}

/// Every rewrite rebuilds syntax, so a defect in one could emit text that no
/// longer parses. Planning checks the output again and blocks the run
/// instead of writing it.
func migratedSourceHasSyntaxErrors(_ source: String) -> Bool {
    Syntax(Parser.parse(source: source)).hasError
}
