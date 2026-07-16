//
//  DIEnvironmentBridgeMacro.swift
//  InnoDIMacros
//
//  `@DIEnvironmentBridge` drives SwiftUI environment wiring: a container
//  type declares member → environment key-path mappings, and the macro
//  synthesizes a `ViewModifier` that reads those members and injects them
//  into the SwiftUI environment. This file holds the macro conformances
//  (member + extension) plus the validation and codegen helpers specific
//  to the bridge.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DIEnvironmentBridgeMacro {}

private let environmentBridgeModifierTypeName = "_InnoDIEnvironmentBridgeModifier"
private let environmentBridgeHelperName = "_innoDIEnvironmentBridgeModifier"

extension DIEnvironmentBridgeMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard isSupportedDIContainerDeclarationIfPresent(declaration, in: context) else {
            return []
        }

        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: true
        )
        guard let mappings = validation.mappings else {
            return []
        }

        guard let nominalType = nominalTypeSyntax(for: declaration) else {
            return []
        }

        let accessLevel = environmentBridgeAccessLevelModifiers(
            for: declaration.modifiers
        )
        let declarationSyntax = Syntax(declaration)
        let targetName = nominalDeclarationNameToken(
            in: declarationSyntax
        ).map(unescapedInnoDIIdentifierName)
        let targetLookupShadowsModifierType = targetName
            == environmentBridgeModifierTypeName
            || genericParameterNameTokens(in: declarationSyntax).contains {
                unescapedInnoDIIdentifierName($0)
                    == environmentBridgeModifierTypeName
            }
        let nestedTypeShadowsTarget = targetName.map { targetName in
            directContainerDeclarationNames(in: declaration).contains {
                $0.namespace == .type && $0.name == targetName
            }
        } ?? false
        let visibleGenericParameterNames =
            environmentBridgeVisibleGenericParameterNames(
                for: declaration,
                lexicalContext: context.lexicalContext
            )
        let visibleGenericShadowsTarget = targetName.map(
            visibleGenericParameterNames.contains
        ) ?? false
        let requiresShadowSafeStorage = targetLookupShadowsModifierType
            || nestedTypeShadowsTarget
            || visibleGenericShadowsTarget
        let shadowSafeTypeNames = makeEnvironmentBridgeShadowSafeTypeNames(
            mappingCount: mappings.count,
            excluding: visibleGenericParameterNames
        )
        let modifierDecl = requiresShadowSafeStorage
            ? makeShadowSafeEnvironmentBridgeModifierDecl(
                accessLevel: accessLevel,
                typeNames: shadowSafeTypeNames
            )
            : makeEnvironmentBridgeModifierDecl(
                accessLevel: accessLevel,
                containerType: nominalType,
                mappings: mappings
            )
        let bridgeMethodDecl = requiresShadowSafeStorage
            ? makeShadowSafeEnvironmentBridgeHelperDecl(
                accessLevel: accessLevel,
                mappings: mappings
            )
            : makeEnvironmentBridgeHelperDecl(accessLevel: accessLevel)

        return [DeclSyntax(modifierDecl), DeclSyntax(bridgeMethodDecl)]
    }
}

extension DIEnvironmentBridgeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard isSupportedDIContainerDeclarationIfPresent(declaration, in: context) else {
            return []
        }

        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: false
        )
        guard validation.mappings != nil else {
            return []
        }

        return [
            try ExtensionDeclSyntax(
                "extension \(type): InnoDISwiftUI.DIEnvironmentBridging {}"
            )
        ]
    }
}

// MARK: - Validation model

private struct EnvironmentBridgeMappingInfo {
    let memberName: String
    let environmentKeyPath: KeyPathExprSyntax
}

private struct EnvironmentBridgeValidationResult {
    let mappings: [EnvironmentBridgeMappingInfo]?
}

private struct EnvironmentBridgeContainerMemberInfo {
    let name: String
    let isAsyncProvide: Bool
}

