//
//  ProvideMacro.swift
//  InnoDIMacros
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ProvideMacro: PeerMacro, AccessorMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type else {
            return []
        }
        
        let parseResult = parseProvideArguments(attribute)
        let name = identifier.identifier.text
        
        switch parseResult.scope {
        case .transient:
            let overrideName = "_override_\(name)"
            return [storagePeerDecl(name: overrideName, type: type, optional: true)]
        case .shared:
            if parseResult.asyncFactoryExpr != nil {
                let storageName = "_storage_task_\(name)"
                let successType = taskSuccessTypeDescription(from: type)
                let failureType = parseResult.asyncFactoryIsThrowing ? "Error" : "Never"
                return [taskStoragePeerDecl(
                    name: storageName,
                    successType: successType,
                    failureType: failureType
                )]
            }
            let storageName = "_storage_\(name)"
            return [storagePeerDecl(name: storageName, type: type, optional: false)]
        case .input:
            let storageName = "_storage_\(name)"
            return [storagePeerDecl(name: storageName, type: type, optional: false)]
        case .none:
            return []
        }
    }
    
    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let parseResult = parseProvideArguments(attribute)
        
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return []
        }

        let enclosingContainerMainActor = enclosingDIContainerInfo(for: declaration)?.mainActor == true
        let name = identifier.identifier.text
        
        switch parseResult.scope {
        case .shared:
            if parseResult.asyncFactoryExpr != nil {
                let storageName = "_storage_task_\(name)"
                let valueExpr = ExprSyntax(MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier(storageName)),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("value"))
                ))
                let getter = makeGetter(
                    statements: [
                        awaitedReturnStmt(
                            expr: valueExpr,
                            isThrowing: parseResult.asyncFactoryIsThrowing
                        )
                    ],
                    isAsync: true,
                    isThrowing: parseResult.asyncFactoryIsThrowing,
                    isMainActor: enclosingContainerMainActor
                )
                return [getter]
            }

            let storageName = "_storage_\(name)"
            let getter = makeGetter(
                statements: [
                    returnStmt(expr: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .identifier(storageName))
                    ))
                ],
                isAsync: false,
                isThrowing: false,
                isMainActor: enclosingContainerMainActor
            )
            return [getter]

        case .input:
            let storageName = "_storage_\(name)"
            let getter = makeGetter(
                statements: [
                    returnStmt(expr: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .identifier(storageName))
                    ))
                ],
                isAsync: false,
                isThrowing: false,
                isMainActor: enclosingContainerMainActor
            )
            return [getter]
            
        case .transient:
            let overrideName = "_override_\(name)"

            if transientDependencyResolutionShouldFail(
                declaration: declaration,
                parseResult: parseResult,
                memberName: name
            ) {
                return [fatalErrorGetter(
                    "Transient dependency resolution failed validation.",
                    isAsync: parseResult.asyncFactoryExpr != nil,
                    isThrowing: parseResult.asyncFactoryIsThrowing,
                    isMainActor: enclosingContainerMainActor
                )]
            }
            
            let overrideCheck = overrideCheckStmt(overrideName: overrideName)

            if let asyncFactory = parseResult.asyncFactoryExpr {
                var createExpr: ExprSyntax

                if let closure = asyncFactory.as(ClosureExprSyntax.self) {
                    let parsedArguments = parseClosureParameterNames(closure)
                    if parsedArguments.hasWildcard {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(closure),
                                message: SimpleDiagnostic.transientFactoryUnnamedParameters()
                            )
                        )
                        return [fatalErrorGetter(
                            "Transient factory closure parameters must be named for injection.",
                            isAsync: true,
                            isThrowing: parseResult.asyncFactoryIsThrowing,
                            isMainActor: enclosingContainerMainActor
                        )]
                    }
                    createExpr = makeTransientClosureCallExpr(
                        closure: closure,
                        parsed: parsedArguments
                    )
                } else {
                    createExpr = asyncFactory
                }

                let getter = makeGetter(
                    statements: [
                        overrideCheck,
                        awaitedReturnStmt(
                            expr: createExpr,
                            isThrowing: parseResult.asyncFactoryIsThrowing
                        )
                    ],
                    isAsync: true,
                    isThrowing: parseResult.asyncFactoryIsThrowing,
                    isMainActor: enclosingContainerMainActor
                )
                return [getter]
            }

            var createExpr: ExprSyntax

            if let factory = parseResult.factoryExpr {
                if let closure = factory.as(ClosureExprSyntax.self) {
                    let parsedArguments = parseClosureParameterNames(closure)
                    if parsedArguments.hasWildcard {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(closure),
                                message: SimpleDiagnostic.transientFactoryUnnamedParameters()
                            )
                        )
                        return [fatalErrorGetter(
                            "Transient factory closure parameters must be named for injection.",
                            isAsync: false,
                            isThrowing: false,
                            isMainActor: enclosingContainerMainActor
                        )]
                    }
                    createExpr = makeTransientClosureCallExpr(
                        closure: closure,
                        parsed: parsedArguments
                    )
                } else {
                    createExpr = factory
                }
            } else if let typeExpr = parseResult.typeExpr {
                var args: [LabeledExprSyntax] = []
                for dep in parseResult.dependencies {
                    args.append(LabeledExprSyntax(
                        label: .identifier(dep),
                        colon: .colonToken(),
                        expression: makeSelfMemberAccessExpr(name: dep)
                    ))
                }

                createExpr = ExprSyntax(FunctionCallExprSyntax(
                    calledExpression: typeExpr,
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax(args),
                    rightParen: .rightParenToken()
                ))
            } else if let initializer = binding.initializer?.value {
                createExpr = initializer
            } else {
                return [fatalErrorGetter(
                    "Missing factory for transient dependency",
                    isAsync: false,
                    isThrowing: false,
                    isMainActor: enclosingContainerMainActor
                )]
            }
            
            let getter = makeGetter(
                statements: [
                    overrideCheck,
                    returnStmt(expr: createExpr)
                ],
                isAsync: false,
                isThrowing: false,
                isMainActor: enclosingContainerMainActor
            )

            return [getter]

        case .none:
            let getter = makeGetter(
                statements: [
                    fatalErrorStmt(message: "Unknown scope")
                ],
                isAsync: false,
                isThrowing: false,
                isMainActor: enclosingContainerMainActor
            )
            return [getter]
        }
    }
}

