import Foundation
import SwiftSyntax

// Stable helper-name planning for generated mock members.
struct MockFunctionNames {
    let stem: String
    let callStructName: String
    let callsProperty: String
    let returnProperty: String
    let resultProperty: String
    let thrownErrorProperty: String
    let handlerProperty: String

    func generatedValueNames(for function: FunctionDeclSyntax) -> Set<String> {
        let isGeneric = function.genericParameterClause != nil
        let isThrowing = function.signature.effectSpecifiers?.throwsClause != nil
        let returnsVoid = isVoidReturnType(
            function.signature.returnClause?.type.trimmedDescription
        )

        var names: Set<String> = [callsProperty]
        if isGeneric {
            names.insert(handlerProperty)
        } else if !returnsVoid {
            names.insert(isThrowing ? resultProperty : returnProperty)
        } else if isThrowing {
            names.insert(thrownErrorProperty)
        }
        return names
    }
}

private func makeFunctionNames(
    baseName: String,
    parameters: FunctionParameterListSyntax,
    forceQualifiedNames: Bool
) -> MockFunctionNames {
    let base = baseName.safeLowerCamelIdentifier
    let stem: String
    if forceQualifiedNames {
        let suffix = parameters.map { parameter -> String in
            let label = parameter.firstName.text == "_"
                ? "Unlabeled"
                : parameter.firstName.text.identifierStem
            return label + parameter.type.trimmedDescription.identifierStem
        }.joined()
        stem = base + (suffix.isEmpty ? "NoArguments" : suffix)
    } else {
        stem = base
    }

    return makeFunctionNames(stem: stem)
}

private func makeFunctionNames(stem: String) -> MockFunctionNames {
    MockFunctionNames(
        stem: stem,
        callStructName: "\(stem.capitalizedFirst)Call",
        callsProperty: "\(stem)Calls",
        returnProperty: "\(stem)ReturnValue",
        resultProperty: "\(stem)Result",
        thrownErrorProperty: "\(stem)ThrownError",
        handlerProperty: "\(stem)Handler"
    )
}

func plannedFunctionNames(
    in protocolDecl: ProtocolDeclSyntax
) -> [MockFunctionNames] {
    let functions = protocolDecl.memberBlock.members.compactMap {
        $0.decl.as(FunctionDeclSyntax.self)
    }
    let overloadCounts = Dictionary(
        grouping: functions.map { $0.name.text },
        by: { $0 }
    ).mapValues(\.count)
    let declaredValueNames = Set(
        protocolDecl.memberBlock.members.flatMap { member -> [String] in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                return []
            }
            return variable.bindings.compactMap {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
        }
    )
    let candidates = functions.map { function in
        makeFunctionNames(
            baseName: function.name.text,
            parameters: function.signature.parameterClause.parameters,
            forceQualifiedNames: function.genericParameterClause != nil
                || (overloadCounts[function.name.text] ?? 0) > 1
        )
    }
    let stemCounts = Dictionary(
        grouping: candidates.map(\.stem),
        by: { $0 }
    ).mapValues(\.count)

    return zip(functions, candidates).map { function, candidate in
        let collidesWithFunction = (stemCounts[candidate.stem] ?? 0) > 1
        let collidesWithProperty = !candidate
            .generatedValueNames(for: function)
            .isDisjoint(with: declaredValueNames)
        guard collidesWithFunction || collidesWithProperty else {
            return candidate
        }

        let signatureIdentity = [
            function.name.text,
            function.genericParameterClause?.trimmedDescription ?? "",
            function.signature.trimmedDescription,
            function.genericWhereClause?.trimmedDescription ?? "",
        ].joined(separator: "|")
        return makeFunctionNames(
            stem: candidate.stem
                + signatureIdentity.stableIdentifierSuffix.capitalizedFirst
        )
    }
}

extension String {
    var unescapedIdentifier: String {
        var value = self
        if value.first == "`" {
            value.removeFirst()
        }
        if value.last == "`" {
            value.removeLast()
        }
        return value
    }

    var escapedSwiftIdentifier: String {
        if swiftKeywords.contains(self) {
            return "`\(self)`"
        }
        return self
    }

    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }

    var identifierStem: String {
        let words = splitIntoIdentifierWords()
        guard !words.isEmpty else { return "Value" }
        return words.map(\.capitalizedFirst).joined()
    }

    var safeLowerCamelIdentifier: String {
        let stem = identifierStem
        guard let first = stem.first else { return "value" }
        return String(first).lowercased() + stem.dropFirst()
    }

    var stableIdentifierSuffix: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "h%016llx", hash)
    }

    private func splitIntoIdentifierWords() -> [String] {
        var words: [String] = []
        var current = ""
        for scalar in unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}

private let swiftKeywords: Set<String> = [
    "associatedtype",
    "class",
    "deinit",
    "enum",
    "extension",
    "fileprivate",
    "func",
    "import",
    "init",
    "inout",
    "internal",
    "let",
    "open",
    "operator",
    "private",
    "precedencegroup",
    "protocol",
    "public",
    "rethrows",
    "static",
    "struct",
    "subscript",
    "typealias",
    "var",
    "break",
    "case",
    "catch",
    "continue",
    "default",
    "defer",
    "do",
    "else",
    "fallthrough",
    "for",
    "guard",
    "if",
    "in",
    "repeat",
    "return",
    "throw",
    "switch",
    "where",
    "while",
    "as",
    "Any",
    "false",
    "is",
    "nil",
    "self",
    "Self",
    "super",
    "throws",
    "true",
    "try",
]