private struct EnvironmentBridgeShadowSafeTypeNames {
    let container: String
    let values: [String]
}

private func validateEnvironmentBridge(
    attribute: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext,
    emitDiagnostics: Bool
) -> EnvironmentBridgeValidationResult {
    if isDeclarationInExtensionLookupScope(
        declaration,
        lexicalContext: context.lexicalContext
    ) {
        if emitDiagnostics {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic
                        .swiftUIEnvironmentBridgeExtensionContextUnsupported()
                )
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    if let unsupported = unsupportedEnvironmentBridgeDeclaration(
        declaration
    ) {
        if emitDiagnostics {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic
                        .swiftUIEnvironmentBridgeUnsupportedDeclarationKind(
                            name: unsupported.name,
                            kind: unsupported.kind
                        )
                )
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    if let privateLookupComponent = privateNestedEnvironmentBridgeLookupComponent(
        declaration,
        lexicalContext: context.lexicalContext
    ) {
        if emitDiagnostics {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic
                        .swiftUIEnvironmentBridgePrivateNestedTarget(
                            name: privateLookupComponent
                        )
                )
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    if environmentBridgeHasParameterPack(declaration) {
        if emitDiagnostics {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic
                        .swiftUIEnvironmentBridgeParameterPackUnsupported()
                )
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    let qualifierConflicts = environmentBridgeQualifierConflicts(
        in: declaration,
        lexicalContext: context.lexicalContext
    )
    let isContainer = findInnoDIAttribute(
        named: "DIContainer",
        in: declaration.attributes
    ) != nil
    let hasCoreContainerConflict = isContainer
        && containerHasReservedGeneratedName(
            in: declaration,
            lexicalContext: context.lexicalContext
        )
    let bridgeOwnedConflicts = isContainer
        ? qualifierConflicts.filter {
            $0.name == "SwiftUI" || $0.name == "InnoDISwiftUI"
        }
        : qualifierConflicts
    let generatedNameConflicts = environmentBridgeGeneratedNameConflicts(
        in: declaration
    )
    let bridgeOwnedGeneratedNameConflicts = hasCoreContainerConflict
        ? []
        : generatedNameConflicts
    if emitDiagnostics {
        for conflict in bridgeOwnedConflicts {
            context.diagnose(
                Diagnostic(
                    node: generatedNameDiagnosticAnchor(
                        for: conflict,
                        attachedTo: declaration
                    ),
                    message: SimpleDiagnostic.swiftUIEnvironmentBridgeReservedModuleName(
                        declarationName: conflict.name
                    )
                )
            )
        }
        for conflict in bridgeOwnedGeneratedNameConflicts {
            let message = conflict.name == environmentBridgeModifierTypeName
                ? SimpleDiagnostic.swiftUIEnvironmentBridgeGeneratedModifierTypeNameConflict(
                    memberName: conflict.name
                )
                : SimpleDiagnostic.swiftUIEnvironmentBridgeGeneratedHelperNameConflict(
                    memberName: conflict.name
                )
            context.diagnose(
                Diagnostic(
                    node: conflict.anchor,
                    message: message
                )
            )
        }
    }
    if hasCoreContainerConflict
        || !qualifierConflicts.isEmpty
        || !generatedNameConflicts.isEmpty {
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let firstArgument = arguments.first,
          let arrayExpr = firstArgument.expression.as(ArrayExprSyntax.self) else {
        if emitDiagnostics {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidArguments()
                )
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    var membersByName: [String: EnvironmentBridgeContainerMemberInfo] = [:]
    for memberInfo in containerMemberInfos(in: declaration) {
        membersByName[memberInfo.name] = memberInfo
    }
    var seenMembers: Set<String> = []
    var mappings: [EnvironmentBridgeMappingInfo] = []
    var hadErrors = false

    for element in arrayExpr.elements {
        guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member")
                    )
                )
            }
            hadErrors = true
            continue
        }

        var memberName: String?
        var environmentKeyPath: KeyPathExprSyntax?

        for tupleElement in tupleExpr.elements {
            guard let label = tupleElement.label?.text else {
                continue
            }

            switch label {
            case "member":
                guard let parsedMemberName = stringLiteralValue(tupleElement.expression) else {
                    if emitDiagnostics {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(tupleElement.expression),
                                message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member")
                            )
                        )
                    }
                    hadErrors = true
                    continue
                }
                memberName = parsedMemberName
            case "environment":
                guard let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self) else {
                    if emitDiagnostics {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(tupleElement.expression),
                                message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "environment")
                            )
                        )
                    }
                    hadErrors = true
                    continue
                }
                guard let canonicalKeyPath = canonicalEnvironmentBridgeKeyPath(
                    keyPath
                ) else {
                    if emitDiagnostics {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(tupleElement.expression),
                                message: SimpleDiagnostic
                                    .swiftUIEnvironmentBridgeInvalidEnvironmentKeyPath()
                            )
                        )
                    }
                    hadErrors = true
                    continue
                }
                environmentKeyPath = canonicalKeyPath
            default:
                continue
            }
        }

        guard let memberName, let environmentKeyPath else {
            hadErrors = true
            continue
        }

        guard let memberInfo = membersByName[memberName] else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeUnknownMember(memberName: memberName)
                    )
                )
            }
            hadErrors = true
            continue
        }

        if memberInfo.isAsyncProvide {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeAsyncMember(memberName: memberName)
                    )
                )
            }
            hadErrors = true
            continue
        }

        guard seenMembers.insert(memberName).inserted else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeDuplicateMember(memberName: memberName)
                    )
                )
            }
            hadErrors = true
            continue
        }

        mappings.append(
            EnvironmentBridgeMappingInfo(
                memberName: memberName,
                environmentKeyPath: environmentKeyPath
            )
        )
    }

    return EnvironmentBridgeValidationResult(mappings: hadErrors ? nil : mappings)
}

