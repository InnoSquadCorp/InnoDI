import Foundation
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
        let options = parseDIContainerAttribute(decl.attributes) ?? DIContainerAttributeInfo(
            validate: true,
            root: false,
            validateDAG: true
        )
        let accessLevel = containerAccessLevel(for: decl)
        var members: [ProvideMemberModel] = []
        var hadErrors = false

        for member in decl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            if varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
                continue
            }

            guard let attribute = findAttribute(named: "Provide", in: varDecl.attributes) else {
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

            let parseResult = parseProvideArguments(attribute)
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
            } else {
                closureDependencies = []
            }

            let factoryExpressionReferences: [String]
            if let factoryExpr = parseResult.factoryExpr, factoryExpr.as(ClosureExprSyntax.self) == nil {
                factoryExpressionReferences = collectIdentifierReferences(in: factoryExpr)
            } else {
                factoryExpressionReferences = []
            }

            let initializerExpr = binding.initializer?.value
            let initializerReferences = collectIdentifierReferences(in: initializerExpr)

            members.append(
                ProvideMemberModel(
                    name: identifier.identifier.text,
                    type: typeAnnotation.type,
                    scope: scope,
                    factory: parseResult.factoryExpr,
                    typeExpr: parseResult.typeExpr,
                    initializer: initializerExpr,
                    concreteOptIn: parseResult.concrete,
                    withDependencies: parseResult.dependencies,
                    closureDependencies: closureDependencies,
                    expressionReferences: deduplicateStrings(factoryExpressionReferences + initializerReferences),
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

private func collectIdentifierReferences(in expr: ExprSyntax?) -> [String] {
    guard let expr else { return [] }
    let text = expr.description
    let pattern = #"\b[_A-Za-z][_A-Za-z0-9]*\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }

    let keywordBlacklist: Set<String> = [
        "self",
        "Self",
        "super",
        "true",
        "false",
        "nil",
        "in",
        "let",
        "var",
        "if",
        "else",
        "return",
        "switch",
        "case",
        "default",
        "try",
        "catch",
        "throw",
        "throws",
        "rethrows",
        "await",
        "async",
        "where",
        "for",
        "while",
        "repeat",
        "guard",
        "defer",
        "break",
        "continue",
        "do",
        "as",
        "is",
        "any",
        "some"
    ]

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, options: [], range: range)
    let references: [String] = matches.compactMap { match in
        guard let swiftRange = Range(match.range, in: text) else { return nil }
        let token = String(text[swiftRange])
        guard !keywordBlacklist.contains(token) else { return nil }
        guard let first = token.first else { return nil }
        guard first.isLowercase || first == "_" else { return nil }
        return token
    }

    return deduplicateStrings(references)
}
