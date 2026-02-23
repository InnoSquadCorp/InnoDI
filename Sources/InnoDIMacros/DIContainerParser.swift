import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct DIContainerParser {
    static func hasUserDefinedInit(in decl: some DeclGroupSyntax) -> Bool {
        decl.memberBlock.members.contains { member in
            member.decl.is(InitializerDeclSyntax.self)
        }
    }

    static func parse(
        declaration decl: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) -> DIContainerExpansionModel? {
        let options = InnoDICore.parseDIContainerAttribute(decl.attributes) ?? DIContainerAttributeInfo(
            validate: true,
            root: false,
            validateDAG: true,
            mainActor: false
        )
        let accessLevel = containerAccessLevel(for: decl)
        var members: [ProvideMemberModel] = []
        var hadErrors = false

        if options.mainActor, let conflictingActor = detectConflictingGlobalActor(in: decl.attributes) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(decl),
                    message: SimpleDiagnostic.containerMainActorConflict(actorName: conflictingActor)
                )
            )
            hadErrors = true
        }

        for member in decl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            if varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
                continue
            }

            guard let attribute = InnoDICore.findAttribute(named: "Provide", in: varDecl.attributes) else {
                continue
            }

            guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else {
                context.diagnose(Diagnostic(node: Syntax(varDecl), message: SimpleDiagnostic.provideSingleBinding()))
                hadErrors = true
                continue
            }

            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                context.diagnose(Diagnostic(node: Syntax(binding), message: SimpleDiagnostic.provideNamedPropertyRequired()))
                hadErrors = true
                continue
            }

            guard let typeAnnotation = binding.typeAnnotation else {
                context.diagnose(Diagnostic(node: Syntax(binding), message: SimpleDiagnostic.provideExplicitTypeRequired()))
                hadErrors = true
                continue
            }

            let parseResult = InnoDICore.parseProvideArguments(attribute)
            guard let scope = parseResult.scope else {
                if let name = parseResult.scopeName {
                    context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic.provideUnknownScope(name)))
                }
                hadErrors = true
                continue
            }

            let closureDependencies: [String]
            if let closure = parseResult.factoryExpr?.as(ClosureExprSyntax.self) {
                closureDependencies = parseClosureParameterNames(closure).names
            } else if let asyncClosure = parseResult.asyncFactoryExpr?.as(ClosureExprSyntax.self) {
                closureDependencies = parseClosureParameterNames(asyncClosure).names
            } else {
                closureDependencies = []
            }

            let factoryExpressionReferences: [String]
            if let factoryExpr = parseResult.factoryExpr, factoryExpr.as(ClosureExprSyntax.self) == nil {
                factoryExpressionReferences = extractExpressionDependencyReferences(from: factoryExpr)
            } else {
                factoryExpressionReferences = []
            }

            let asyncFactoryExpressionReferences: [String]
            if let asyncFactoryExpr = parseResult.asyncFactoryExpr, asyncFactoryExpr.as(ClosureExprSyntax.self) == nil {
                asyncFactoryExpressionReferences = extractExpressionDependencyReferences(from: asyncFactoryExpr)
            } else {
                asyncFactoryExpressionReferences = []
            }

            let initializerExpr = binding.initializer?.value
            let initializerReferences = extractExpressionDependencyReferences(from: initializerExpr)

            members.append(
                ProvideMemberModel(
                    name: identifier.identifier.text,
                    type: typeAnnotation.type,
                    scope: scope,
                    factory: parseResult.factoryExpr,
                    asyncFactory: parseResult.asyncFactoryExpr,
                    asyncFactoryIsThrowing: parseResult.asyncFactoryIsThrowing,
                    typeExpr: parseResult.typeExpr,
                    initializer: initializerExpr,
                    concreteOptIn: parseResult.concrete,
                    withDependencies: parseResult.dependencies,
                    closureDependencies: closureDependencies,
                    expressionReferences: deduplicateStrings(factoryExpressionReferences + asyncFactoryExpressionReferences + initializerReferences),
                    attribute: attribute,
                    bindingSyntax: binding
                )
            )
        }

        if hadErrors {
            return nil
        }

        return DIContainerExpansionModel(
            options: options,
            accessLevel: accessLevel,
            members: members
        )
    }
}

private func containerAccessLevel(for decl: some DeclGroupSyntax) -> String? {
    let modifiers = decl.modifiers
    if modifiers.isEmpty {
        return nil
    }
    for modifier in modifiers {
        switch modifier.name.text {
        case "public", "open":
            return "public"
        case "internal", "fileprivate", "private":
            return modifier.name.text
        default:
            continue
        }
    }
    return nil
}

private func detectConflictingGlobalActor(in attributes: AttributeListSyntax?) -> String? {
    guard let attributes else { return nil }
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        guard let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) else { continue }
        let name = identifier.name.text
        if name == "DIContainer" || name == "MainActor" {
            continue
        }
        if name.hasSuffix("Actor") {
            return name
        }
    }
    return nil
}