private func unsupportedEnvironmentBridgeDeclaration(
    _ declaration: some DeclGroupSyntax
) -> (name: String, kind: String)? {
    if declaration.is(StructDeclSyntax.self)
        || declaration.is(ClassDeclSyntax.self)
        || declaration.is(EnumDeclSyntax.self) {
        return nil
    }
    if let actor = declaration.as(ActorDeclSyntax.self) {
        return (actor.name.text, "an actor")
    }
    if let protocolDecl = declaration.as(ProtocolDeclSyntax.self) {
        return (protocolDecl.name.text, "a protocol")
    }
    return ("<unknown>", "an unsupported declaration")
}

private func privateNestedEnvironmentBridgeLookupComponent(
    _ declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax]
) -> String? {
    var lookupComponents = [Syntax(declaration)]
    if Syntax(declaration).parent != nil {
        var current = Syntax(declaration).parent
        while let node = current {
            if nominalDeclarationNameToken(in: node) != nil {
                lookupComponents.append(node)
            }
            current = node.parent
        }
    } else {
        lookupComponents.append(
            contentsOf: lexicalContext.filter {
                nominalDeclarationNameToken(in: $0) != nil
            }
        )
    }

    guard lookupComponents.count > 1 else {
        return nil
    }
    for component in lookupComponents.dropLast() {
        guard nominalDeclarationModifiers(in: component)?.contains(where: {
            $0.name.tokenKind == .keyword(.private)
        }) == true else {
            continue
        }
        return nominalDeclarationNameToken(in: component).map(
            unescapedInnoDIIdentifierName
        )
    }
    return nil
}