private func fatalErrorGetter(
    _ message: String,
    isAsync: Bool,
    isThrowing: Bool,
    isMainActor: Bool
) -> AccessorDeclSyntax {
    let fatalErrorCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("fatalError")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: ExprSyntax(StringLiteralExprSyntax(content: message))
            )
        ]),
        rightParen: .rightParenToken()
    )

    return makeGetter(
        statements: [
            CodeBlockItemSyntax(item: .expr(ExprSyntax(fatalErrorCall)))
        ],
        isAsync: isAsync,
        isThrowing: isThrowing,
        isMainActor: isMainActor
    )
}

private func makeGetter(
    statements: [CodeBlockItemSyntax],
    isAsync: Bool,
    isThrowing: Bool,
    isMainActor: Bool
) -> AccessorDeclSyntax {
    var getter = AccessorDeclSyntax(
        accessorSpecifier: .keyword(.get),
        effectSpecifiers: makeAccessorEffectSpecifiers(isAsync: isAsync, isThrowing: isThrowing),
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )
    if isMainActor {
        getter = getter.with(\.attributes, mainActorAccessorAttributes())
    }
    return getter
}

private func makeAccessorEffectSpecifiers(
    isAsync: Bool,
    isThrowing: Bool
) -> AccessorEffectSpecifiersSyntax? {
    guard isAsync else { return nil }
    let throwsClause: ThrowsClauseSyntax? = isThrowing
        ? ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        : nil
    return AccessorEffectSpecifiersSyntax(
        asyncSpecifier: .keyword(.async),
        throwsClause: throwsClause
    )
}

private func mainActorAccessorAttributes() -> AttributeListSyntax {
    AttributeListSyntax([
        AttributeListSyntax.Element(
            AttributeSyntax(
                attributeName: IdentifierTypeSyntax(name: .identifier("MainActor"))
            )
        )
    ])
}

private func taskSuccessTypeDescription(from type: TypeSyntax) -> String {
    let description = type.trimmedDescription
    if description.hasPrefix("any ") || description.hasPrefix("some ") || description.contains("&") {
        return "(\(description))"
    }
    return description
}

