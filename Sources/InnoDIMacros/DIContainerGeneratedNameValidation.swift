import InnoDICore
import SwiftSyntax

enum DirectContainerNameNamespace: Equatable {
    case value
    case type
}

struct DirectContainerDeclarationName {
    let name: String
    let anchor: Syntax
    let namespace: DirectContainerNameNamespace
    let requiresAttachedDeclarationAnchor: Bool

    init(
        name: String,
        anchor: Syntax,
        namespace: DirectContainerNameNamespace,
        requiresAttachedDeclarationAnchor: Bool = false
    ) {
        self.name = name
        self.anchor = anchor
        self.namespace = namespace
        self.requiresAttachedDeclarationAnchor = requiresAttachedDeclarationAnchor
    }
}

let reservedGeneratedMemberPrefixes = [
    "_storage_",
    "_override_",
    "_innoDI",
    "_InnoDI",
]

/// Collects names introduced directly into a container's member lookup scope.
/// Top-level conditional-compilation branches are traversed, but nested
/// declaration bodies stop at their own name so their members cannot be
/// mistaken for members of the container.
func directContainerDeclarationNames(
    in declaration: some DeclGroupSyntax
) -> [DirectContainerDeclarationName] {
    var result: [DirectContainerDeclarationName] = []
    for member in declaration.memberBlock.members {
        collectDirectContainerDeclarationNames(
            in: Syntax(member.decl),
            into: &result
        )
    }
    return result
}

func hasReservedGeneratedDeclarationName(
    in declaration: some DeclGroupSyntax
) -> Bool {
    directContainerDeclarationNames(in: declaration).contains(
        where: isReservedGeneratedDeclarationName
    )
}

func containerHasReservedGeneratedName(
    in declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax]
) -> Bool {
    hasReservedGeneratedDeclarationName(in: declaration)
        || !reservedGeneratedQualifierScopeDeclarations(
            for: declaration,
            lexicalContext: lexicalContext
        ).isEmpty
}

/// Returns declarations visible in attached-macro syntax that shadow module
/// qualifiers used by generated code. This includes target/enclosing nominal
/// names and generic parameters. SwiftSyntax deliberately strips member lists
/// from enclosing lexical contexts, so the planned full-source preflight must
/// own declarations elsewhere in those scopes.
/// Physical ancestry is authoritative; compiler-provided lexical context is
/// the fallback for detached attached-macro inputs.
func reservedGeneratedQualifierScopeDeclarations(
    for declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax]
) -> [DirectContainerDeclarationName] {
    generatedQualifierScopeDeclarations(
        for: declaration,
        lexicalContext: lexicalContext,
        qualifierNames: ["InnoDI", "Swift", "_Concurrency"]
    )
}

func generatedQualifierScopeDeclarations(
    for declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax],
    qualifierNames: Set<String>
) -> [DirectContainerDeclarationName] {
    var candidates: [DirectContainerDeclarationName] = []
    var seenNames: Set<String> = []

    func appendCandidate(
        nameToken token: TokenSyntax,
        requiresAttachedDeclarationAnchor: Bool = false
    ) {
        let name = unescapedInnoDIIdentifierName(token)
        guard qualifierNames.contains(name),
              seenNames.insert(name).inserted else {
            return
        }
        candidates.append(
            DirectContainerDeclarationName(
                name: name,
                anchor: Syntax(token),
                namespace: .type,
                requiresAttachedDeclarationAnchor: requiresAttachedDeclarationAnchor
            )
        )
    }

    func appendLookupScope(
        _ syntax: Syntax,
        requiresAttachedDeclarationAnchor: Bool = false
    ) {
        if let token = nominalDeclarationNameToken(in: syntax) {
            appendCandidate(
                nameToken: token,
                requiresAttachedDeclarationAnchor: requiresAttachedDeclarationAnchor
            )
        }
        for token in genericParameterNameTokens(in: syntax) {
            appendCandidate(
                nameToken: token,
                requiresAttachedDeclarationAnchor: requiresAttachedDeclarationAnchor
            )
        }
    }

    appendLookupScope(Syntax(declaration))
    if Syntax(declaration).parent != nil {
        var current = Syntax(declaration).parent
        while let node = current {
            appendLookupScope(node)
            current = node.parent
        }
    } else {
        for node in lexicalContext {
            appendLookupScope(
                node,
                requiresAttachedDeclarationAnchor: true
            )
        }
    }
    return candidates
}

