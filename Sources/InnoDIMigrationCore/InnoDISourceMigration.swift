import Foundation
import InnoDICore
import SwiftSyntax

// Attribute ownership analysis and legacy-source rewriting.
extension InnoDIMigrator {
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
            topLevelImportOffsets: topLevelImportOffsets,
            trustedModules: trustedModules
        )
        collector.walk(source)
        return UnqualifiedInnoDIAttributeContext(
            availableNames: collector.availableNames,
            ambiguousNames: collector.conditionalImportNames
                .union(collector.untrustedImportNames)
                .union(additionalAmbiguousNames),
            untrustedModules: collector.untrustedModules.sorted()
        )
    }

    func innoDIAttributeShadowNames(
        in source: SourceFileSyntax
    ) -> Set<String> {
        let collector = InnoDIAttributeOwnershipCollector(
            topLevelImportOffsets: [],
            trustedModules: trustedModules
        )
        collector.walk(source)
        return collector.shadowedNames
            .union(collector.exportedUntrustedImportNames)
    }
}

struct UnqualifiedInnoDIAttributeContext {
    let availableNames: Set<String>
    let ambiguousNames: Set<String>
    /// Imported modules that made InnoDI attribute names ambiguous.
    var untrustedModules: [String] = []

    func allows(_ name: String) -> Bool {
        availableNames.contains(name) && !ambiguousNames.contains(name)
    }
}

private final class InnoDIAttributeOwnershipCollector: SyntaxVisitor {
    private static let innoDINames: Set<String> = [
        "DIContainer",
        "DIContainerRole",
        "DIComponent",
        "DIHierarchyRoot",
        "Input",
        "Provide",
        "SubContainer",
        "SubContainerFactory",
    ]
    private static let innoDISwiftUINames: Set<String> = [
        "DIContainer",
        "DIContainerRole",
        "DIComponent",
        "DIHierarchyRoot",
        "DIFeatureRoot",
        "Input",
        "Provide",
        "SubContainer",
        "SubContainerFactory",
    ]

    private(set) var availableNames: Set<String> = []
    private(set) var conditionalImportNames: Set<String> = []
    private(set) var untrustedImportNames: Set<String> = []
    private(set) var exportedUntrustedImportNames: Set<String> = []
    private(set) var shadowedNames: Set<String> = []
    private(set) var untrustedModules: Set<String> = []
    private let topLevelImportOffsets: Set<Int>
    private let trustedModules: Set<String>