private func enclosingDIContainerInfo(for declaration: some DeclSyntaxProtocol) -> DIContainerAttributeInfo? {
    var current: Syntax? = Syntax(declaration).parent

    while let node = current {
        if let structDecl = node.as(StructDeclSyntax.self),
           let info = parseDIContainerAttribute(structDecl.attributes) {
            return info
        }
        if let classDecl = node.as(ClassDeclSyntax.self),
           let info = parseDIContainerAttribute(classDecl.attributes) {
            return info
        }
        if let actorDecl = node.as(ActorDeclSyntax.self),
           let info = parseDIContainerAttribute(actorDecl.attributes) {
            return info
        }

        current = node.parent
    }

    return nil
}

private func transientDependencyResolutionShouldFail(
    declaration: some DeclSyntaxProtocol,
    parseResult: ProvideArguments,
    memberName: String
) -> Bool {
    guard let members = enclosingProvideMemberNames(for: declaration) else {
        return false
    }

    let knownNames = Set(members)

    for dependency in parseResult.dependencies where !knownNames.contains(dependency) {
        return true
    }

    let parameterNames: [String]
    if let closure = parseResult.factoryExpr?.as(ClosureExprSyntax.self) {
        parameterNames = parseClosureParameterNames(closure).names
    } else if let closure = parseResult.asyncFactoryExpr?.as(ClosureExprSyntax.self) {
        parameterNames = parseClosureParameterNames(closure).names
    } else {
        parameterNames = []
    }

    for dependency in parameterNames where !knownNames.contains(dependency) {
        return true
    }

    if !knownNames.contains(memberName) {
        return true
    }

    return false
}

private func enclosingProvideMemberNames(for declaration: some DeclSyntaxProtocol) -> [String]? {
    var current: Syntax? = Syntax(declaration).parent

    while let node = current {
        let declGroup: (any DeclGroupSyntax)?
        switch true {
        case node.is(StructDeclSyntax.self):
            declGroup = node.as(StructDeclSyntax.self)
        case node.is(ClassDeclSyntax.self):
            declGroup = node.as(ClassDeclSyntax.self)
        case node.is(ActorDeclSyntax.self):
            declGroup = node.as(ActorDeclSyntax.self)
        default:
            declGroup = nil
        }

        if let declGroup,
           parseDIContainerAttribute(declGroup.attributes) != nil {
            return declGroup.memberBlock.members.compactMap { member in
                guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                      hasProvideAttribute(varDecl.attributes),
                      let binding = varDecl.bindings.first,
                      let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    return nil
                }
                return identifier.identifier.text
            }
        }

        current = node.parent
    }

    return nil
}

/// Builds the factory-call expression for a transient accessor. Same as
/// `makeClosureCallExpr(closure:argumentNames:)` except soft (Lazy<T>)
/// parameters are wrapped as `Lazy({ self.<name> })`, because the accessor
/// runs after `self` is fully initialized and therefore can capture it
/// directly — no `_LazyCell` box plumbing is needed here.
private func makeTransientClosureCallExpr(
    closure: ClosureExprSyntax,
    parsed: ClosureParameterList
) -> ExprSyntax {
    // If the references list is available, honor soft kinds; otherwise fall
    // back to the plain member-access path.
    if parsed.references.isEmpty || parsed.references.allSatisfy({ $0.kind == .hard }) {
        return makeClosureCallExpr(closure: closure, argumentNames: parsed.names)
    }

    let expressions: [ExprSyntax] = parsed.references.map { ref in
        if ref.kind == .soft {
            guard let calleeDescription = ref.lazyWrapperCalleeDescription else {
                fatalError("Soft transient dependency '\(ref.name)' is missing a Lazy wrapper callee.")
            }
            return makeLazyAccessorWrapperExpr(
                name: ref.name,
                calleeDescription: calleeDescription
            )
        }
        if ref.kind == .provider {
            guard let calleeDescription = ref.providerWrapperCalleeDescription else {
                fatalError("Provider transient dependency '\(ref.name)' is missing a Provider wrapper callee.")
            }
            return makeProviderAccessorWrapperExpr(
                name: ref.name,
                calleeDescription: calleeDescription
            )
        }
        return makeSelfMemberAccessExpr(name: ref.name)
    }
    return makeClosureCallExpr(closure: closure, argumentExpressions: expressions)
}

private func hasProvideAttribute(_ attributes: AttributeListSyntax?) -> Bool {
    guard let attributes else { return false }

    return attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self),
              let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
            return false
        }
        return identifier.name.text == "Provide"
    }
}
