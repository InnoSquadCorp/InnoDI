import SwiftSyntax

/// A final mock is the concrete witness for protocol Self. Leaving Self in a
/// nested call record instead binds it to that record, and mutable Self-typed
/// stub storage is not a legal class member.
final class MockSelfTypeRewriter: SyntaxRewriter {
    private let mockTypeName: String

    init(mockTypeName: String) {
        self.mockTypeName = mockTypeName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
        guard node.name.text == "Self" else { return super.visit(node) }
        return TypeSyntax(node.with(\.name, .identifier(mockTypeName)))
    }
}

func unsupportedMockFunctionShape(_ function: FunctionDeclSyntax) -> String? {
    for parameter in function.signature.parameterClause.parameters {
        let name = (parameter.secondName ?? parameter.firstName).text
        let specifiers = mockParameterSpecifiers(parameter.type)
        if let unsupported = specifiers.first(where: {
            !["consuming", "borrowing", "sending", "__owned", "__shared"].contains($0)
        }) {
            return "\(unsupported) parameter '\(name)' cannot be retained in call history"
        }
        if parameter.ellipsis == nil,
           isDirectMockFunctionType(parameter.type),
           !isStorableMockFunction(parameter.type) {
            return "nonescaping closure parameter '\(name)' cannot be retained in call history"
        }
    }
    if let result = function.signature.returnClause?.type,
       mockParameterSpecifiers(result).contains("sending") {
        return "sending results cannot be repeatedly returned from retained stub storage"
    }
    let genericTokens = (function.genericParameterClause.map {
        Array($0.tokens(viewMode: .sourceAccurate))
    } ?? []) + (function.genericWhereClause.map {
        Array($0.tokens(viewMode: .sourceAccurate))
    } ?? [])
    if zip(genericTokens, genericTokens.dropFirst()).contains(where: {
        $0.text == "~" && ["Copyable", "Escapable"].contains($1.text)
    }) {
        return "noncopyable or nonescapable generic parameters cannot be retained in call history"
    }
    return nil
}

/// Only the parameter's outer attributes/specifiers are storage annotations.
/// Effects inside a closure's own signature still belong to its function type.
func mockCallRecordType(_ type: TypeSyntax) -> TypeSyntax {
    guard var attributed = type.as(AttributedTypeSyntax.self) else { return type }
    attributed.specifiers = []
    attributed.lateSpecifiers = []
    attributed.attributes = attributed.attributes.filter {
        guard let attribute = $0.as(AttributeSyntax.self) else { return true }
        return !["escaping", "autoclosure"].contains(attribute.attributeName.trimmedDescription)
    }
    if attributed.attributes.isEmpty {
        return mockCallRecordType(attributed.baseType).trimmed
    }
    return TypeSyntax(attributed.trimmed)
}

func mockParameterSpecifiers(_ type: TypeSyntax) -> [String] {
    guard let attributed = type.as(AttributedTypeSyntax.self) else { return [] }
    return (Array(attributed.specifiers) + Array(attributed.lateSpecifiers)).map {
        $0.trimmedDescription
    } + mockParameterSpecifiers(attributed.baseType)
}

private func isStorableMockFunction(_ type: TypeSyntax) -> Bool {
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return attributed.attributes.contains {
            guard let attribute = $0.as(AttributeSyntax.self) else { return false }
            if attribute.attributeName.trimmedDescription == "escaping" { return true }
            // A C function pointer has no captured Swift closure context and
            // remains storable without an @escaping annotation.
            return attribute.attributeName.trimmedDescription == "convention"
                && attribute.arguments?.as(LabeledExprListSyntax.self)?.first?
                    .expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "c"
        } || isStorableMockFunction(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
       let element = tuple.elements.first {
        return isStorableMockFunction(element.type)
    }
    return false
}

private func isDirectMockFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) { return true }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isDirectMockFunctionType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
       let element = tuple.elements.first {
        return isDirectMockFunctionType(element.type)
    }
    // Optional closures and variadic arrays already have escaping storage.
    return false
}
