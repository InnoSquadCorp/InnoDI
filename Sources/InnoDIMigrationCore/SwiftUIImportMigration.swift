import SwiftSyntax

/// InnoDI 7.0 stops re-exporting SwiftUI from `InnoDISwiftUI`.
///
/// A file that imports `InnoDISwiftUI` saw every SwiftUI name through it, at
/// that import's access level and, for an `@_exported` import, in the file's
/// clients too. Without SwiftUI's names the file fails to compile, including
/// the `SwiftUI.` qualifiers in generated feature-root helpers and
/// environment bridges. This rule gives such a file a full `import SwiftUI`
/// with the same visibility: it raises an existing one to the access level
/// and `@_exported` attribute the `InnoDISwiftUI` import had, or inserts one
/// right after that import. A scoped import such as `import struct
/// SwiftUI.Text`, or one inside an `#if` clause the `InnoDISwiftUI` import is
/// not in, does not provide every SwiftUI name, so it never counts. An
/// `InnoDISwiftUI` import inside an `#if` clause gets its SwiftUI import in the
/// same clause unless an enclosing scope already provides one. The rule is
/// idempotent.
func addingSwiftUIImportForInnoDISwiftUI(
    to source: SourceFileSyntax
) -> SourceFileSyntax {
    let collector = ImportScopeCollector(viewMode: .sourceAccurate)
    collector.walk(source)

    var insertions: [Int: SwiftUIImportVisibility] = [:]
    var upgrades: [Int: SwiftUIImportVisibility] = [:]
    var planned: [Int: [SwiftUIImportVisibility]] = [:]
    // Scopes are recorded in source order, so an enclosing scope, and any
    // import planned for it, is settled before the clauses it contains.
    for scope in collector.scopes {
        guard let anchor = scope.innoDISwiftUIImports.first else { continue }
        let required = scope.innoDISwiftUIImports.dropFirst().reduce(anchor.visibility) {
            $0.union($1.visibility)
        }
        let provided = collector.chain(of: scope.id).flatMap { id -> [SwiftUIImportVisibility] in
            (collector.scopes.first { $0.id == id }?.fullSwiftUIImports.map(\.visibility) ?? [])
                + (planned[id] ?? [])
        }
        if provided.contains(where: { $0.satisfies(required) }) { continue }
        if let existing = scope.fullSwiftUIImports.first {
            upgrades[existing.offset] = required
        } else {
            insertions[anchor.offset] = required
        }
        planned[scope.id, default: []].append(required)
    }
    guard !insertions.isEmpty || !upgrades.isEmpty else { return source }

    let newline: TriviaPiece = source.description.contains("\r\n")
        ? .carriageReturnLineFeeds(1)
        : .newlines(1)
    return SwiftUIImportRewriter(
        insertions: insertions,
        upgrades: upgrades,
        newline: newline
    ).rewrite(source).cast(SourceFileSyntax.self)
}

/// The SwiftUI visibility an import grants: whether clients see it, and the
/// access level it is written with.
struct SwiftUIImportVisibility: Equatable {
    /// `private` through `public`; `nil` when the import has no modifier and
    /// so takes the module's default import access level.
    var accessRank: Int?
    var exported: Bool

    fileprivate static let accessKeywords: [Keyword] = [.private, .fileprivate, .internal, .package, .public]
    private static let internalRank = 2
    private static let publicRank = 4

    var accessKeyword: Keyword? {
        accessRank.map { Self.accessKeywords[$0] }
    }

    func union(_ other: Self) -> Self {
        var result = self
        result.exported = exported || other.exported
        if let rank = other.accessRank {
            result.accessRank = max(accessRank ?? rank, rank)
        }
        return result
    }

    /// Whether this import alone grants what `required` asks for. An
    /// unmodified import is `internal` or `public` depending on the build's
    /// default, so it only stands in for `internal` and below, and only a
    /// `public` or exported import stands in for an unmodified one.
    func satisfies(_ required: Self) -> Bool {
        if required.exported && !exported { return false }
        if exported { return true }
        switch (accessRank, required.accessRank) {
        case (nil, nil):
            return true
        case let (nil, requiredRank?):
            return requiredRank <= Self.internalRank
        case let (rank?, nil):
            return rank == Self.publicRank
        case let (rank?, requiredRank?):
            return rank >= requiredRank
        }
    }
}

extension SwiftUIImportVisibility {
    init(_ node: ImportDeclSyntax) {
        exported = node.attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported"
        }
        accessRank = node.modifiers.lazy
            .compactMap { modifier in
                Self.accessKeywords.firstIndex { modifier.name.tokenKind == .keyword($0) }
            }
            .first
    }
}

private struct RecordedImport {
    let offset: Int
    let visibility: SwiftUIImportVisibility
}

private struct ImportScope {
    let id: Int
    let parentID: Int?
    var innoDISwiftUIImports: [RecordedImport] = []
    /// Unscoped `import SwiftUI` declarations directly in this scope.
    var fullSwiftUIImports: [RecordedImport] = []
}

/// Records each code-block list that holds imports: the file scope and every
/// `#if` clause, nested or not.
private final class ImportScopeCollector: SyntaxVisitor {
    private(set) var scopes: [ImportScope] = []
    private var stack: [Int] = []

