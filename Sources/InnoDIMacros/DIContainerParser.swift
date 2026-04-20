import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct DIContainerParser {
    struct OverridesNameConflict {
        let node: any SyntaxProtocol
        let kind: String
    }

    /// Scans the container body for a user declaration named `Overrides` that
    /// would clash with the synthesized builder struct. Returns the offending
    /// declaration along with its kind ("struct", "class", "typealias", etc.)
    /// so callers can emit a clear warning.
    static func findOverridesNameConflict(in decl: some DeclGroupSyntax) -> OverridesNameConflict? {
        for member in decl.memberBlock.members {
            let d = member.decl
            if let s = d.as(StructDeclSyntax.self), s.name.text == "Overrides" {
                return OverridesNameConflict(node: s, kind: "struct")
            }
            if let c = d.as(ClassDeclSyntax.self), c.name.text == "Overrides" {
                return OverridesNameConflict(node: c, kind: "class")
            }
            if let e = d.as(EnumDeclSyntax.self), e.name.text == "Overrides" {
                return OverridesNameConflict(node: e, kind: "enum")
            }
            if let a = d.as(ActorDeclSyntax.self), a.name.text == "Overrides" {
                return OverridesNameConflict(node: a, kind: "actor")
            }
            if let t = d.as(TypeAliasDeclSyntax.self), t.name.text == "Overrides" {
                return OverridesNameConflict(node: t, kind: "typealias")
            }
        }
        return nil
    }

    static func userDefinedInitializers(in decl: some DeclGroupSyntax) -> [InitializerDeclSyntax] {
        let bodyInitializers = decl.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }

        guard let sourceFile = sourceFile(containing: Syntax(decl)),
              let declarationPath = nominalDeclarationPath(containing: Syntax(decl)) else {
            return bodyInitializers
        }

        let extensionInitializers = sourceFile.statements.compactMap { statement in
            statement.item.as(ExtensionDeclSyntax.self)
        }
        .filter { matchesSameFileContainerExtension($0, declarationPath: declarationPath) }
        .flatMap { extensionDecl in
            extensionDecl.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        }

        return bodyInitializers + extensionInitializers
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

            let closureParameterList: ClosureParameterList
            if let closure = parseResult.factoryExpr?.as(ClosureExprSyntax.self) {
                closureParameterList = parseClosureParameterNames(closure)
            } else if let asyncClosure = parseResult.asyncFactoryExpr?.as(ClosureExprSyntax.self) {
                closureParameterList = parseClosureParameterNames(asyncClosure)
            } else {
                closureParameterList = ClosureParameterList(names: [], references: [], hasWildcard: false)
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
            let withDependencyReferences = extractWithDependencyReferences(from: attribute)

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
                    withDependencyReferences: withDependencyReferences,
                    closureDependencies: closureParameterList.names,
                    closureParameterReferences: closureParameterList.references,
                    closureHasWildcard: closureParameterList.hasWildcard,
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

private func sourceFile(containing syntax: Syntax) -> SourceFileSyntax? {
    var current: Syntax? = syntax

    while let node = current {
        if let sourceFile = node.as(SourceFileSyntax.self) {
            return sourceFile
        }
        current = node.parent
    }

    return nil
}

private func nominalDeclarationPath(containing syntax: Syntax) -> String? {
    var current: Syntax? = syntax
    var components: [String] = []

    while let node = current {
        if let name = nominalDeclarationName(for: node) {
            components.append(name)
        }
        current = node.parent
    }

    guard !components.isEmpty else {
        return nil
    }

    return components.reversed().joined(separator: ".")
}

private func nominalDeclarationName(for syntax: Syntax) -> String? {
    if let structDecl = syntax.as(StructDeclSyntax.self) {
        return structDecl.name.text
    }
    if let classDecl = syntax.as(ClassDeclSyntax.self) {
        return classDecl.name.text
    }
    if let actorDecl = syntax.as(ActorDeclSyntax.self) {
        return actorDecl.name.text
    }
    if let enumDecl = syntax.as(EnumDeclSyntax.self) {
        return enumDecl.name.text
    }
    return nil
}

private func matchesSameFileContainerExtension(_ extensionDecl: ExtensionDeclSyntax, declarationPath: String) -> Bool {
    guard extensionDecl.genericWhereClause == nil else {
        return false
    }

    return normalizedSemanticTypeReference(extensionDecl.extendedType)?.displayPath == declarationPath
}

private func extractWithDependencyReferences(from attribute: AttributeSyntax) -> [WithDependencyReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "with" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return []
        }

        return arrayExpr.elements.compactMap { element in
            guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
                  let property = keyPath.components.last?.component.as(KeyPathPropertyComponentSyntax.self)?.declName.baseName.text else {
                return nil
            }
            return WithDependencyReference(name: property, keyPath: keyPath)
        }
    }

    return []
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
