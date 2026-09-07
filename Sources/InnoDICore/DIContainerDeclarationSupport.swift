import SwiftSyntax

/// The InnoDI 6.0 declaration-shape contract shared by macro expansion,
/// build validation, and dependency-graph analysis.
package enum DIContainerDeclarationSupport: Equatable, Sendable {
    case supported
    case unsupportedKind(name: String, kind: String)
    case privateAccess(name: String)
    case generic(name: String, contextName: String?)
    case unverifiableEnclosingContext(name: String, extendedType: String)
    case localDeclaration(name: String, context: String)

    package var isSupported: Bool {
        self == .supported
    }

    package var diagnosticCode: String? {
        switch self {
        case .supported:
            return nil
        case .unsupportedKind:
            return "container.unsupported-declaration-kind"
        case .privateAccess:
            return "container.private-access-unsupported"
        case .generic:
            return "container.generic-unsupported"
        case .unverifiableEnclosingContext:
            return "container.unverifiable-enclosing-context"
        case .localDeclaration:
            return "container.local-declaration-unsupported"
        }
    }

    package var diagnosticMessage: String? {
        switch self {
        case .supported:
            return nil
        case let .unsupportedKind(name, kind):
            let article = ["actor", "enum", "extension"].contains(kind) ? "an" : "a"
            return "@DIContainer supports only non-generic structs in InnoDI 6.0; '\(name)' is declared as \(article) \(kind). Convert it to a struct and inject runtime state through @Input."
        case let .privateAccess(name):
            return "@DIContainer '\(name)' cannot be declared private in InnoDI 6.0 because generated child-mount APIs would not be accessible to sibling containers. Use fileprivate for file-local mounting, or place a default-access container inside a private enclosing namespace."
        case let .generic(name, contextName):
            let reason = if let contextName {
                "'\(name)' is nested in generic context '\(contextName)'"
            } else {
                "'\(name)' declares generic parameters"
            }
            return "@DIContainer supports only non-generic structs in InnoDI 6.0; \(reason). Move type-specific behavior behind an injected dependency."
        case let .unverifiableEnclosingContext(name, extendedType):
            return "@DIContainer cannot prove that '\(name)' has a non-generic context because it is declared inside extension '\(extendedType)'. Move the container to file scope or a non-generic nominal declaration."
        case let .localDeclaration(name, _):
            return "@DIContainer supports only file-scope structs or structs nested in non-generic nominal declarations in InnoDI 6.0; '\(name)' is declared in an executable code scope. Move the container to file scope or a non-generic nominal declaration."
        }
    }

    package var remediation: String? {
        switch self {
        case .supported:
            return nil
        case .unsupportedKind:
            return "Convert the container to a non-generic struct and inject runtime state through @Input."
        case .privateAccess:
            return "Use fileprivate for a file-local container, or nest a default-access container inside a private namespace."
        case .generic:
            return "Move the container out of the generic context and put type-specific behavior behind an injected dependency."
        case .unverifiableEnclosingContext:
            return "Move the container to file scope or nest it directly in a non-generic nominal declaration."
        case .localDeclaration:
            return "Move the container out of executable code and declare it at file scope or directly inside a non-generic nominal declaration."
        }
    }
}

/// Classifies one declaration against the InnoDI 6.0 container support
/// matrix. Physical parent syntax is authoritative; macro lexical context is
/// accepted as a fallback for detached syntax used by the compiler and tests.
package func classifyDIContainerDeclaration(
    _ declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax] = []
) -> DIContainerDeclarationSupport {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return .unsupportedKind(name: classDecl.name.text, kind: "class")
        }
        if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            return .unsupportedKind(name: actorDecl.name.text, kind: "actor")
        }
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            return .unsupportedKind(name: enumDecl.name.text, kind: "enum")
        }
        if let protocolDecl = declaration.as(ProtocolDeclSyntax.self) {
            return .unsupportedKind(name: protocolDecl.name.text, kind: "protocol")
        }
        if let extensionDecl = declaration.as(ExtensionDeclSyntax.self) {
            return .unsupportedKind(
                name: extensionDecl.extendedType.trimmedDescription,
                kind: "extension"
            )
        }

        return .unsupportedKind(name: "<unknown>", kind: "declaration")
    }

    if structDecl.modifiers.contains(where: { $0.name.text == "private" }) {
        return .privateAccess(name: structDecl.name.text)
    }

    if structDecl.genericParameterClause != nil || structDecl.genericWhereClause != nil {
        return .generic(name: structDecl.name.text, contextName: nil)
    }

    if let enclosingContext = enclosingDeclarationContext(
        startingAt: Syntax(declaration).parent
    ) ?? lexicalContext.compactMap(declarationContext(from:)).first {
        switch enclosingContext {
        case let .generic(name):
            return .generic(name: structDecl.name.text, contextName: name)
        case let .extension(extendedType):
            return .unverifiableEnclosingContext(
                name: structDecl.name.text,
                extendedType: extendedType
            )
        case let .local(context):
            return .localDeclaration(
                name: structDecl.name.text,
                context: context
            )
        }
    }

    return .supported
}

/// One unsupported declaration found during a syntax-tree scan.
package struct DIContainerDeclarationSupportIssue: Equatable {
    package let support: DIContainerDeclarationSupport
    package let attributePosition: AbsolutePosition

    package init(
        support: DIContainerDeclarationSupport,
        attributePosition: AbsolutePosition
    ) {
        self.support = support
        self.attributePosition = attributePosition
    }
}