private func nominalDeclarationModifiers(
    in syntax: Syntax
) -> DeclModifierListSyntax? {
    if let declaration = syntax.as(StructDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = syntax.as(ProtocolDeclSyntax.self) {
        return declaration.modifiers
    }
    return nil
}

private func environmentBridgeQualifierConflicts(
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

private func canonicalEnvironmentBridgeKeyPath(
    _ keyPath: KeyPathExprSyntax
) -> KeyPathExprSyntax? {
    guard !Syntax(keyPath).hasError,
          let root = keyPath.root?.as(IdentifierTypeSyntax.self),
          root.genericArgumentClause == nil else {
        return nil
    }

    let propertyComponent: KeyPathComponentSyntax
    switch root.name.text {
    case "EnvironmentValues":
        guard keyPath.components.count == 1,
              let component = keyPath.components.first,
              directEnvironmentBridgeProperty(in: component) != nil else {
            return nil
        }
        propertyComponent = component
    case "SwiftUI":
        guard keyPath.components.count == 2,
              let environmentValuesComponent = keyPath.components.first,
              directEnvironmentBridgeProperty(
                in: environmentValuesComponent
              )?.declName.baseName.text == "EnvironmentValues",
              let component = keyPath.components.last,
              directEnvironmentBridgeProperty(in: component) != nil else {
            return nil
        }
        propertyComponent = component
    default:
        return nil
    }

    var canonical = keyPath
    canonical.root = TypeSyntax(
        MemberTypeSyntax(
            baseType: IdentifierTypeSyntax(name: .identifier("SwiftUI")),
            name: .identifier("EnvironmentValues")
        )
    )
    canonical.components = KeyPathComponentListSyntax([propertyComponent])
    return canonical
}

private func directEnvironmentBridgeProperty(
    in component: KeyPathComponentSyntax
) -> KeyPathPropertyComponentSyntax? {
    guard component.period != nil,
          let property = component.component.as(
            KeyPathPropertyComponentSyntax.self
          ),
          property.genericArgumentClause == nil,
          property.declName.moduleSelector == nil,
          property.declName.argumentNames == nil,
          case .identifier = property.declName.baseName.tokenKind else {
        return nil
    }
    return property
}

private func environmentBridgeGeneratedNameConflicts(
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

private func environmentBridgeAccessLevelModifiers(
    for modifiers: DeclModifierListSyntax?
) -> DeclModifierListSyntax {
    guard modifiers?.contains(where: {
        $0.name.tokenKind == .keyword(.private)
    }) == true else {
        return accessLevelModifiers(for: modifiers)
    }
    return DeclModifierListSyntax([
        DeclModifierSyntax(name: .keyword(.fileprivate))
    ])
}

private func environmentBridgeVisibleGenericParameterNames(
    for declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax]
) -> Set<String> {
    var names: Set<String> = []

    func collect(from syntax: Syntax) {
        names.formUnion(
            genericParameterNameTokens(in: syntax).map(
                unescapedInnoDIIdentifierName
            )
        )
    }

    collect(from: Syntax(declaration))
    if Syntax(declaration).parent != nil {
        var current = Syntax(declaration).parent
        while let node = current {
            collect(from: node)
            current = node.parent
        }
    } else {
        for node in lexicalContext {
            collect(from: node)
        }
    }
    return names
}

private func environmentBridgeHasParameterPack(
    _ declaration: some DeclGroupSyntax
) -> Bool {
    let parameters: GenericParameterListSyntax?
    if let declaration = declaration.as(StructDeclSyntax.self) {
        parameters = declaration.genericParameterClause?.parameters
    } else if let declaration = declaration.as(ClassDeclSyntax.self) {
        parameters = declaration.genericParameterClause?.parameters
    } else if let declaration = declaration.as(EnumDeclSyntax.self) {
        parameters = declaration.genericParameterClause?.parameters
    } else {
        parameters = nil
    }
    return parameters?.contains(where: {
        $0.specifier?.tokenKind == .keyword(.each)
    }) == true
}

private func containerMemberInfos(in declaration: some DeclGroupSyntax) -> [EnvironmentBridgeContainerMemberInfo] {
    declaration.memberBlock.members.flatMap { member -> [EnvironmentBridgeContainerMemberInfo] in
        guard let variableDecl = member.decl.as(VariableDeclSyntax.self) else {
            return []
        }
        guard !variableDecl.modifiers.contains(where: {
            $0.name.text == "static" || $0.name.text == "class"
        }) else {
            return []
        }

        let provideAttribute = findAttribute(
            named: "Provide",
            allowingQualifiedModules: ["InnoDI"],
            in: variableDecl.attributes
        )
        let isAsyncProvide = provideAttribute.map { parseProvideArguments($0).asyncFactoryExpr != nil } ?? false

        return variableDecl.bindings.compactMap { binding -> EnvironmentBridgeContainerMemberInfo? in
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                return nil
            }
            return EnvironmentBridgeContainerMemberInfo(name: name, isAsyncProvide: isAsyncProvide)
        }
    }
}

// MARK: - Code generation

private func makeEnvironmentBridgeModifierDecl(
    accessLevel: DeclModifierListSyntax,
    containerType: TypeSyntax,
    mappings: [EnvironmentBridgeMappingInfo]
) -> StructDeclSyntax {
    let containerDecl = VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
                typeAnnotation: TypeAnnotationSyntax(type: containerType)
            )
        ])
    )
    let bodyDecl = FunctionDeclSyntax(
        modifiers: accessLevel,
        name: .identifier("body"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(
                parameters: FunctionParameterListSyntax([
                    FunctionParameterSyntax(
                        firstName: .identifier("content"),
                        colon: .colonToken(),
                        type: TypeSyntax(stringLiteral: "Self.Content")
                    )
                ])
            ),
            returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "some SwiftUI.View"))
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ExpressionStmtSyntax(
                                expression: makeEnvironmentBridgeBodyExpr(mappings: mappings)
                            )
                        )
                    )
                )
            ])
        )
    )

    return StructDeclSyntax(
        modifiers: accessLevel,
        name: .identifier(environmentBridgeModifierTypeName),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "SwiftUI.ViewModifier"))
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax([
                MemberBlockItemSyntax(decl: DeclSyntax(containerDecl)),
                MemberBlockItemSyntax(decl: DeclSyntax(bodyDecl)),
            ])
        )
    )
}

