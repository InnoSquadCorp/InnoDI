import Foundation
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
        let plan = try plan(root: root)
        guard mode == .write, plan.canWrite else {
            return plan
        }

        // Planning above parses and transforms every Swift source before this
        // first write. An ambiguous legacy shape therefore cannot leave the
        // package in a partially migrated state.
        let fileManager = FileManager.default
        for change in plan.changes {
            let fileURL = root.appendingPathComponent(change.path)
            let directoryURL = fileURL.deletingLastPathComponent()
            guard fileManager.isWritableFile(atPath: fileURL.path(percentEncoded: false)),
                  fileManager.isWritableFile(atPath: directoryURL.path(percentEncoded: false)) else {
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "The file or its containing directory is not writable."
                )
            }
            let currentData: Data
            do {
                currentData = try Data(contentsOf: fileURL)
            } catch {
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "Could not re-read the source during write preflight: \(error.localizedDescription)"
                )
            }
            let plannedData = try encodedData(
                change.originalSource,
                for: change
            )
            guard currentData == plannedData else {
                throw MigrationError.cannotWrite(
                    path: change.path,
                    reason: "The source changed while the migration plan was being prepared; no files were written."
                )
            }
        }

        var writtenChanges: [MigrationFileChange] = []
        for (index, change) in plan.changes.enumerated() {
            let fileURL = root.appendingPathComponent(change.path)
            do {
                try beforeWritingChange?(change, index)
                guard try source(
                    change.originalSource,
                    for: change,
                    matchesContentsOf: fileURL
                ) else {
                    throw MigrationError.cannotWrite(
                        path: change.path,
                        reason: "The source changed after write preflight; the remaining files were not written."
                    )
                }
                try write(change.migratedSource, for: change, to: fileURL)
                writtenChanges.append(change)
            } catch {
                var rollbackFailures: [String] = []
                for written in writtenChanges.reversed() {
                    let writtenURL = root.appendingPathComponent(written.path)
                    do {
                        guard try source(
                            written.migratedSource,
                            for: written,
                            matchesContentsOf: writtenURL
                        ) else {
                            rollbackFailures.append(written.path)
                            continue
                        }
                        try write(
                            written.originalSource,
                            for: written,
                            to: writtenURL
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

private extension InnoDIMigrator {
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

    func unqualifiedInnoDIAttributeContext(
        in source: SourceFileSyntax,
        additionalAmbiguousNames: Set<String>
    ) -> UnqualifiedInnoDIAttributeContext {
        let topLevelImportOffsets = Set(
            source.statements.compactMap { item in
                item.item.as(ImportDeclSyntax.self)?.position.utf8Offset
            }
        )
        let collector = InnoDIAttributeOwnershipCollector(
            topLevelImportOffsets: topLevelImportOffsets
        )
        collector.walk(source)
        return UnqualifiedInnoDIAttributeContext(
            availableNames: collector.availableNames,
            ambiguousNames: collector.conditionalImportNames
                .union(collector.untrustedImportNames)
                .union(additionalAmbiguousNames)
        )
    }

    func innoDIAttributeShadowNames(
        in source: SourceFileSyntax
    ) -> Set<String> {
        let collector = InnoDIAttributeOwnershipCollector(
            topLevelImportOffsets: []
        )
        collector.walk(source)
        return collector.shadowedNames
            .union(collector.exportedUntrustedImportNames)
    }
}

private struct UnqualifiedInnoDIAttributeContext {
    let availableNames: Set<String>
    let ambiguousNames: Set<String>

    func allows(_ name: String) -> Bool {
        availableNames.contains(name) && !ambiguousNames.contains(name)
    }
}

private final class InnoDIAttributeOwnershipCollector: SyntaxVisitor {
    private static let innoDINames: Set<String> = [
        "DIContainer",
        "Provide",
        "SubContainer",
    ]
    private static let innoDISwiftUINames: Set<String> = [
        "DIContainer",
        "DIFeatureRoot",
        "Provide",
        "SubContainer",
    ]

    private(set) var availableNames: Set<String> = []
    private(set) var conditionalImportNames: Set<String> = []
    private(set) var untrustedImportNames: Set<String> = []
    private(set) var exportedUntrustedImportNames: Set<String> = []
    private(set) var shadowedNames: Set<String> = []
    private let topLevelImportOffsets: Set<Int>

    init(topLevelImportOffsets: Set<Int>) {
        self.topLevelImportOffsets = topLevelImportOffsets
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let importedNames = innoDIAttributeNames(importedBy: node)
        if importsUntrustedMacroNamespace(node) {
            untrustedImportNames.formUnion(Self.innoDINames)
            untrustedImportNames.formUnion(Self.innoDISwiftUINames)
            if isExportedImport(node) {
                exportedUntrustedImportNames.formUnion(Self.innoDINames)
                exportedUntrustedImportNames.formUnion(Self.innoDISwiftUINames)
            }
        } else if node.importKindSpecifier?.text == "macro",
                  let importedNameToken = node.path.last?.name,
                  importedNames.isEmpty {
            let importedName = canonicalIdentifier(importedNameToken)
            if Self.innoDISwiftUINames.contains(importedName) {
                untrustedImportNames.insert(importedName)
                if isExportedImport(node) {
                    exportedUntrustedImportNames.insert(importedName)
                }
            }
        }
        if topLevelImportOffsets.contains(node.position.utf8Offset) {
            availableNames.formUnion(importedNames)
        } else {
            conditionalImportNames.formUnion(importedNames)
        }
        return .skipChildren
    }

    private func innoDIAttributeNames(
        importedBy node: ImportDeclSyntax
    ) -> Set<String> {
        let path = Array(node.path.map { canonicalIdentifier($0.name) })
        guard let module = path.first else { return [] }

        if node.importKindSpecifier == nil, path.count == 1 {
            switch module {
            case "InnoDI":
                return Self.innoDINames
            case "InnoDISwiftUI":
                return Self.innoDISwiftUINames
            default:
                return []
            }
        }

        guard node.importKindSpecifier?.text == "macro",
              path.count == 2,
              let name = path.last else {
            return []
        }
        if module == "InnoDI", Self.innoDINames.contains(name) {
            return [name]
        } else if module == "InnoDISwiftUI", name == "DIFeatureRoot" {
            return [name]
        }
        return []
    }

    private func importsUntrustedMacroNamespace(_ node: ImportDeclSyntax) -> Bool {
        let path = Array(node.path.map { canonicalIdentifier($0.name) })
        guard node.importKindSpecifier == nil,
              let module = path.first else {
            return false
        }
        return !Self.trustedMacroFreeModules.contains(module)
            && module != "InnoDI"
            && module != "InnoDISwiftUI"
    }

    private func isExportedImport(_ node: ImportDeclSyntax) -> Bool {
        node.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self),
                  let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
                return false
            }
            return canonicalIdentifier(identifier.name) == "_exported"
        } || node.modifiers.contains {
            canonicalIdentifier($0.name) == "public"
        }
    }

    private static let trustedMacroFreeModules: Set<String> = [
        "AppKit",
        "Combine",
        "Dispatch",
        "Foundation",
        "Observation",
        "OSLog",
        "Swift",
        "SwiftUI",
        "Testing",
        "UIKit",
        "XCTest",
        "_Concurrency",
    ]

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        recordShadow(canonicalIdentifier(node.name))
        return .visitChildren
    }

    private func recordShadow(_ name: String) {
        if Self.innoDISwiftUINames.contains(name) {
            shadowedNames.insert(name)
        }
    }
}

private final class MigratableProvideCollector: SyntaxVisitor {
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private(set) var attributeOffsets: Set<Int> = []

    init(attributeContext: UnqualifiedInnoDIAttributeContext) {
        self.attributeContext = attributeContext
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let isContainer = node.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else {
                return false
            }
            return isInnoDIAttribute(
                attribute,
                named: "DIContainer",
                context: attributeContext
            )
        }
        if isContainer {
            let collector = ConditionalContainerProvideCollector(
                attributeContext: attributeContext
            )
            collector.walk(node.memberBlock)
            attributeOffsets.formUnion(collector.attributeOffsets)
        }
        return .visitChildren
    }

    override func visit(_: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

private final class ConditionalContainerProvideCollector: SyntaxVisitor {
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private(set) var attributeOffsets: Set<Int> = []

    init(attributeContext: UnqualifiedInnoDIAttributeContext) {
        self.attributeContext = attributeContext
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.attributes {
            guard let attribute = element.as(AttributeSyntax.self),
                  isInnoDIAttribute(
                    attribute,
                    named: "Provide",
                    context: attributeContext
                  ) else {
                continue
            }
            attributeOffsets.insert(attribute.position.utf8Offset)
        }
        return .skipChildren
    }

    override func visit(_: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

private final class InnoDISourceMigrationRewriter: SyntaxRewriter {
    private let path: String
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private var migratableProvideOffsets: Set<Int> = []
    private(set) var diagnostics: [MigrationDiagnostic] = []

    init(
        path: String,
        attributeContext: UnqualifiedInnoDIAttributeContext
    ) {
        self.path = path
        self.attributeContext = attributeContext
        super.init(viewMode: .sourceAccurate)
    }

    func rewrite(_ source: SourceFileSyntax) -> SourceFileSyntax {
        let ambiguityCollector = UnqualifiedLegacyAmbiguityCollector(
            attributeContext: attributeContext
        )
        ambiguityCollector.walk(source)
        if !ambiguityCollector.names.isEmpty {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.unqualified-ownership-ambiguous",
                    path: path,
                    message: "Cannot prove that unqualified legacy attribute(s) \(ambiguityCollector.names.sorted().joined(separator: ", ")) belong to InnoDI. Qualify them with their module before rerunning; no files were written."
                )
            )
        }

        let provideCollector = MigratableProvideCollector(
            attributeContext: attributeContext
        )
        provideCollector.walk(source)
        migratableProvideOffsets = provideCollector.attributeOffsets

        let rewritten = visit(source)
        let concreteArguments = LegacyConcreteArgumentCollector(
            attributeContext: attributeContext
        )
        concreteArguments.walk(rewritten)
        if concreteArguments.count > 0,
           !diagnostics.contains(where: { $0.code == "migrate.concrete-argument-unsupported" }) {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.concrete-placement-ambiguous",
                    path: path,
                    message: "Cannot safely migrate every remaining InnoDI @Provide(concrete:) use automatically; move it to a direct @DIContainer member or remove the argument manually. No files were written."
                )
            )
        }
        let featureRoots = LegacyFeatureRootCollector(
            attributeContext: attributeContext
        )
        featureRoots.walk(rewritten)
        if featureRoots.count > 0 {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.feature-root-ambiguous",
                    path: path,
                    message: "Cannot safely migrate @DIFeatureRoot automatically; no files were written."
                )
            )
        }
        return rewritten
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> DeclSyntax {
        DeclSyntax(node)
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        ExprSyntax(node)
    }

    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        guard node.bindings.count == 1,
              let binding = node.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              binding.typeAnnotation != nil else {
            return super.visit(node)
        }
        let subContainers = node.attributes.compactMap { element -> AttributeSyntax? in
            guard let attribute = element.as(AttributeSyntax.self),
                  isInnoDIAttribute(
                    attribute,
                    named: "SubContainer",
                    context: attributeContext
                  ) else {
                return nil
            }
            return attribute
        }
        let featureRoots = node.attributes.compactMap { element -> AttributeSyntax? in
            guard let attribute = element.as(AttributeSyntax.self),
                  isInnoDIAttribute(
                    attribute,
                    named: "DIFeatureRoot",
                    context: attributeContext
                  ) else {
                return nil
            }
            return attribute
        }

        guard !featureRoots.isEmpty,
              subContainers.count == 1,
              let migratedSubContainer = migrateFeatureRoots(
                featureRoots,
                into: subContainers[0],
                propertyName: canonicalIdentifier(identifier.identifier)
              ) else {
            return super.visit(node)
        }

        let subContainerOffset = subContainers[0].position.utf8Offset
        let featureRootOffsets = Set(featureRoots.map { $0.position.utf8Offset })
        var migratedAttributes: [AttributeListSyntax.Element] = []
        for element in node.attributes {
            if let attribute = element.as(AttributeSyntax.self) {
                let offset = attribute.position.utf8Offset
                if featureRootOffsets.contains(offset) {
                    continue
                }
                if offset == subContainerOffset {
                    migratedAttributes.append(.attribute(migratedSubContainer))
                    continue
                }
            }
            migratedAttributes.append(element)
        }
        let attributes = AttributeListSyntax(migratedAttributes)
        return super.visit(node.with(\.attributes, attributes))
    }

    override func visit(_ node: AttributeSyntax) -> AttributeSyntax {
        guard migratableProvideOffsets.contains(node.position.utf8Offset),
              isInnoDIAttribute(
                node,
                named: "Provide",
                context: attributeContext
              ),
              let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return super.visit(node)
        }

        let concreteArguments = Array(
            arguments.filter { $0.label.map(canonicalIdentifier) == "concrete" }
        )
        guard !concreteArguments.isEmpty else {
            return super.visit(node)
        }

        guard concreteArguments.count == 1,
              concreteArguments[0].expression.is(BooleanLiteralExprSyntax.self),
              !containsComment(concreteArguments[0]) else {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.concrete-argument-unsupported",
                    path: path,
                    message: "Only comment-free concrete: true or concrete: false arguments can be removed automatically; no files were written."
                )
            )
            return super.visit(node)
        }

        var filteredArguments = Array(
            arguments.filter { $0.label.map(canonicalIdentifier) != "concrete" }
        )
        if !arguments.description.contains("\n"),
           !containsComment(arguments),
           var last = filteredArguments.last,
           last.trailingComma != nil {
            last = last.with(\.trailingComma, nil)
            filteredArguments[filteredArguments.index(before: filteredArguments.endIndex)] = last
        }
        let filtered = LabeledExprListSyntax(filteredArguments)
        return super.visit(
            node.with(\.arguments, .argumentList(filtered))
        )
    }

    private func migrateFeatureRoots(
        _ legacyAttributes: [AttributeSyntax],
        into subContainer: AttributeSyntax,
        propertyName: String
    ) -> AttributeSyntax? {
        guard !containsComment(subContainer),
              !legacyAttributes.contains(where: { containsComment($0) }),
              let existingArguments = subContainer.arguments?.as(LabeledExprListSyntax.self),
              !existingArguments.contains(where: {
                $0.label.map(canonicalIdentifier) == "featureRoot"
                    || $0.label.map(canonicalIdentifier) == "featureRoots"
              }) else {
            return nil
        }

        let roots = legacyAttributes.compactMap(parseLegacyFeatureRoot)
        let helperNames = roots.map { $0.aliasText ?? propertyName }
        guard roots.count == legacyAttributes.count,
              roots.filter({ $0.aliasText == nil }).count <= 1,
              Set(roots.compactMap(\.aliasText)).count == roots.compactMap(\.aliasText).count,
              Set(helperNames).count == helperNames.count else {
            return nil
        }

        let newArgument: LabeledExprSyntax
        if roots.count == 1, roots[0].aliasExpression == nil {
            newArgument = LabeledExprSyntax(
                label: .identifier("featureRoot"),
                colon: .colonToken(trailingTrivia: .space),
                expression: roots[0].rootType
            )
        } else {
            var arrayElements: [ArrayElementSyntax] = []
            for (index, root) in roots.enumerated() {
                var arguments = [
                    LabeledExprSyntax(expression: root.rootType)
                ]
                if let alias = root.aliasExpression {
                    if var rootArgument = arguments.first {
                        rootArgument = rootArgument.with(
                            \.trailingComma,
                            .commaToken(trailingTrivia: .space)
                        )
                        arguments[0] = rootArgument
                    }
                    arguments.append(
                        LabeledExprSyntax(
                            label: .identifier("as"),
                            colon: .colonToken(trailingTrivia: .space),
                            expression: alias
                        )
                    )
                }
                let call = FunctionCallExprSyntax(
                    calledExpression: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(
                            baseName: .identifier("InnoDI")
                        ),
                        name: .identifier("FeatureRoot")
                    ),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax(arguments),
                    rightParen: .rightParenToken()
                )
                arrayElements.append(
                    ArrayElementSyntax(
                        expression: call,
                        trailingComma: index == roots.index(before: roots.endIndex)
                            ? nil
                            : .commaToken(trailingTrivia: .space)
                    )
                )
            }
            let elements = ArrayElementListSyntax(arrayElements)
            newArgument = LabeledExprSyntax(
                label: .identifier("featureRoots"),
                colon: .colonToken(trailingTrivia: .space),
                expression: ArrayExprSyntax(
                    leftSquare: .leftSquareToken(),
                    elements: elements,
                    rightSquare: .rightSquareToken()
                )
            )
        }

        var arguments = Array(existingArguments)
        if var last = arguments.last {
            if last.trailingComma == nil {
                last = last.with(
                    \.trailingComma,
                    .commaToken(trailingTrivia: .space)
                )
                arguments[arguments.index(before: arguments.endIndex)] = last
            }
        }
        arguments.append(newArgument)

        return subContainer.with(
            \.arguments,
            .argumentList(
                LabeledExprListSyntax(arguments)
            )
        )
    }

    private struct LegacyFeatureRoot {
        let rootType: ExprSyntax
        let aliasExpression: ExprSyntax?
        let aliasText: String?
    }

    private func parseLegacyFeatureRoot(
        _ attribute: AttributeSyntax
    ) -> LegacyFeatureRoot? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        let values = Array(arguments)
        guard values.count == 1 || values.count == 2,
              values[0].label == nil,
              isTypeSelfExpression(values[0].expression) else {
            return nil
        }
        guard values.count == 2 else {
            return LegacyFeatureRoot(
                rootType: values[0].expression.trimmed,
                aliasExpression: nil,
                aliasText: nil
            )
        }
        guard values[1].label.map(canonicalIdentifier) == "as",
              let literal = values[1].expression.as(StringLiteralExprSyntax.self),
              let aliasText = stringLiteralValue(literal),
              isValidSwiftIdentifier(aliasText) else {
            return nil
        }
        return LegacyFeatureRoot(
            rootType: values[0].expression.trimmed,
            aliasExpression: values[1].expression.trimmed,
            aliasText: aliasText
        )
    }
}

