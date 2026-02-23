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
            let decl: DeclSyntax = "private let \(raw: overrideName): \(type)?"
            return [decl]
        case .shared:
            if parseResult.asyncFactoryExpr != nil {
                let storageName = "_storage_task_\(name)"
                let successType = taskSuccessTypeDescription(from: type)
                let failureType = parseResult.asyncFactoryIsThrowing ? "Error" : "Never"
                let decl: DeclSyntax = "private let \(raw: storageName): Task<\(raw: successType), \(raw: failureType)>"
                return [decl]
            }
            let storageName = "_storage_\(name)"
            let decl: DeclSyntax = "private let \(raw: storageName): \(type)"
            return [decl]
        case .input:
            let storageName = "_storage_\(name)"
            let decl: DeclSyntax = "private let \(raw: storageName): \(type)"
            return [decl]
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
                let valueExpr: String
                if parseResult.asyncFactoryIsThrowing {
                    valueExpr = "try await \(storageName).value"
                } else {
                    valueExpr = "await \(storageName).value"
                }
                let getter = makeGetter(
                    statements: [
                        CodeBlockItemSyntax(item: .stmt(StmtSyntax("return \(raw: valueExpr)")))
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
                    CodeBlockItemSyntax(item: .stmt(StmtSyntax("return \(raw: storageName)")))
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
                    CodeBlockItemSyntax(item: .stmt(StmtSyntax("return \(raw: storageName)")))
                ],
                isAsync: false,
                isThrowing: false,
                isMainActor: enclosingContainerMainActor
            )
            return [getter]
            
        case .transient:
            let overrideName = "_override_\(name)"
            
            let overrideCheck = CodeBlockItemSyntax(item: .stmt(StmtSyntax(
                """
                if let override = \(raw: overrideName) { return override }
                """
            )))

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
                    createExpr = makeClosureCallExpr(closure: closure, argumentNames: parsedArguments.names)
                } else {
                    createExpr = asyncFactory
                }

                let awaitedExpr: String
                if parseResult.asyncFactoryIsThrowing {
                    awaitedExpr = "try await \(createExpr)"
                } else {
                    awaitedExpr = "await \(createExpr)"
                }

                let getter = makeGetter(
                    statements: [
                        overrideCheck,
                        CodeBlockItemSyntax(item: .stmt(StmtSyntax("return \(raw: awaitedExpr)")))
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
                    createExpr = makeClosureCallExpr(closure: closure, argumentNames: parsedArguments.names)
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
                    CodeBlockItemSyntax(item: .stmt(StmtSyntax("return \(createExpr)")))
                ],
                isAsync: false,
                isThrowing: false,
                isMainActor: enclosingContainerMainActor
            )
            
            return [getter]
            
        case .none:
            let getter = makeGetter(
                statements: [
                    CodeBlockItemSyntax(item: .stmt(StmtSyntax("fatalError(\"Unknown scope\")")))
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
