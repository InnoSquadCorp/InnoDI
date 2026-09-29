import SwiftSyntax

/// InnoDI 7.0 stops re-exporting SwiftUI from `InnoDISwiftUI`.
///
/// A file that imports `InnoDISwiftUI` without importing SwiftUI loses
/// SwiftUI's names, including the `SwiftUI.` qualifiers in generated
/// feature-root helpers and environment bridges. This rule inserts
/// `import SwiftUI` right after such an `InnoDISwiftUI` import. An exported
/// `InnoDISwiftUI` import gets an exported SwiftUI import, so the file's own
/// clients keep seeing SwiftUI. A file that already imports SwiftUI in any
/// form is left unchanged, which makes the rule idempotent.
func addingSwiftUIImportForInnoDISwiftUI(
    to source: SourceFileSyntax
) -> SourceFileSyntax {
    let collector = ModuleImportCollector(viewMode: .sourceAccurate)
    collector.walk(source)
    guard collector.swiftUIImportCount == 0,
          !collector.innoDISwiftUIImports.isEmpty else {
        return source
    }

    // One insertion after the first unconditional import covers every
    // configuration. Imports that only appear in `#if` clauses each get an
    // insertion in their own clause.
    let targets: [ImportDeclSyntax]
    if let topLevel = collector.innoDISwiftUIImports.first(where: {
        $0.parent?.parent?.is(SourceFileSyntax.self) == true
    }) {
        targets = [topLevel]
    } else {
        var seenClauses: Set<SyntaxIdentifier> = []
        targets = collector.innoDISwiftUIImports.filter { importDecl in
            guard let list = importDecl.parent?.parent else { return false }
            return seenClauses.insert(list.id).inserted
        }
    }
    let targetIDs = Set(targets.map(\.id))
    let exportedTargetIDs = Set(targets.filter(isExported).map(\.id))
    return SwiftUIImportInserter(
        targetIDs: targetIDs,
        exportedTargetIDs: exportedTargetIDs
    ).rewrite(source).cast(SourceFileSyntax.self)
}

private func importedModuleName(_ node: ImportDeclSyntax) -> String? {
    node.path.first?.name.text
}

private func isExported(_ node: ImportDeclSyntax) -> Bool {
    node.attributes.contains { element in
        element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported"
    }
}

private final class ModuleImportCollector: SyntaxVisitor {
    private(set) var swiftUIImportCount = 0
    private(set) var innoDISwiftUIImports: [ImportDeclSyntax] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        switch importedModuleName(node) {
        case "SwiftUI":
            swiftUIImportCount += 1
        case "InnoDISwiftUI":
            innoDISwiftUIImports.append(node)
        default:
            break
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

private final class SwiftUIImportInserter: SyntaxRewriter {
    private let targetIDs: Set<SyntaxIdentifier>
    private let exportedTargetIDs: Set<SyntaxIdentifier>

    init(targetIDs: Set<SyntaxIdentifier>, exportedTargetIDs: Set<SyntaxIdentifier>) {
        self.targetIDs = targetIDs
        self.exportedTargetIDs = exportedTargetIDs
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        var items: [CodeBlockItemSyntax] = []
        var inserted = false
        for item in node {
            items.append(item)
            guard let importDecl = item.item.as(ImportDeclSyntax.self),
                  targetIDs.contains(importDecl.id) else {
                continue
            }
            items.append(
                makeSwiftUIImport(
                    after: importDecl,
                    exported: exportedTargetIDs.contains(importDecl.id)
                )
            )
            inserted = true
        }
        let list = inserted ? CodeBlockItemListSyntax(items) : node
        return super.visit(list)
    }

    private func makeSwiftUIImport(
        after anchor: ImportDeclSyntax,
        exported: Bool
    ) -> CodeBlockItemSyntax {
        let indentation = anchor.leadingTrivia.pieces.reversed().prefix { piece in
            if case .newlines = piece { return false }
            if case .carriageReturnLineFeeds = piece { return false }
            return true
        }
        let leadingTrivia = Trivia(pieces: [.newlines(1)] + indentation.reversed())
        let attributes: AttributeListSyntax = exported
            ? AttributeListSyntax([
                .attribute(
                    AttributeSyntax(
                        atSign: .atSignToken(),
                        attributeName: IdentifierTypeSyntax(name: .identifier("_exported")),
                        trailingTrivia: .space
                    )
                ),
            ])
            : AttributeListSyntax([])
        let importDecl = ImportDeclSyntax(
            leadingTrivia: leadingTrivia,
            attributes: attributes,
            importKeyword: .keyword(.import, trailingTrivia: .space),
            path: ImportPathComponentListSyntax([
                ImportPathComponentSyntax(name: .identifier("SwiftUI")),
            ])
        )
        return CodeBlockItemSyntax(item: .decl(DeclSyntax(importDecl)))
    }
}