private final class LegacyConcreteArgumentCollector: SyntaxVisitor {
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private(set) var count = 0

    init(attributeContext: UnqualifiedInnoDIAttributeContext) {
        self.attributeContext = attributeContext
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if isInnoDIAttribute(
            node,
            named: "Provide",
            context: attributeContext
        ), let arguments = node.arguments?.as(LabeledExprListSyntax.self),
           arguments.contains(where: {
               $0.label.map(canonicalIdentifier) == "concrete"
           }) {
            count += 1
        }
        return .visitChildren
    }
}

private final class UnqualifiedLegacyAmbiguityCollector: SyntaxVisitor {
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private(set) var names: Set<String> = []

    init(attributeContext: UnqualifiedInnoDIAttributeContext) {
        self.attributeContext = attributeContext
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        guard let identifier = node.attributeName.as(IdentifierTypeSyntax.self) else {
            return .visitChildren
        }
        let name = canonicalIdentifier(identifier.name)
        if name == "DIFeatureRoot", !attributeContext.allows(name) {
            names.insert("@DIFeatureRoot")
        } else if name == "Provide",
                  !attributeContext.allows(name),
                  let arguments = node.arguments?.as(LabeledExprListSyntax.self),
                  arguments.contains(where: {
                      $0.label.map(canonicalIdentifier) == "concrete"
                  }) {
            names.insert("@Provide(concrete:)")
        }
        return .visitChildren
    }
}

