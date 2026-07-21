//
//  DIEnvironmentBridgeConflictDetection.swift
//  InnoDIMacros
//
//  Name lookup and redeclaration checks for `@DIEnvironmentBridge`.
//

import SwiftSyntax

func environmentBridgeQualifierConflicts(
    in declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax]
) -> [DirectContainerDeclarationName] {
    let memberBodyQualifierNames: Set<String> = [
        "Swift",
        "SwiftUI",
    ]
    let scopeQualifierNames = memberBodyQualifierNames.union([
        "InnoDISwiftUI",
    ])
    let directTypeConflicts = directContainerDeclarationNames(in: declaration).filter {
        $0.namespace == .type && memberBodyQualifierNames.contains($0.name)
    }
    return directTypeConflicts + generatedQualifierScopeDeclarations(
        for: declaration,
        lexicalContext: lexicalContext,
        qualifierNames: scopeQualifierNames
    )
}

func environmentBridgeGeneratedNameConflicts(
    in declaration: some DeclGroupSyntax
) -> [DirectContainerDeclarationName] {
    var conflicts: [DirectContainerDeclarationName] = []
    for member in declaration.memberBlock.members {
        collectEnvironmentBridgeGeneratedNameConflicts(
            in: Syntax(member.decl),
            into: &conflicts
        )
    }
    return conflicts
}

/// Collects only declarations that Swift considers redeclarations of the two
/// members synthesized by `@DIEnvironmentBridge`. The modifier occupies the
/// type namespace. The helper occupies the instance-value namespace and can
/// coexist with static members and parameterized overloads.
private func collectEnvironmentBridgeGeneratedNameConflicts(
    in syntax: Syntax,
    into conflicts: inout [DirectContainerDeclarationName]
) {
    if let variable = syntax.as(VariableDeclSyntax.self) {
        let isTypeMember = hasEnvironmentBridgeTypeMemberModifier(
            variable.modifiers
        )
        for binding in variable.bindings {
            collectEnvironmentBridgeVariableConflicts(
                in: Syntax(binding.pattern),
                expectedName: isTypeMember
                    ? environmentBridgeModifierTypeName
                    : environmentBridgeHelperName,
                namespace: isTypeMember ? .type : .value,
                into: &conflicts
            )
        }
        return
    }

    if let function = syntax.as(FunctionDeclSyntax.self) {
        let isTypeMember = hasEnvironmentBridgeTypeMemberModifier(
            function.modifiers
        )
        let expectedName = isTypeMember
            ? environmentBridgeModifierTypeName
            : environmentBridgeHelperName
        guard unescapedInnoDIIdentifierName(function.name) == expectedName,
              isTypeMember
                || function.signature.parameterClause.parameters.isEmpty else {
            return
        }
        conflicts.append(
            DirectContainerDeclarationName(
                name: expectedName,
                anchor: Syntax(function.name),
                namespace: isTypeMember ? .type : .value
            )
        )
        return
    }

    if let enumCase = syntax.as(EnumCaseDeclSyntax.self) {
        for element in enumCase.elements where
            unescapedInnoDIIdentifierName(element.name)
                == environmentBridgeModifierTypeName {
            conflicts.append(
                DirectContainerDeclarationName(
                    name: environmentBridgeModifierTypeName,
                    anchor: Syntax(element.name),
                    namespace: .type
                )
            )
        }
        return
    }

    if let declaration = syntax.as(StructDeclSyntax.self) {
        appendEnvironmentBridgeModifierTypeConflict(
            declaration.name,
            to: &conflicts
        )
        return
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        appendEnvironmentBridgeModifierTypeConflict(
            declaration.name,
            to: &conflicts
        )
        return
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        appendEnvironmentBridgeModifierTypeConflict(
            declaration.name,
            to: &conflicts
        )
        return
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        appendEnvironmentBridgeModifierTypeConflict(
            declaration.name,
            to: &conflicts
        )
        return
    }
    if let declaration = syntax.as(ProtocolDeclSyntax.self) {
        appendEnvironmentBridgeModifierTypeConflict(
            declaration.name,
            to: &conflicts
        )
        return
    }
    if let declaration = syntax.as(TypeAliasDeclSyntax.self) {
        appendEnvironmentBridgeModifierTypeConflict(
            declaration.name,
            to: &conflicts
        )
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
        collectEnvironmentBridgeGeneratedNameConflicts(
            in: child,
            into: &conflicts
        )
    }
}

private func collectEnvironmentBridgeVariableConflicts(
    in syntax: Syntax,
    expectedName: String,
    namespace: DirectContainerNameNamespace,
    into conflicts: inout [DirectContainerDeclarationName]
) {
    if let identifier = syntax.as(IdentifierPatternSyntax.self) {
        guard unescapedInnoDIIdentifierName(identifier.identifier)
            == expectedName else {
            return
        }
        conflicts.append(
            DirectContainerDeclarationName(
                name: expectedName,
                anchor: Syntax(identifier.identifier),
                namespace: namespace
            )
        )
        return
    }

    for child in syntax.children(viewMode: .sourceAccurate) {
        collectEnvironmentBridgeVariableConflicts(
            in: child,
            expectedName: expectedName,
            namespace: namespace,
            into: &conflicts
        )
    }
}

private func appendEnvironmentBridgeModifierTypeConflict(
    _ token: TokenSyntax,
    to conflicts: inout [DirectContainerDeclarationName]
) {
    guard unescapedInnoDIIdentifierName(token)
        == environmentBridgeModifierTypeName else {
        return
    }
    conflicts.append(
        DirectContainerDeclarationName(
            name: environmentBridgeModifierTypeName,
            anchor: Syntax(token),
            namespace: .type
        )
    )
}

private func hasEnvironmentBridgeTypeMemberModifier(
    _ modifiers: DeclModifierListSyntax
) -> Bool {
    modifiers.contains {
        $0.name.text == "static" || $0.name.text == "class"
    }
}