/// A bridge target or one of its generic parameters may legally have the same
/// name as its generated nested modifier. In that case unqualified generated
/// type references resolve to the source binder instead of the nested type.
/// Generic container/value storage plus key paths preserves normal deferred
/// member reads without spelling the shadowed target type in nested storage.
private func makeShadowSafeEnvironmentBridgeModifierDecl(
    accessLevel: DeclModifierListSyntax,
    typeNames: EnvironmentBridgeShadowSafeTypeNames
) -> StructDeclSyntax {
    let genericParameterNames = [typeNames.container] + typeNames.values
    let genericParameterClause = GenericParameterClauseSyntax(
        leftAngle: .leftAngleToken(),
        parameters: GenericParameterListSyntax(
            genericParameterNames.enumerated().map { index, name in
                GenericParameterSyntax(
                    name: .identifier(name),
                    trailingComma: index == genericParameterNames.count - 1
                        ? nil
                        : .commaToken()
                )
            }
        ),
        rightAngle: .rightAngleToken()
    )

    var members: [MemberBlockItemSyntax] = [
        MemberBlockItemSyntax(
            decl: DeclSyntax(
                makeEnvironmentBridgeStoredProperty(
                    name: "container",
                    type: TypeSyntax(
                        IdentifierTypeSyntax(
                            name: .identifier(typeNames.container)
                        )
                    )
                )
            )
        )
    ]
    for index in typeNames.values.indices {
        let valueTypeName = typeNames.values[index]
        members.append(
            MemberBlockItemSyntax(
                decl: DeclSyntax(
                    makeEnvironmentBridgeStoredProperty(
                        name: "member\(index)",
                        type: TypeSyntax(
                            stringLiteral: "Swift.KeyPath<\(typeNames.container), \(valueTypeName)>"
                        )
                    )
                )
            )
        )
        members.append(
            MemberBlockItemSyntax(
                decl: DeclSyntax(
                    makeEnvironmentBridgeStoredProperty(
                        name: "environment\(index)",
                        type: TypeSyntax(
                            stringLiteral: "Swift.WritableKeyPath<SwiftUI.EnvironmentValues, \(valueTypeName)>"
                        )
                    )
                )
            )
        )
    }

    let bodyDecl = FunctionDeclSyntax(
        modifiers: accessLevel,
        name: .identifier("body"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(
                parameters: FunctionParameterListSyntax([
                    FunctionParameterSyntax(
                        firstName: .identifier("content"),
                        colon: .colonToken(),
                        type: TypeSyntax(stringLiteral: "Self.Content")
                    )
                ])
            ),
            returnClause: ReturnClauseSyntax(
                type: TypeSyntax(stringLiteral: "some SwiftUI.View")
            )
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ExpressionStmtSyntax(
                                expression: makeShadowSafeEnvironmentBridgeBodyExpr(
                                    mappingCount: typeNames.values.count
                                )
                            )
                        )
                    )
                )
            ])
        )
    )
    members.append(MemberBlockItemSyntax(decl: DeclSyntax(bodyDecl)))

    return StructDeclSyntax(
        modifiers: accessLevel,
        name: .identifier(environmentBridgeModifierTypeName),
        genericParameterClause: genericParameterClause,
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(stringLiteral: "SwiftUI.ViewModifier")
                )
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax(members)
        )
    )
}