private final class LegacyFeatureRootCollector: SyntaxVisitor {
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private(set) var count = 0

    init(attributeContext: UnqualifiedInnoDIAttributeContext) {
        self.attributeContext = attributeContext
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if isInnoDIAttribute(
            node,
            named: "DIFeatureRoot",
            context: attributeContext
        ) {
            count += 1
        }
        return .visitChildren
    }
}

private func isInnoDIAttribute(
    _ attribute: AttributeSyntax,
    named name: String,
    context: UnqualifiedInnoDIAttributeContext
) -> Bool {
    if let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) {
        return context.allows(name) && canonicalIdentifier(identifier.name) == name
    }
    guard let member = attribute.attributeName.as(MemberTypeSyntax.self),
          canonicalIdentifier(member.name) == name,
          let module = member.baseType.as(IdentifierTypeSyntax.self) else {
        return false
    }
    let allowedModule = name == "DIFeatureRoot" ? "InnoDISwiftUI" : "InnoDI"
    return canonicalIdentifier(module.name) == allowedModule
}

private func isTypeSelfExpression(_ expression: ExprSyntax) -> Bool {
    guard let member = expression.as(MemberAccessExprSyntax.self) else {
        return false
    }
    return member.base != nil && canonicalIdentifier(member.declName.baseName) == "self"
}

