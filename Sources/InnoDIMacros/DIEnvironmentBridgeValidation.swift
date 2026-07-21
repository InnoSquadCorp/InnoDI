//
//  DIEnvironmentBridgeValidation.swift
//  InnoDIMacros
//
//  Validation and declaration analysis for `@DIEnvironmentBridge`.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Validation model

struct EnvironmentBridgeMappingInfo {
    let memberName: String
    let environmentKeyPath: KeyPathExprSyntax
}

struct EnvironmentBridgeValidationResult {
    let mappings: [EnvironmentBridgeMappingInfo]?
}

private struct EnvironmentBridgeContainerMemberInfo {
    let name: String
    let isAsyncProvide: Bool
}

func validateEnvironmentBridge(
    attribute: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext,
    emitDiagnostics: Bool
) -> EnvironmentBridgeValidationResult {
    guard validateEnvironmentBridgeDeclaration(
        attribute: attribute,
        declaration: declaration,
        context: context,
        emitDiagnostics: emitDiagnostics
    ) else {
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let firstArgument = arguments.first,
          let arrayExpr = firstArgument.expression.as(ArrayExprSyntax.self) else {
        if emitDiagnostics {
            context.emit(
                SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidArguments(),
                at: Syntax(attribute)
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    return parseEnvironmentBridgeMappings(
        arrayExpr,
        declaration: declaration,
        context: context,
        emitDiagnostics: emitDiagnostics
    )
}

// MARK: - Declaration preflight

private func validateEnvironmentBridgeDeclaration(
    attribute: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext,
    emitDiagnostics: Bool
) -> Bool {
    if isDeclarationInExtensionLookupScope(
        declaration,
        lexicalContext: context.lexicalContext
    ) {
        if emitDiagnostics {
            context.emit(
                SimpleDiagnostic
                    .swiftUIEnvironmentBridgeExtensionContextUnsupported(),
                at: Syntax(attribute)
            )
        }
        return false
    }

    if let unsupported = unsupportedEnvironmentBridgeDeclaration(
        declaration
    ) {
        if emitDiagnostics {
            context.emit(
                SimpleDiagnostic
                    .swiftUIEnvironmentBridgeUnsupportedDeclarationKind(
                        name: unsupported.name,
                        kind: unsupported.kind
                    ),
                at: Syntax(attribute)
            )
        }
        return false
    }

    if let privateLookupComponent = privateNestedEnvironmentBridgeLookupComponent(
        declaration,
        lexicalContext: context.lexicalContext
    ) {
        if emitDiagnostics {
            context.emit(
                SimpleDiagnostic
                    .swiftUIEnvironmentBridgePrivateNestedTarget(
                        name: privateLookupComponent
                    ),
                at: Syntax(attribute)
            )
        }
        return false
    }

    if environmentBridgeHasParameterPack(declaration) {
        if emitDiagnostics {
            context.emit(
                SimpleDiagnostic
                    .swiftUIEnvironmentBridgeParameterPackUnsupported(),
                at: Syntax(attribute)
            )
        }
        return false
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
            context.emit(
                SimpleDiagnostic.swiftUIEnvironmentBridgeReservedModuleName(
                    declarationName: conflict.name
                ),
                at: generatedNameDiagnosticAnchor(
                    for: conflict,
                    attachedTo: declaration
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
            context.emit(message, at: conflict.anchor)
        }
    }
    return !hasCoreContainerConflict
        && qualifierConflicts.isEmpty
        && generatedNameConflicts.isEmpty
}

// MARK: - Mapping parsing

private func parseEnvironmentBridgeMappings(
    _ arrayExpr: ArrayExprSyntax,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext,
    emitDiagnostics: Bool
) -> EnvironmentBridgeValidationResult {
    let membersByName = Dictionary(
        uniqueKeysWithValues: containerMemberInfos(in: declaration).map {
            ($0.name, $0)
        }
    )
    var seenMembers: Set<String> = []
    var mappings: [EnvironmentBridgeMappingInfo] = []
    var hadErrors = false

    for element in arrayExpr.elements {
        guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
            if emitDiagnostics {
                context.emit(
                    SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member"),
                    at: Syntax(element.expression)
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
                        context.emit(
                            SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member"),
                            at: Syntax(tupleElement.expression)
                        )
                    }
                    hadErrors = true
                    continue
                }
                memberName = parsedMemberName
            case "environment":
                guard let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self) else {
                    if emitDiagnostics {
                        context.emit(
                            SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "environment"),
                            at: Syntax(tupleElement.expression)
                        )
                    }
                    hadErrors = true
                    continue
                }
                guard let canonicalKeyPath = canonicalEnvironmentBridgeKeyPath(
                    keyPath
                ) else {
                    if emitDiagnostics {
                        context.emit(
                            SimpleDiagnostic
                                .swiftUIEnvironmentBridgeInvalidEnvironmentKeyPath(),
                            at: Syntax(tupleElement.expression)
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
                context.emit(
                    SimpleDiagnostic.swiftUIEnvironmentBridgeUnknownMember(memberName: memberName),
                    at: Syntax(element.expression)
                )
            }
            hadErrors = true
            continue
        }

        if memberInfo.isAsyncProvide {
            if emitDiagnostics {
                context.emit(
                    SimpleDiagnostic.swiftUIEnvironmentBridgeAsyncMember(memberName: memberName),
                    at: Syntax(element.expression)
                )
            }
            hadErrors = true
            continue
        }

        guard seenMembers.insert(memberName).inserted else {
            if emitDiagnostics {
                context.emit(
                    SimpleDiagnostic.swiftUIEnvironmentBridgeDuplicateMember(memberName: memberName),
                    at: Syntax(element.expression)
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

func environmentBridgeAccessLevelModifiers(
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

func environmentBridgeVisibleGenericParameterNames(
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