private func makeEnvironmentBridgeShadowSafeTypeNames(
    mappingCount: Int,
    excluding visibleGenericParameterNames: Set<String>
) -> EnvironmentBridgeShadowSafeTypeNames {
    var usedNames = visibleGenericParameterNames

    func allocate(_ base: String) -> String {
        var candidate = base
        var suffix = 0
        while usedNames.contains(candidate) {
            suffix += 1
            candidate = "\(base)_\(suffix)"
        }
        usedNames.insert(candidate)
        return candidate
    }

    return EnvironmentBridgeShadowSafeTypeNames(
        container: allocate("_InnoDIContainer"),
        values: (0..<mappingCount).map { index in
            allocate("_InnoDIValue\(index)")
        }
    )
}

private func makeEnvironmentBridgeStoredProperty(
    name: String,
    type: TypeSyntax
) -> VariableDeclSyntax {
    VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(type: type)
            )
        ])
    )
}

private func makeEnvironmentBridgeHelperDecl(
    accessLevel: DeclModifierListSyntax
) -> FunctionDeclSyntax {
    let modifierType = TypeSyntax(
        IdentifierTypeSyntax(name: .identifier(environmentBridgeModifierTypeName))
    )
    let callExpr = ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: ExprSyntax(
                MemberAccessExprSyntax(
                    base: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .keyword(.Self))
                    ),
                    declName: DeclReferenceExprSyntax(
                        baseName: .identifier(environmentBridgeModifierTypeName)
                    )
                )
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(
                    label: .identifier("container"),
                    colon: .colonToken(),
                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                )
            ]),
            rightParen: .rightParenToken()
        )
    )

    return FunctionDeclSyntax(
        attributes: AttributeListSyntax([
            .attribute(
                AttributeSyntax(attributeName: TypeSyntax(stringLiteral: "Swift.MainActor"))
            )
        ]),
        modifiers: accessLevel,
        name: .identifier(environmentBridgeHelperName),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(parameters: []),
            returnClause: ReturnClauseSyntax(type: modifierType)
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(StmtSyntax(ExpressionStmtSyntax(expression: callExpr)))
                )
            ])
        )
    )
}