    init(topLevelImportOffsets: Set<Int>, trustedModules: Set<String>) {
        self.topLevelImportOffsets = topLevelImportOffsets
        self.trustedModules = trustedModules
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let importedNames = innoDIAttributeNames(importedBy: node)
        if importsUntrustedMacroNamespace(node) {
            if let module = node.path.first.map({ canonicalIdentifier($0.name) }) {
                untrustedModules.insert(module)
            }
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
            && !trustedModules.contains(module)
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

    // A rewritten role spells `ContainerRole.x` unqualified, so any type of
    // that name in the scanned sources would capture it.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(node.name)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(node.name)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(node.name)
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(node.name)
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(node.name)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(node.name)
    }

    private func recordTypeShadow(_ name: TokenSyntax) -> SyntaxVisitorContinueKind {
        if canonicalIdentifier(name) == "ContainerRole" {
            shadowedNames.insert("ContainerRole")
        }
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
            return ["DIContainer", "DIContainerRole"].contains { name in
                isInnoDIAttribute(
                    attribute,
                    named: name,
                    context: attributeContext
                )
            }
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

/// Rule codes a migration report lists for each changed file.
enum MigrationRule {
    /// 4.3: `@DIFeatureRoot` moves into `@SubContainer(featureRoot:)`.
    static let featureRoot = "migrate.feature-root"
    /// 5.0: the removed `concrete:` argument is dropped.
    static let concreteArgument = "migrate.concrete-argument"
    /// 6.0: legacy container options become `@DIContainerRole`.
    static let containerRole = "migrate.container-role"
    /// 6.0: `@Provide(.input)` becomes `@Input`.
    static let inputAttribute = "migrate.input-attribute"
    /// 7.0: named-root parent key paths become `\Self.member`.
    static let parentKeyPath = "migrate.parent-key-path"
    /// 7.0: a file that relied on the SwiftUI re-export imports SwiftUI.
    static let swiftUIImport = "migrate.swiftui-import"
}

final class InnoDISourceMigrationRewriter: SyntaxRewriter {
    private let path: String
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private let swiftUIImportAccess: MigrationSwiftUIImportAccess?
    private let hasOtherExplicitSwiftUIImports: Bool
    private var migratableProvideOffsets: Set<Int> = []
    private(set) var diagnostics: [MigrationDiagnostic] = []
    /// Rules whose rewrite changed this file, for the migration report.
    private(set) var appliedRules: Set<String> = []

    init(
        path: String,
        attributeContext: UnqualifiedInnoDIAttributeContext,
        swiftUIImportAccess: MigrationSwiftUIImportAccess? = nil,
        hasOtherExplicitSwiftUIImports: Bool = false
    ) {
        self.path = path
        self.attributeContext = attributeContext
        self.swiftUIImportAccess = swiftUIImportAccess
        self.hasOtherExplicitSwiftUIImports = hasOtherExplicitSwiftUIImports
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
                    message: ownershipAmbiguityMessage(
                        names: ambiguityCollector.names.sorted(),
                        untrustedModules: attributeContext.untrustedModules
                    )
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
        // The rewrites read only direct attributes, so a legacy spelling in an
        // attribute-list `#if` clause or a macro argument survives them.
        let residue = LegacyResidueCollector(attributeContext: attributeContext)
        residue.walk(rewritten)
        if diagnostics.isEmpty, !residue.forms.isEmpty {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.legacy-form-unsupported",
                    path: path,
                    message: "Cannot migrate \(residue.forms.sorted().joined(separator: ", ")) automatically where the rewrite cannot reach it, such as inside an #if clause of an attribute list or a macro argument. Migrate it manually before rerunning; no files were written."
                )
            )
        }
        let imported = addingSwiftUIImportForInnoDISwiftUI(
            to: rewritten,
            access: swiftUIImportAccess,
            hasOtherExplicitSwiftUIImports: hasOtherExplicitSwiftUIImports
        ) { message in
            diagnostics.append(MigrationDiagnostic(
                code: "migrate.swiftui-import-access-ambiguous", path: path, message: message
            ))
        }
        if imported.description != rewritten.description {
            appliedRules.insert(MigrationRule.swiftUIImport)
        }
        return imported
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> DeclSyntax {
        DeclSyntax(node)
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        ExprSyntax(node)
    }

    override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
        let visited = super.visit(node)
        guard let visitedStruct = visited.as(StructDeclSyntax.self),
              let migrated = migrateContainerDeclaration(visitedStruct) else {
            return visited
        }
        appliedRules.insert(MigrationRule.containerRole)
        return DeclSyntax(migrated)
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

        let migrated = removingAttributes(
            at: Set(featureRoots.map { $0.position.utf8Offset }),
            replacing: [subContainers[0].position.utf8Offset: migratedSubContainer],
            from: node,
            keyword: \.bindingSpecifier
        )
        appliedRules.insert(MigrationRule.featureRoot)
        return super.visit(migrated)
    }

    override func visit(_ node: AttributeSyntax) -> AttributeSyntax {
        if isInnoDIAttribute(node, named: "SubContainer", context: attributeContext)
            || isInnoDIAttribute(node, named: "SubContainerFactory", context: attributeContext) {
            let migrated = migrateParentKeyPaths(in: node)
            if migrated.description != node.description {
                appliedRules.insert(MigrationRule.parentKeyPath)
            }
            return super.visit(migrated)
        }
        guard migratableProvideOffsets.contains(node.position.utf8Offset),
              isInnoDIAttribute(
                node,
                named: "Provide",
                context: attributeContext
              ),
              let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return super.visit(node)
        }

        if isInputScope(arguments.first(where: { $0.label == nil })?.expression) {
            // An unqualified `@Input` binds to whatever `Input` the file
            // sees, so a same-named declaration would capture the rewrite.
            if node.attributeName.is(IdentifierTypeSyntax.self),
               !attributeContext.allows("Input") {
                diagnostics.append(
                    MigrationDiagnostic(
                        code: "migrate.rewrite-target-ambiguous",
                        path: path,
                        message: "Cannot rewrite @Provide(.input) to @Input, because the scanned sources or an import declare another Input. Write @InnoDI.Provide(.input) or rename that declaration before rerunning; no files were written."
                    )
                )
                return super.visit(node)
            }
            // The rewrite keeps the attribute's leading and trailing trivia,
            // so only a comment between its tokens would be lost.
            guard !containsComment(node.trimmed),
                  arguments.allSatisfy({ argument in
                    argument.label == nil
                        || canonicalIdentifier(argument.label!) == "escaping"
                  }) else {
                diagnostics.append(
                    MigrationDiagnostic(
                        code: "migrate.input-argument-unsupported",
                        path: path,
                        message: "Cannot safely rewrite a commented or non-input @Provide(.input) argument list; no files were written."
                    )
                )
                return super.visit(node)
            }
            appliedRules.insert(MigrationRule.inputAttribute)
            return super.visit(makeInputAttribute(from: node, arguments: arguments))
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
        if !containsComment(arguments),
           var last = filteredArguments.last,
           last.trailingComma != nil {
            last = last.with(\.trailingComma, nil)
            filteredArguments[filteredArguments.index(before: filteredArguments.endIndex)] = last
        }
        let filtered = LabeledExprListSyntax(filteredArguments)
        appliedRules.insert(MigrationRule.concreteArgument)
        return super.visit(
            node.with(\.arguments, .argumentList(filtered))
        )
    }

    /// 7.0 spells parent-side sub-container key paths as `\Self.member`.
    /// InnoDI always read only the member name, so replacing a named root
    /// keeps behavior unchanged. A nested component was silently reduced to
    /// its last component, so its intent cannot be recovered automatically.
    private func migrateParentKeyPaths(in attribute: AttributeSyntax) -> AttributeSyntax {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return attribute
        }
        var didChange = false
        var blocked = false
        func migrate(_ expression: ExprSyntax) -> ExprSyntax {
            guard let keyPath = expression.as(KeyPathExprSyntax.self) else {
                return expression
            }
            switch parentMemberKeyPathSpelling(expression) {
            case .canonical:
                return expression
            case .namedRoot:
                // Only the root is replaced, so only comments in its trivia
                // could be lost.
                guard let root = keyPath.root, !containsComment(root) else {
                    blocked = true
                    return expression
                }
                didChange = true
                let selfRoot = TypeSyntax(
                    IdentifierTypeSyntax(name: .keyword(.Self))
                )
                return ExprSyntax(keyPath.with(\.root, selfRoot))
            case .invalid:
                blocked = true
                return expression
            }
        }
        let rebuilt = arguments.map { argument -> LabeledExprSyntax in
            guard let array = argument.expression.as(ArrayExprSyntax.self) else {
                return argument
            }
            switch argument.label.map(canonicalIdentifier) {
            case "with":
                let elements = array.elements.map { element in
                    element.with(\.expression, migrate(element.expression))
                }
                return argument.with(
                    \.expression,
                    ExprSyntax(array.with(\.elements, ArrayElementListSyntax(elements)))
                )
            case "bindings":
                let elements = array.elements.map { element -> ArrayElementSyntax in
                    guard let tuple = element.expression.as(TupleExprSyntax.self) else {
                        return element
                    }
                    let parts = tuple.elements.map { part -> LabeledExprSyntax in
                        guard part.label.map(canonicalIdentifier) == "parent" else {
                            return part
                        }
                        return part.with(\.expression, migrate(part.expression))
                    }
                    return element.with(
                        \.expression,
                        ExprSyntax(tuple.with(\.elements, LabeledExprListSyntax(parts)))
                    )
                }
                return argument.with(
                    \.expression,
                    ExprSyntax(array.with(\.elements, ArrayElementListSyntax(elements)))
                )
            default:
                return argument
            }
        }
        if blocked {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.parent-key-path-unsupported",
                    path: path,
                    message: "Cannot safely rewrite a commented, nested, or non-member parent key path in @SubContainer or @SubContainerFactory. Spell each parent key path as \\Self.member; no files were written."
                )
            )
            return attribute
        }
        guard didChange else { return attribute }
        return attribute.with(\.arguments, .argumentList(LabeledExprListSyntax(rebuilt)))
    }

    private func migrateContainerDeclaration(
        _ node: StructDeclSyntax
    ) -> StructDeclSyntax? {
        let attributes = node.attributes.compactMap { $0.as(AttributeSyntax.self) }
        guard let container = attributes.first(where: {
            isInnoDIAttribute($0, named: "DIContainer", context: attributeContext)
        }) else {
            return nil
        }
        let componentMarkers = attributes.filter {
            isInnoDIAttribute($0, named: "DIComponent", context: attributeContext)
        }
        let rootMarkers = attributes.filter {
            isInnoDIAttribute($0, named: "DIHierarchyRoot", context: attributeContext)
        }
        guard componentMarkers.count <= 1, rootMarkers.count <= 1 else {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.container-role-duplicate",
                    path: path,
                    message: "Duplicate hierarchy markers cannot be migrated safely; no files were written."
                )
            )
            return nil
        }
        if !componentMarkers.isEmpty && !rootMarkers.isEmpty {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.container-role-conflict",
                    path: path,
                    message: "A container cannot migrate as both .component and .root; choose one role before rerunning. No files were written."
                )
            )
            return nil
        }
        // A current 6.0 container has nothing to rewrite, so comments near it,
        // such as its documentation comment, must not block the whole run.
        let hasLegacyContainerOption = (
            container.arguments?.as(LabeledExprListSyntax.self) ?? []
        ).contains {
            let label = $0.label.map(canonicalIdentifier)
            return label == "root" || label == "mainActor"
        }
        guard hasLegacyContainerOption
            || !componentMarkers.isEmpty
            || !rootMarkers.isEmpty else {
            return nil
        }
        // The container attribute keeps its surrounding trivia, so only a
        // comment between its tokens is at risk. Removed markers take their
        // attached comments with them, so any comment on them blocks.
        guard !containsComment(container.trimmed),
              !componentMarkers.contains(where: containsComment),
              !rootMarkers.contains(where: containsComment) else {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.container-option-comment",
                    path: path,
                    message: "Comments attached to legacy container role or isolation options require manual migration; no files were written."
                )
            )
            return nil
        }

        let existing = Array(container.arguments?.as(LabeledExprListSyntax.self) ?? [])
        let existingRole = existing.first(where: { $0.label == nil })
        let rootArgument = existing.first(where: {
            $0.label.map(canonicalIdentifier) == "root"
        })
        let mainActorArgument = existing.first(where: {
            $0.label.map(canonicalIdentifier) == "mainActor"
        })
        if existingRole != nil || existing.contains(where: {
            $0.label.map(canonicalIdentifier) == "isolation"
        }) {
            return nil
        }

        let rootValue = rootArgument.flatMap { booleanLiteralValue($0.expression) }
        let mainActorValue = mainActorArgument.flatMap { booleanLiteralValue($0.expression) }
        if rootArgument != nil && rootValue == nil
            || mainActorArgument != nil && mainActorValue == nil {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.container-option-nonliteral",
                    path: path,
                    message: "Only literal root: and mainActor: values can be migrated automatically; no files were written."
                )
            )
            return nil
        }

        // 5.x let a component also be a render entry point through
        // `root: true`, but a 6.0 container has exactly one role.
        if !componentMarkers.isEmpty && rootValue == true {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.container-role-conflict",
                    path: path,
                    message: "A container cannot migrate as both .component and .root; choose one role before rerunning. No files were written."
                )
            )
            return nil
        }

        let role: String?
        if !componentMarkers.isEmpty {
            role = "component"
        } else if !rootMarkers.isEmpty || rootValue == true {
            role = "root"
        } else if mainActorValue == true {
            // The role macro requires a role, and an isolated container
            // without a hierarchy marker was a local container in 5.x.
            role = "local"
        } else {
            role = nil
        }
        let needsMigration = role != nil
            || mainActorArgument != nil
            || rootArgument != nil
            || !componentMarkers.isEmpty
            || !rootMarkers.isEmpty
        guard needsMigration else { return nil }

        let moduleQualified = container.attributeName.is(MemberTypeSyntax.self)
        if role != nil, !moduleQualified,
           !attributeContext.allows("DIContainerRole")
            || attributeContext.ambiguousNames.contains("ContainerRole") {
            diagnostics.append(
                MigrationDiagnostic(
                    code: "migrate.rewrite-target-ambiguous",
                    path: path,
                    message: "Cannot rewrite legacy container options to @DIContainerRole(role: ContainerRole...), because the scanned sources or an import declare another DIContainerRole or ContainerRole. Write @InnoDI.DIContainer or rename that declaration before rerunning; no files were written."
                )
            )
            return nil
        }
        var rebuilt: [LabeledExprSyntax] = []
        if let role {
            rebuilt.append(
                LabeledExprSyntax(
                    label: .identifier("role"),
                    colon: .colonToken(trailingTrivia: .space),
                    expression: qualifiedRoleOption(
                        typeName: "ContainerRole",
                        memberName: role,
                        moduleQualified: moduleQualified
                    )
                )
            )
        }
        if mainActorValue == true {
            rebuilt.append(
                LabeledExprSyntax(
                    label: .identifier("mainActor"),
                    colon: .colonToken(trailingTrivia: .space),
                    expression: ExprSyntax(
                        BooleanLiteralExprSyntax(literal: .keyword(.true))
                    )
                )
            )
        }
        rebuilt.append(contentsOf: existing.filter { argument in
            let label = argument.label.map(canonicalIdentifier)
            return label != "root" && label != "mainActor"
        }.map { $0.with(\.leadingTrivia, []) })
        // A multi-line legacy argument list keeps one argument per line. The
        // comment guard leaves only whitespace in the first argument's trivia.
        let argumentLineTrivia = existing.first.map(\.leadingTrivia).flatMap {
            $0.contains(where: \.isNewline) ? $0 : nil
        }
        rebuilt = rebuilt.enumerated().map { index, argument in
            let isLast = index == rebuilt.index(before: rebuilt.endIndex)
            guard let argumentLineTrivia else {
                return argument.with(
                    \.trailingComma,
                    isLast ? nil : .commaToken(trailingTrivia: .space)
                )
            }
            return argument
                .with(\.leadingTrivia, argumentLineTrivia)
                .with(\.trailingComma, isLast ? nil : .commaToken())
        }

        let migratedContainer: AttributeSyntax
        if role != nil {
            // A marker-only legacy container such as `@DIComponent @DIContainer`
            // has no parentheses, and its trailing comment sits on the name.
            migratedContainer = container
                .with(\.attributeName, roleContainerAttributeName(from: container))
                .with(\.leftParen, container.leftParen ?? .leftParenToken())
                .with(\.arguments, .argumentList(LabeledExprListSyntax(rebuilt)))
                .with(\.rightParen, container.rightParen ?? .rightParenToken())
                .with(\.trailingTrivia, container.trailingTrivia)
        } else if rebuilt.isEmpty {
            // Only default-valued options such as `root: false` were left, so
            // the ordinary container keeps no argument list. The comment
            // guard allows a trailing comment, which `)` carried.
            migratedContainer = container
                .with(\.leftParen, nil)
                .with(\.arguments, nil)
                .with(\.rightParen, nil)
                .with(\.trailingTrivia, container.trailingTrivia)
        } else {
            migratedContainer = container
                .with(\.arguments, .argumentList(LabeledExprListSyntax(rebuilt)))
        }
        return removingAttributes(
            at: Set((componentMarkers + rootMarkers).map { $0.position.utf8Offset }),
            replacing: [container.position.utf8Offset: migratedContainer],
            from: node,
            keyword: \.structKeyword
        )
    }

    /// Removes the attributes at `removedOffsets` and substitutes
    /// `replacements` by offset. A removed attribute takes its line with it,
    /// so the blank lines above it move to the next kept attribute or, when
    /// it ended the list, to the first modifier or `keyword`. Callers block
    /// comments on a removed attribute, so only whitespace moves.
    private func removingAttributes<Declaration: WithAttributesSyntax & WithModifiersSyntax>(
        at removedOffsets: Set<Int>,
        replacing replacements: [Int: AttributeSyntax],
        from declaration: Declaration,
        keyword: WritableKeyPath<Declaration, TokenSyntax>
    ) -> Declaration {
        var kept: [AttributeListSyntax.Element] = []
        var removedTrivia: Trivia?
        // An attribute removed from the end of a line leaves the space that
        // separated it from the previous one.
        var removedSharedLine = false
        func trimTrailingSpaceIfLineEnds(before leadingTrivia: Trivia) {
            guard removedSharedLine, leadingTrivia.first?.isNewline == true,
                  let last = kept.indices.last else { return }
            var pieces = Array(kept[last].trailingTrivia)
            while pieces.last?.isSpaceOrTab == true {
                pieces.removeLast()
            }
            kept[last].trailingTrivia = Trivia(pieces: pieces)
        }
        for var element in declaration.attributes {
            if let attribute = element.as(AttributeSyntax.self) {
                let offset = attribute.position.utf8Offset
                if removedOffsets.contains(offset) {
                    if !attribute.leadingTrivia.contains(where: \.isNewline) {
                        removedSharedLine = true
                    }
                    removedTrivia = removedTrivia.map {
                        triviaAfterRemovedLine($0, before: attribute.leadingTrivia)
                    } ?? attribute.leadingTrivia
                    continue
                }
                if let replacement = replacements[offset] {
                    element = .attribute(replacement)
                }
            }
            if let trivia = removedTrivia {
                element.leadingTrivia = triviaAfterRemovedLine(trivia, before: element.leadingTrivia)
                removedTrivia = nil
            }
            trimTrailingSpaceIfLineEnds(before: element.leadingTrivia)
            removedSharedLine = false
            kept.append(element)
        }
        var result = declaration
        if let trivia = removedTrivia {
            if result.modifiers.isEmpty {
                result[keyPath: keyword].leadingTrivia = triviaAfterRemovedLine(
                    trivia,
                    before: result[keyPath: keyword].leadingTrivia
                )
                trimTrailingSpaceIfLineEnds(before: result[keyPath: keyword].leadingTrivia)
            } else {
                result.modifiers.leadingTrivia = triviaAfterRemovedLine(
                    trivia,
                    before: result.modifiers.leadingTrivia
                )
                trimTrailingSpaceIfLineEnds(before: result.modifiers.leadingTrivia)
            }
        }
        result.attributes = AttributeListSyntax(kept)
        return result
    }

    private func roleContainerAttributeName(
        from container: AttributeSyntax
    ) -> TypeSyntax {
        if container.attributeName.is(MemberTypeSyntax.self) {
            return TypeSyntax(
                MemberTypeSyntax(
                    baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("InnoDI"))),
                    period: .periodToken(),
                    name: .identifier("DIContainerRole")
                )
            )
        }
        return TypeSyntax(
            IdentifierTypeSyntax(name: .identifier("DIContainerRole"))
        )
    }

    private func qualifiedRoleOption(
        typeName: String,
        memberName: String,
        moduleQualified: Bool
    ) -> ExprSyntax {
        let typeReference: ExprSyntax
        if moduleQualified {
            typeReference = ExprSyntax(
                MemberAccessExprSyntax(
                    base: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .identifier("InnoDI"))
                    ),
                    declName: DeclReferenceExprSyntax(baseName: .identifier(typeName))
                )
            )
        } else {
            typeReference = ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier(typeName))
            )
        }
        return ExprSyntax(
            MemberAccessExprSyntax(
                base: typeReference,
                declName: DeclReferenceExprSyntax(baseName: .identifier(memberName))
            )
        )
    }

    private func makeInputAttribute(
        from provide: AttributeSyntax,
        arguments: LabeledExprListSyntax
    ) -> AttributeSyntax {
        let name: TypeSyntax
        if provide.attributeName.is(MemberTypeSyntax.self) {
            name = TypeSyntax(
                MemberTypeSyntax(
                    baseType: TypeSyntax(IdentifierTypeSyntax(name: .identifier("InnoDI"))),
                    period: .periodToken(),
                    name: .identifier("Input")
                )
            )
        } else {
            name = TypeSyntax(IdentifierTypeSyntax(name: .identifier("Input")))
        }
        let escaping = arguments.filter {
            $0.label.map(canonicalIdentifier) == "escaping"
        }
        // Reusing the parentheses keeps a multi-line list's closing line.
        var migrated = AttributeSyntax(
            atSign: provide.atSign,
            attributeName: name,
            leftParen: escaping.isEmpty ? nil : provide.leftParen ?? .leftParenToken(),
            arguments: escaping.isEmpty ? nil : .argumentList(escaping),
            rightParen: escaping.isEmpty ? nil : provide.rightParen ?? .rightParenToken()
        )
        migrated = migrated
            .with(\.leadingTrivia, provide.leadingTrivia)
            .with(\.trailingTrivia, provide.trailingTrivia)
        return migrated
    }

    private func isInputScope(_ expression: ExprSyntax?) -> Bool {
        guard let expression,
              let member = expression.as(MemberAccessExprSyntax.self),
              canonicalIdentifier(member.declName.baseName) == "input" else {
            return false
        }
        guard let base = member.base else { return true }
        return base.trimmedDescription == "DIScope"
            || base.trimmedDescription == "InnoDI.DIScope"
    }

    private func booleanLiteralValue(_ expression: ExprSyntax) -> Bool? {
        guard let literal = expression.as(BooleanLiteralExprSyntax.self) else {
            return nil
        }
        return literal.literal.text == "true"
    }

    private func migrateFeatureRoots(
        _ legacyAttributes: [AttributeSyntax],
        into subContainer: AttributeSyntax,
        propertyName: String
    ) -> AttributeSyntax? {
        // The kept @SubContainer attribute preserves its surrounding trivia;
        // each removed @DIFeatureRoot would drop its attached comments.
        guard !containsComment(subContainer.trimmed),
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

        // A multi-line argument list gets the new argument on its own line.
        // The comment guard leaves only whitespace in that trivia.
        var arguments = Array(existingArguments)
        let argumentLineTrivia = arguments.first.map(\.leadingTrivia).flatMap {
            $0.contains(where: \.isNewline) ? $0 : nil
        }
        if var last = arguments.last {
            if last.trailingComma == nil {
                last = last.with(
                    \.trailingComma,
                    argumentLineTrivia == nil
                        ? .commaToken(trailingTrivia: .space)
                        : .commaToken()
                )
                arguments[arguments.index(before: arguments.endIndex)] = last
            }
        }
        arguments.append(
            argumentLineTrivia.map { newArgument.with(\.leadingTrivia, $0) } ?? newArgument
        )

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

/// Legacy InnoDI spellings that survived the rewrites.
private final class LegacyResidueCollector: SyntaxVisitor {
    private let attributeContext: UnqualifiedInnoDIAttributeContext
    private(set) var forms: Set<String> = []

    init(attributeContext: UnqualifiedInnoDIAttributeContext) {
        self.attributeContext = attributeContext
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        for marker in ["DIComponent", "DIHierarchyRoot"]
        where isInnoDIAttribute(node, named: marker, context: attributeContext) {
            forms.insert("@\(marker)")
        }
        if isInnoDIAttribute(node, named: "DIContainer", context: attributeContext),
           arguments?.contains(where: {
               let label = $0.label.map(canonicalIdentifier)
               return label == "root" || label == "mainActor" || label == "isolation"
           }) == true {
            forms.insert("@DIContainer(root:mainActor:)")
        }
        if isInnoDIAttribute(node, named: "Provide", context: attributeContext),
           arguments?.first(where: { $0.label == nil }).map({
               isLegacyInputScopeExpression($0.expression)
           }) == true {
            forms.insert("@Provide(.input)")
        }
        for owner in ["SubContainer", "SubContainerFactory"]
        where isInnoDIAttribute(node, named: owner, context: attributeContext)
            && hasNonCanonicalParentKeyPath(node) {
            forms.insert("a @\(owner) parent key path")
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
        } else if name == "SubContainer" || name == "SubContainerFactory",
                  !attributeContext.allows(name),
                  hasNonCanonicalParentKeyPath(node) {
            names.insert("@\(name) parent key path")
        } else if name == "Provide",
                  !attributeContext.allows(name),
                  let arguments = node.arguments?.as(LabeledExprListSyntax.self),
                  arguments.contains(where: {
                      $0.label.map(canonicalIdentifier) == "concrete"
                  }) || arguments.first(where: { $0.label == nil }).map({
                      isLegacyInputScopeExpression($0.expression)
                  }) == true {
            if arguments.contains(where: {
                $0.label.map(canonicalIdentifier) == "concrete"
            }) {
                names.insert("@Provide(concrete:)")
            }
            if arguments.first(where: { $0.label == nil }).map({
                isLegacyInputScopeExpression($0.expression)
            }) == true {
                names.insert("@Provide(.input)")
            }
        } else if name == "DIContainer",
                  !attributeContext.allows(name),
                  let arguments = node.arguments?.as(LabeledExprListSyntax.self),
                  arguments.contains(where: {
                      let label = $0.label.map(canonicalIdentifier)
                      return label == "root" || label == "mainActor" || label == "isolation"
                  }) {
            names.insert("@DIContainer(role/isolation:)")
        } else if (name == "DIComponent" || name == "DIHierarchyRoot"),
                  !attributeContext.allows(name) {
            names.insert("@\(name)")
        }
        return .visitChildren
    }
}

private func isLegacyInputScopeExpression(_ expression: ExprSyntax) -> Bool {
    guard let member = expression.as(MemberAccessExprSyntax.self),
          canonicalIdentifier(member.declName.baseName) == "input" else {
        return false
    }
    guard let base = member.base else { return true }
    return base.trimmedDescription == "DIScope"
        || base.trimmedDescription == "InnoDI.DIScope"
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

/// Whether `with:` or a `bindings:` parent side names a root other than `Self`.
/// Whether a parent-side key path literal needs a rewrite or blocks one: a
/// named root, a nested component, or any other non-member spelling.
private func hasNonCanonicalParentKeyPath(_ attribute: AttributeSyntax) -> Bool {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return false
    }
    for argument in arguments {
        guard let array = argument.expression.as(ArrayExprSyntax.self) else { continue }
        let label = argument.label.map(canonicalIdentifier)
        for element in array.elements {
            let parents: [ExprSyntax]
            if label == "with" {
                parents = [element.expression]
            } else if label == "bindings",
                      let tuple = element.expression.as(TupleExprSyntax.self) {
                parents = tuple.elements
                    .filter { $0.label.map(canonicalIdentifier) == "parent" }
                    .map(\.expression)
            } else {
                parents = []
            }
            if parents.contains(where: { parent in
                guard parent.is(KeyPathExprSyntax.self) else { return false }
                if case .canonical = parentMemberKeyPathSpelling(parent) { return false }
                return true
            }) {
                return true
            }
        }
    }
    return false
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

/// The leading trivia left for `next` after the line of a removed token
/// whose leading trivia was `removed`: the blank lines above the removed
/// line stay, and `next` keeps its own comments and indentation. A removed
/// token that shared a line with the previous token leaves `next` unchanged.
private func triviaAfterRemovedLine(_ removed: Trivia, before next: Trivia) -> Trivia {
    guard removed.contains(where: \.isNewline) else { return next }
    var above = Array(removed)
    while above.last?.isSpaceOrTab == true {
        above.removeLast()
    }
    var below = Array(next)
    if let newline = below.firstIndex(where: \.isNewline) {
        let remaining: TriviaPiece? = switch below[newline] {
        case .newlines(let count) where count > 1: .newlines(count - 1)
        case .carriageReturns(let count) where count > 1: .carriageReturns(count - 1)
        case .carriageReturnLineFeeds(let count) where count > 1: .carriageReturnLineFeeds(count - 1)
        default: nil
        }
        below.removeSubrange(...newline)
        if let remaining {
            below.insert(remaining, at: 0)
        }
    }
    return Trivia(pieces: above + below)
}

private func containsComment(_ syntax: some SyntaxProtocol) -> Bool {
    let source = syntax.description
    return source.contains("//") || source.contains("/*")
}

/// Names the imports behind an ownership ambiguity, so the user can either
/// qualify the attributes or trust modules that declare no InnoDI names.
private func ownershipAmbiguityMessage(
    names: [String],
    untrustedModules: [String]
) -> String {
    let attributes = names.joined(separator: ", ")
    guard !untrustedModules.isEmpty else {
        return "Cannot prove that unqualified legacy attribute(s) \(attributes) belong to InnoDI. Qualify them with their module before rerunning; no files were written."
    }
    let modules = untrustedModules.joined(separator: ", ")
    return "Cannot prove that unqualified legacy attribute(s) \(attributes) belong to InnoDI, because this file imports \(modules), which could declare attributes with the same names. Qualify the attributes with InnoDI., or rerun with --trust-module <name> for each listed module that declares no InnoDI-named attribute or macro; no files were written."
}