private func canonicalIdentifier(_ token: TokenSyntax) -> String {
    let text = token.text
    guard text.count >= 2,
          text.first == "`",
          text.last == "`" else {
        return text
    }
    return String(text.dropFirst().dropLast())
}

private func stringLiteralValue(_ literal: StringLiteralExprSyntax) -> String? {
    guard literal.segments.count == 1,
          let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
        return nil
    }
    return segment.content.text
}

private func isValidSwiftIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty,
          !swiftReservedKeywords.contains(value),
          let head = value.unicodeScalars.first,
          head == "_" || CharacterSet.letters.contains(head) else {
        return false
    }
    return value.unicodeScalars.dropFirst().allSatisfy {
        $0 == "_" || CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
    }
}

private func containsComment(_ syntax: some SyntaxProtocol) -> Bool {
    let source = syntax.description
    return source.contains("//") || source.contains("/*")
}

private let swiftReservedKeywords: Set<String> = [
    "associatedtype", "actor", "any", "as", "await", "break", "case", "catch",
    "class", "continue", "default", "defer", "deinit", "do", "else", "enum",
    "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard",
    "if", "import", "in", "init", "inout", "internal", "is", "isolated", "let",
    "macro", "nil", "nonisolated", "open", "operator", "package", "precedencegroup",
    "private", "protocol", "public", "repeat", "rethrows", "return", "self",
    "Self", "some", "static", "struct", "subscript", "super", "switch", "throw",
    "throws", "true", "try", "typealias", "var", "where", "while",
]
