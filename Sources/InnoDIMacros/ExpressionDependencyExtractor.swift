import SwiftSyntax

private let expressionDependencyKeywordBlacklist: Set<String> = [
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

func extractExpressionDependencyReferences(from expr: ExprSyntax?) -> [String] {
    guard let expr else { return [] }
    var references: [String] = []

    func collect(token: String) {
        guard !token.isEmpty else { return }
        guard !expressionDependencyKeywordBlacklist.contains(token) else { return }
        guard let first = token.first, first.isLowercase || first == "_" else { return }
        references.append(token)
    }

    func walk(node: Syntax) {
        if let declReference = node.as(DeclReferenceExprSyntax.self) {
            collect(token: declReference.baseName.text)
        }

        if let memberAccess = node.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "self" {
            collect(token: memberAccess.declName.baseName.text)
        }

        for child in node.children(viewMode: .sourceAccurate) {
            walk(node: child)
        }
    }

    walk(node: Syntax(expr))
    return deduplicateStrings(references)
}