    func chain(of id: Int) -> [Int] {
        var result: [Int] = []
        var current: Int? = id
        while let value = current, let scope = scopes.first(where: { $0.id == value }) {
            result.append(value)
            current = scope.parentID
        }
        return result
    }

    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        let id = node.position.utf8Offset
        scopes.append(ImportScope(id: id, parentID: stack.last))
        stack.append(id)
        return .visitChildren
    }

    override func visitPost(_: CodeBlockItemListSyntax) {
        stack.removeLast()
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let scopeID = stack.last,
              let index = scopes.firstIndex(where: { $0.id == scopeID }) else {
            return .skipChildren
        }
        let path = node.path.map(\.name.text)
        let record = RecordedImport(
            offset: node.position.utf8Offset,
            visibility: SwiftUIImportVisibility(node)
        )
        if path.first == "InnoDISwiftUI" {
            scopes[index].innoDISwiftUIImports.append(record)
        } else if path == ["SwiftUI"], node.importKindSpecifier == nil {
            scopes[index].fullSwiftUIImports.append(record)
        }
        return .skipChildren
    }

    // Imports can only appear at file scope or inside file-scope `#if`
    // clauses, so declarations with bodies never need to be searched.
    override func visit(_: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

/// Applies the planned changes by the imports' offsets in the original tree.
/// Each list rewrites its children first, so nested clause lists are matched
/// against their original offsets before this list gains a new import.
private final class SwiftUIImportRewriter: SyntaxRewriter {
    private let insertions: [Int: SwiftUIImportVisibility]
    private let upgrades: [Int: SwiftUIImportVisibility]
    private let newline: TriviaPiece

    init(
        insertions: [Int: SwiftUIImportVisibility],
        upgrades: [Int: SwiftUIImportVisibility],
        newline: TriviaPiece
    ) {
        self.insertions = insertions
        self.upgrades = upgrades
        self.newline = newline
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        let rewritten = super.visit(node)
        let originals = Array(node)
        let updated = Array(rewritten)
        var items: [CodeBlockItemSyntax] = []
        var changed = false
        for index in updated.indices {
            var item = updated[index]
            guard let original = originals[index].item.as(ImportDeclSyntax.self),
                  let importDecl = item.item.as(ImportDeclSyntax.self) else {
                items.append(item)
                continue
            }
            let offset = original.position.utf8Offset
            if let visibility = upgrades[offset] {
                item = item.with(\.item, .decl(DeclSyntax(raising(importDecl, to: visibility))))
                changed = true
            }
            items.append(item)
            if let visibility = insertions[offset] {
                let next = index + 1 < updated.count ? updated[index + 1] : nil
                items.append(swiftUIImport(visibility, after: item, before: next))
                changed = true
            }
        }
        return changed ? CodeBlockItemListSyntax(items) : rewritten
    }

    private func raising(
        _ node: ImportDeclSyntax,
        to required: SwiftUIImportVisibility
    ) -> ImportDeclSyntax {
        let current = SwiftUIImportVisibility(node)
        let leadingTrivia = node.leadingTrivia
        var result = node.with(\.leadingTrivia, [])
        if required.exported && !current.exported {
            result.attributes = AttributeListSyntax(
                [.attribute(exportedAttribute())] + Array(result.attributes)
            )
        }
        if !current.satisfies(SwiftUIImportVisibility(accessRank: required.accessRank, exported: false)) {
            var modifiers: [DeclModifierSyntax] = required.accessKeyword.map {
                [DeclModifierSyntax(name: .keyword($0, trailingTrivia: .space))]
            } ?? []
            for modifier in result.modifiers
            where current.accessKeyword.map({ modifier.name.tokenKind != .keyword($0) }) ?? true {
                modifiers.append(modifier)
            }
            result.modifiers = DeclModifierListSyntax(modifiers)
        }
        return result.with(\.leadingTrivia, leadingTrivia)
    }

    private func swiftUIImport(
        _ visibility: SwiftUIImportVisibility,
        after anchor: CodeBlockItemSyntax,
        before next: CodeBlockItemSyntax?
    ) -> CodeBlockItemSyntax {
        var importDecl = ImportDeclSyntax(
            attributes: visibility.exported ? [.attribute(exportedAttribute())] : [],
            modifiers: DeclModifierListSyntax(
                visibility.accessKeyword.map {
                    [DeclModifierSyntax(name: .keyword($0, trailingTrivia: .space))]
                } ?? []
            ),
            importKeyword: .keyword(.import, trailingTrivia: .space),
            path: ImportPathComponentListSyntax([
                ImportPathComponentSyntax(name: .identifier("SwiftUI")),
            ])
        )
        // `import A; import B` keeps its style: the new import joins the line
        // with its own semicolon instead of running into the next import.
        if let semicolon = anchor.semicolon {
            importDecl.leadingTrivia = semicolon.trailingTrivia.isEmpty ? .space : []
            let nextOnSameLine = next.map { !$0.leadingTrivia.contains(where: \.isNewline) } ?? false
            return CodeBlockItemSyntax(
                item: .decl(DeclSyntax(importDecl)),
                semicolon: .semicolonToken(trailingTrivia: nextOnSameLine ? .space : [])
            )
        }
        let indentation = anchor.leadingTrivia.pieces.reversed().prefix { !$0.isNewline }
        importDecl.leadingTrivia = Trivia(pieces: [newline] + indentation.reversed())
        return CodeBlockItemSyntax(item: .decl(DeclSyntax(importDecl)))
    }

    private func exportedAttribute() -> AttributeSyntax {
        AttributeSyntax(
            atSign: .atSignToken(),
            attributeName: IdentifierTypeSyntax(name: .identifier("_exported")),
            trailingTrivia: .space
        )
    }
}