/// Finds every unsupported `@DIContainer` declaration in one syntax tree.
/// Consumers attach their own file/module coordinates to these shared records.
package final class DIContainerDeclarationSupportCollector: SyntaxVisitor {
    package private(set) var issues: [DIContainerDeclarationSupportIssue] = []

    package override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    package override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node)
    }

    package override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node)
    }

    package override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node)
    }

    package override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node)
    }

    package override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node)
    }

    package override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node)
    }

    private func collect(_ declaration: some DeclGroupSyntax) -> SyntaxVisitorContinueKind {
        guard let attribute = findDIContainerAttribute(
            in: declaration.attributes
        ) else {
            return .visitChildren
        }

        let support = classifyDIContainerDeclaration(declaration)
        if !support.isSupported {
            issues.append(
                DIContainerDeclarationSupportIssue(
                    support: support,
                    attributePosition: attribute.positionAfterSkippingLeadingTrivia
                )
            )
        }
        return .visitChildren
    }
}

private enum EnclosingDeclarationContext {
    case generic(name: String)
    case `extension`(extendedType: String)
    case local(context: String)
}

private func enclosingDeclarationContext(startingAt syntax: Syntax?) -> EnclosingDeclarationContext? {
    var current = syntax
    while let node = current {
        if let context = declarationContext(from: node) {
            return context
        }
        current = node.parent
    }
    return nil
}

private func declarationContext(from syntax: Syntax) -> EnclosingDeclarationContext? {
    if let declaration = syntax.as(ExtensionDeclSyntax.self) {
        return .extension(extendedType: declaration.extendedType.trimmedDescription)
    }
    if syntax.is(ClosureExprSyntax.self) {
        return .local(context: "a closure")
    }
    if let accessor = syntax.as(AccessorDeclSyntax.self) {
        return .local(context: "a '\(accessor.accessorSpecifier.text)' accessor")
    }
    if syntax.is(AccessorBlockSyntax.self) {
        return .local(context: "an accessor")
    }
    if syntax.is(SwitchCaseSyntax.self) {
        return .local(context: "a switch case")
    }
    if syntax.is(VariableDeclSyntax.self) {
        // A type cannot be a direct member of a variable declaration. If a
        // variable is present in the lexical context, the type belongs to its
        // accessor or initializer expression. Macro lexical contexts can omit
        // the intermediate AccessorBlockSyntax, so this is the fail-closed
        // fallback for real compiler expansion.
        return .local(context: "an accessor or variable initializer")
    }
    if let items = syntax.as(CodeBlockItemListSyntax.self) {
        // Conditional-compilation clauses are transparent here. Their outer
        // list still tells us whether the declaration belongs to a file,
        // nominal member block, or executable scope. Dedicated #if policy is
        // enforced separately by the conditional-declaration validator.
        if items.parent?.is(IfConfigClauseSyntax.self) == true {
            return nil
        }
        if items.parent?.is(SourceFileSyntax.self) != true {
            return .local(context: localContextDescription(for: items.parent))
        }
    }
    if let codeBlock = syntax.as(CodeBlockSyntax.self) {
        return .local(context: localContextDescription(for: codeBlock.parent))
    }
    if let declaration = syntax.as(StructDeclSyntax.self),
       declaration.genericParameterClause != nil || declaration.genericWhereClause != nil {
        return .generic(name: genericContextName(declaration.name.text, declaration.genericParameterClause))
    }
    if let declaration = syntax.as(ClassDeclSyntax.self),
       declaration.genericParameterClause != nil || declaration.genericWhereClause != nil {
        return .generic(name: genericContextName(declaration.name.text, declaration.genericParameterClause))
    }
    if let declaration = syntax.as(ActorDeclSyntax.self),
       declaration.genericParameterClause != nil || declaration.genericWhereClause != nil {
        return .generic(name: genericContextName(declaration.name.text, declaration.genericParameterClause))
    }
    if let declaration = syntax.as(EnumDeclSyntax.self),
       declaration.genericParameterClause != nil || declaration.genericWhereClause != nil {
        return .generic(name: genericContextName(declaration.name.text, declaration.genericParameterClause))
    }
    if let declaration = syntax.as(FunctionDeclSyntax.self) {
        return .local(context: "function '\(declaration.name.text)'")
    }
    return nil
}

private func localContextDescription(for parent: Syntax?) -> String {
    if let codeBlock = parent?.as(CodeBlockSyntax.self) {
        return localContextDescription(for: codeBlock.parent)
    }
    if let declaration = parent?.as(FunctionDeclSyntax.self) {
        return "function '\(declaration.name.text)'"
    }
    if parent?.is(InitializerDeclSyntax.self) == true {
        return "an initializer"
    }
    if parent?.is(DeinitializerDeclSyntax.self) == true {
        return "a deinitializer"
    }
    if let accessor = parent?.as(AccessorDeclSyntax.self) {
        return "a '\(accessor.accessorSpecifier.text)' accessor"
    }
    if parent?.is(ClosureExprSyntax.self) == true {
        return "a closure"
    }
    if parent?.is(AccessorBlockSyntax.self) == true
        || parent?.is(AccessorDeclSyntax.self) == true {
        return "an accessor"
    }
    if parent?.is(SwitchCaseSyntax.self) == true {
        return "a switch case"
    }
    return "a local code scope"
}

private func genericContextName(
    _ baseName: String,
    _ genericParameterClause: GenericParameterClauseSyntax?
) -> String {
    baseName + (genericParameterClause?.trimmedDescription ?? "")
}