func generatedNameDiagnosticAnchor(
    for declarationName: DirectContainerDeclarationName,
    attachedTo declaration: some DeclGroupSyntax
) -> Syntax {
    declarationName.requiresAttachedDeclarationAnchor
        ? Syntax(declaration)
        : declarationName.anchor
}

func isReservedGeneratedDeclarationName(
    _ declaration: DirectContainerDeclarationName
) -> Bool {
    declaration.name == "InnoDI"
        || (declaration.namespace == .type
            && ["Swift", "_Concurrency"].contains(declaration.name))
        || reservedGeneratedMemberPrefixes.contains { prefix in
            declaration.name.hasPrefix(prefix)
        }
}

private func collectDirectContainerDeclarationNames(
    in syntax: Syntax,
    into result: inout [DirectContainerDeclarationName]
) {
    if let variable = syntax.as(VariableDeclSyntax.self) {
        for binding in variable.bindings {
            collectDirectValueNames(
                in: Syntax(binding.pattern),
                into: &result
            )
        }
        return
    }

    if let function = syntax.as(FunctionDeclSyntax.self) {
        result.append(
            DirectContainerDeclarationName(
                name: unescapedInnoDIIdentifierName(function.name),
                anchor: Syntax(function.name),
                namespace: .value
            )
        )
        return
    }

    if let declaration = syntax.as(StructDeclSyntax.self) {
        appendDirectTypeName(declaration.name, to: &result)
        return
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        appendDirectTypeName(declaration.name, to: &result)
        return
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        appendDirectTypeName(declaration.name, to: &result)
        return
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        appendDirectTypeName(declaration.name, to: &result)
        return
    }
    if let declaration = syntax.as(ProtocolDeclSyntax.self) {
        appendDirectTypeName(declaration.name, to: &result)
        return
    }
    if let declaration = syntax.as(TypeAliasDeclSyntax.self) {
        appendDirectTypeName(declaration.name, to: &result)
        return
    }

    guard syntax.is(IfConfigDeclSyntax.self)
        || syntax.is(IfConfigClauseListSyntax.self)
        || syntax.is(IfConfigClauseSyntax.self)
        || syntax.is(MemberBlockItemSyntax.self)
        || syntax.is(MemberBlockItemListSyntax.self) else {
        return
    }
    for child in syntax.children(viewMode: .sourceAccurate) {
        collectDirectContainerDeclarationNames(in: child, into: &result)
    }
}

private func collectDirectValueNames(
    in syntax: Syntax,
    into result: inout [DirectContainerDeclarationName]
) {
    if let identifier = syntax.as(IdentifierPatternSyntax.self) {
        result.append(
            DirectContainerDeclarationName(
                name: unescapedInnoDIIdentifierName(identifier.identifier),
                anchor: Syntax(identifier.identifier),
                namespace: .value
            )
        )
        return
    }

    for child in syntax.children(viewMode: .sourceAccurate) {
        collectDirectValueNames(in: child, into: &result)
    }
}

private func appendDirectTypeName(
    _ token: TokenSyntax,
    to result: inout [DirectContainerDeclarationName]
) {
    result.append(
        DirectContainerDeclarationName(
            name: unescapedInnoDIIdentifierName(token),
            anchor: Syntax(token),
            namespace: .type
        )
    )
}

func nominalDeclarationNameToken(in syntax: Syntax) -> TokenSyntax? {
    if let declaration = syntax.as(StructDeclSyntax.self) {
        return declaration.name
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        return declaration.name
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        return declaration.name
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        return declaration.name
    }
    if let declaration = syntax.as(ProtocolDeclSyntax.self) {
        return declaration.name
    }
    return nil
}

func genericParameterNameTokens(in syntax: Syntax) -> [TokenSyntax] {
    if let declaration = syntax.as(StructDeclSyntax.self) {
        return declaration.genericParameterClause?.parameters.map(\.name) ?? []
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        return declaration.genericParameterClause?.parameters.map(\.name) ?? []
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        return declaration.genericParameterClause?.parameters.map(\.name) ?? []
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        return declaration.genericParameterClause?.parameters.map(\.name) ?? []
    }
    return []
}

func isDeclarationInExtensionLookupScope(
    _ declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax]
) -> Bool {
    if Syntax(declaration).is(ExtensionDeclSyntax.self) {
        return true
    }
    if Syntax(declaration).parent != nil {
        var current = Syntax(declaration).parent
        while let node = current {
            if node.is(ExtensionDeclSyntax.self) {
                return true
            }
            current = node.parent
        }
        return false
    }
    return lexicalContext.contains { $0.is(ExtensionDeclSyntax.self) }
}
