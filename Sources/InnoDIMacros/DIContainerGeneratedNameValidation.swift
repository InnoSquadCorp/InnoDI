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

enum ManagedGeneratedSymbolShape {
    case provide(scope: ProvideScope, isAsync: Bool)
    case subContainer(scope: SubContainerScopeValue)

    func symbolNames(for memberName: String) -> [String] {
        switch self {
        case .provide(.input, _):
            return ["_storage_\(memberName)"]
        case .provide(.shared, true):
            return ["_storage_task_\(memberName)"]
        case .provide(.shared, false):
            return ["_storage_\(memberName)"]
        case .provide(.transient, _):
            return ["_override_\(memberName)"]
        case .subContainer(.shared):
            return [
                "_storage_sub_\(memberName)",
                "_override_sub_\(memberName)",
                "_override_sub_apply_\(memberName)",
            ]
        case .subContainer(.transient):
            return [
                "_override_sub_\(memberName)",
                "_override_sub_apply_\(memberName)",
                "_innoDISubBuild_\(memberName)",
            ]
        }
    }
}

struct DIContainerGeneratedSymbolCollision {
    let generatedName: String
    let firstMemberName: String
    let firstAnchor: Syntax
    let conflictingMemberName: String
    let conflictingAnchor: Syntax
}

private struct ManagedGeneratedSymbolSource {
    let memberName: String
    let shape: ManagedGeneratedSymbolShape
    let sourceOrder: Int
    let anchor: Syntax
}

private struct ManagedGeneratedSymbolClaim {
    let generatedName: String
    let memberName: String
    let sourceOrder: Int
    let claimOrdinal: Int
    let anchor: Syntax
}

func generatedPeerSymbolCollisions(
    in model: DIContainerExpansionModel
) -> [DIContainerGeneratedSymbolCollision] {
    let provideSources = model.members
        .filter(\.hasLocallyValidConstructionConfiguration)
        .map { member in
            ManagedGeneratedSymbolSource(
                memberName: member.name,
                shape: .provide(
                    scope: member.scope,
                    isAsync: member.isAsyncFactory
                ),
                sourceOrder: member.sourceOrder,
                anchor: managedMemberNameAnchor(member.bindingSyntax)
            )
        }
    let subContainerSources = model.subContainerMembers
        .filter(\.hasLocallyValidGeneratedPeerConfiguration)
        .compactMap { member -> ManagedGeneratedSymbolSource? in
            guard let scope = member.scope else { return nil }
            return ManagedGeneratedSymbolSource(
                memberName: member.name,
                shape: .subContainer(scope: scope),
                sourceOrder: member.sourceOrder,
                anchor: managedMemberNameAnchor(member.bindingSyntax)
            )
        }
    return generatedPeerSymbolCollisions(
        sources: provideSources + subContainerSources
    )
}

func hasGeneratedPeerSymbolCollision(
    in declaration: some DeclGroupSyntax
) -> Bool {
    hasGeneratedPeerSymbolCollision(
        sources: rawManagedGeneratedSymbolSources(in: declaration)
    )
}

private func hasGeneratedPeerSymbolCollision(
    sources: [ManagedGeneratedSymbolSource]
) -> Bool {
    let memberNameCounts = Dictionary(
        sources.map { ($0.memberName, 1) },
        uniquingKeysWith: +
    )
    var claimedGeneratedNames = Set<String>()
    for source in sources where memberNameCounts[source.memberName] == 1 {
        for generatedName in source.shape.symbolNames(for: source.memberName) {
            guard claimedGeneratedNames.insert(generatedName).inserted else {
                return true
            }
        }
    }
    return false
}

