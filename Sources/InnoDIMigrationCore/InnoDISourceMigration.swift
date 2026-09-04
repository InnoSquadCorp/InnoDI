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

struct UnqualifiedInnoDIAttributeContext {
    let availableNames: Set<String>
    let ambiguousNames: Set<String>

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

final class InnoDISourceMigrationRewriter: SyntaxRewriter {
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

    override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
        let visited = super.visit(node)
        guard let visitedStruct = visited.as(StructDeclSyntax.self),
              let migrated = migrateContainerDeclaration(visitedStruct) else {
            return visited
        }
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

        if isInputScope(arguments.first(where: { $0.label == nil })?.expression) {
            guard !containsComment(node),
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
        guard !containsComment(container),
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

        let role: String?
        if !componentMarkers.isEmpty {
            role = "component"
        } else if !rootMarkers.isEmpty || rootValue == true {
            role = "root"
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
        rebuilt = rebuilt.enumerated().map { index, argument in
            argument.with(
                \.trailingComma,
                index == rebuilt.index(before: rebuilt.endIndex)
                    ? nil
                    : .commaToken(trailingTrivia: .space)
            )
        }

        let migratedContainer = container
            .with(\.attributeName, roleContainerAttributeName(from: container))
            .with(
            \.arguments,
            rebuilt.isEmpty ? nil : .argumentList(LabeledExprListSyntax(rebuilt))
        )
        let removedOffsets = Set(
            (componentMarkers + rootMarkers).map { $0.position.utf8Offset }
        )
        let containerOffset = container.position.utf8Offset
        var migratedAttributes: [AttributeListSyntax.Element] = []
        for element in node.attributes {
            if let attribute = element.as(AttributeSyntax.self) {
                let offset = attribute.position.utf8Offset
                if removedOffsets.contains(offset) { continue }
                if offset == containerOffset {
                    migratedAttributes.append(.attribute(migratedContainer))
                    continue
                }
            }
            migratedAttributes.append(element)
        }
        return node.with(
            \.attributes,
            AttributeListSyntax(migratedAttributes)
        )
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
        var migrated = AttributeSyntax(
            atSign: provide.atSign,
            attributeName: name,
            leftParen: escaping.isEmpty ? nil : .leftParenToken(),
            arguments: escaping.isEmpty ? nil : .argumentList(escaping),
            rightParen: escaping.isEmpty ? nil : .rightParenToken()
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