private func makeShadowSafeEnvironmentBridgeHelperDecl(
    accessLevel: DeclModifierListSyntax,
    mappings: [EnvironmentBridgeMappingInfo]
) -> FunctionDeclSyntax {
    var arguments: [LabeledExprSyntax] = [
        LabeledExprSyntax(
            label: .identifier("container"),
            colon: .colonToken(),
            expression: ExprSyntax(
                DeclReferenceExprSyntax(baseName: .keyword(.self))
            ),
            trailingComma: mappings.isEmpty ? nil : .commaToken()
        )
    ]
    for (index, mapping) in mappings.enumerated() {
        arguments.append(
            LabeledExprSyntax(
                label: .identifier("member\(index)"),
                colon: .colonToken(),
                expression: ExprSyntax(
                    stringLiteral: "\\Self.\(mapping.memberName)"
                ),
                trailingComma: .commaToken()
            )
        )
        arguments.append(
            LabeledExprSyntax(
                label: .identifier("environment\(index)"),
                colon: .colonToken(),
                expression: ExprSyntax(mapping.environmentKeyPath),
                trailingComma: index == mappings.count - 1
                    ? nil
                    : .commaToken()
            )
        )
    }

    let callExpr = ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: ExprSyntax(
                MemberAccessExprSyntax(
                    base: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .keyword(.Self))
                    ),
                    declName: DeclReferenceExprSyntax(
                        baseName: .identifier(environmentBridgeModifierTypeName)
                    )
                )
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax(arguments),
            rightParen: .rightParenToken()
        )
    )

    return FunctionDeclSyntax(
        attributes: AttributeListSyntax([
            .attribute(
                AttributeSyntax(
                    attributeName: TypeSyntax(stringLiteral: "Swift.MainActor")
                )
            )
        ]),
        modifiers: accessLevel,
        name: .identifier(environmentBridgeHelperName),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(parameters: []),
            returnClause: ReturnClauseSyntax(
                type: TypeSyntax(stringLiteral: "some SwiftUI.ViewModifier")
            )
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(ExpressionStmtSyntax(expression: callExpr))
                    )
                )
            ])
        )
    )
}

private func makeEnvironmentBridgeBodyExpr(
    mappings: [EnvironmentBridgeMappingInfo]
) -> ExprSyntax {
    mappings.reduce(
        ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("content")))
    ) { partialResult, mapping in
        let memberAccess = ExprSyntax(
            MemberAccessExprSyntax(
                base: partialResult,
                declName: DeclReferenceExprSyntax(baseName: .identifier("environment"))
            )
        )
        let containerMember = ExprSyntax(
            MemberAccessExprSyntax(
                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))),
                declName: DeclReferenceExprSyntax(baseName: .identifier(mapping.memberName))
            )
        )

        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: memberAccess,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(
                        expression: ExprSyntax(mapping.environmentKeyPath),
                        trailingComma: .commaToken()
                    ),
                    LabeledExprSyntax(expression: containerMember),
                ]),
                rightParen: .rightParenToken()
            )
        )
    }
}

private func makeShadowSafeEnvironmentBridgeBodyExpr(
    mappingCount: Int
) -> ExprSyntax {
    (0..<mappingCount).reduce(
        ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("content")))
    ) { partialResult, index in
        let memberAccess = ExprSyntax(
            MemberAccessExprSyntax(
                base: partialResult,
                declName: DeclReferenceExprSyntax(
                    baseName: .identifier("environment")
                )
            )
        )
        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: memberAccess,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(
                        expression: ExprSyntax(
                            DeclReferenceExprSyntax(
                                baseName: .identifier("environment\(index)")
                            )
                        ),
                        trailingComma: .commaToken()
                    ),
                    LabeledExprSyntax(
                        expression: ExprSyntax(
                            stringLiteral: "container[keyPath: member\(index)]"
                        )
                    ),
                ]),
                rightParen: .rightParenToken()
            )
        )
    }
}