private func generatedPeerSymbolCollisions(
    sources: [ManagedGeneratedSymbolSource]
) -> [DIContainerGeneratedSymbolCollision] {
    let duplicateMemberNames = Set(
        Dictionary(grouping: sources, by: \.memberName)
            .filter { $0.value.count > 1 }
            .map(\.key)
    )
    let claims = sources
        .filter { !duplicateMemberNames.contains($0.memberName) }
        .flatMap { source in
            source.shape.symbolNames(for: source.memberName)
                .enumerated()
                .map { ordinal, generatedName in
                    ManagedGeneratedSymbolClaim(
                        generatedName: generatedName,
                        memberName: source.memberName,
                        sourceOrder: source.sourceOrder,
                        claimOrdinal: ordinal,
                        anchor: source.anchor
                    )
                }
        }
        .sorted {
            if $0.sourceOrder != $1.sourceOrder {
                return $0.sourceOrder < $1.sourceOrder
            }
            return $0.claimOrdinal < $1.claimOrdinal
        }

    var firstClaimByGeneratedName: [String: ManagedGeneratedSymbolClaim] = [:]
    var collisions: [DIContainerGeneratedSymbolCollision] = []
    for claim in claims {
        guard let first = firstClaimByGeneratedName[claim.generatedName] else {
            firstClaimByGeneratedName[claim.generatedName] = claim
            continue
        }
        collisions.append(
            DIContainerGeneratedSymbolCollision(
                generatedName: claim.generatedName,
                firstMemberName: first.memberName,
                firstAnchor: first.anchor,
                conflictingMemberName: claim.memberName,
                conflictingAnchor: claim.anchor
            )
        )
    }
    return collisions
}

private func rawManagedGeneratedSymbolSources(
    in declaration: some DeclGroupSyntax
) -> [ManagedGeneratedSymbolSource] {
    declaration.memberBlock.members.enumerated().compactMap {
        sourceOrder,
        member -> ManagedGeneratedSymbolSource? in
        guard let variable = member.decl.as(VariableDeclSyntax.self),
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              !isEscapedInnoDIIdentifier(identifier.identifier),
              binding.typeAnnotation != nil else {
            return nil
        }

        let provideAttributes = findInnoDIAttributes(
            named: "Provide",
            in: variable.attributes
        )
        let subContainerAttributes = findInnoDIAttributes(
            named: "SubContainer",
            in: variable.attributes
        )
        let memberName = unescapedInnoDIIdentifierName(identifier.identifier)
        let anchor = Syntax(identifier.identifier)

        if provideAttributes.count == 1,
           subContainerAttributes.isEmpty,
           isSupportedProvideStoredProperty(variable) {
            let arguments = parseProvideArguments(provideAttributes[0])
            guard let scope = arguments.scope,
                  isLocallyValidProvideConfiguration(
                    declaration: variable,
                    arguments: arguments
                  ) else {
                return nil
            }
            return ManagedGeneratedSymbolSource(
                memberName: memberName,
                shape: .provide(
                    scope: scope,
                    isAsync: arguments.asyncFactoryExpr != nil
                ),
                sourceOrder: sourceOrder,
                anchor: anchor
            )
        }

        if subContainerAttributes.count == 1,
           provideAttributes.isEmpty,
           isSupportedSubContainerStoredProperty(variable) {
            let arguments = parseSubContainerArguments(
                subContainerAttributes[0]
            )
            guard let scope = arguments.scope,
                  !arguments.bindingsParseState.isInvalid,
                  !isInvalidSameNameWiring(arguments.sameNameWiring),
                  !(arguments.hasWithDependencies
                    && arguments.bindingsParseState.hasArgument) else {
                return nil
            }
            return ManagedGeneratedSymbolSource(
                memberName: memberName,
                shape: .subContainer(scope: scope),
                sourceOrder: sourceOrder,
                anchor: anchor
            )
        }

        return nil
    }
}

private func isInvalidSameNameWiring(
    _ state: SubContainerSameNameWiringParseState
) -> Bool {
    if case .invalid = state {
        return true
    }
    return false
}

private func managedMemberNameAnchor(
    _ binding: PatternBindingSyntax
) -> Syntax {
    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
        return Syntax(identifier.identifier)
    }
    return Syntax(binding.pattern)
}

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
