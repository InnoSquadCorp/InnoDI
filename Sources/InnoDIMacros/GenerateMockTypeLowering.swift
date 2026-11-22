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
    if function.genericParameterClause?.parameters.contains(where: { $0.specifier != nil }) == true {
        return "parameter packs cannot be retained in call history"
    }
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

/// How a written type spells optionality at its top level.
enum MockOptionalSpelling {
    case none
    /// `T?`
    case sugar
    /// `T!`
    case implicitlyUnwrapped
    /// `Optional<T>`, `Swift.Optional<T>`, or a parenthesized optional.
    case named
}

/// The optionality the type syntax states. A function type whose result is
/// optional (`() -> Int?`) is not optional, and a typealias that names an
/// optional cannot be resolved by a macro, so it reports `.none`.
func mockOptionalSpelling(_ type: TypeSyntax) -> MockOptionalSpelling {
    if type.is(OptionalTypeSyntax.self) { return .sugar }
    if type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return .implicitlyUnwrapped }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
       let element = tuple.elements.first,
       element.firstName == nil, element.ellipsis == nil {
        return mockOptionalSpelling(element.type) == .none ? .none : .named
    }
    let isOptionalName: Bool
    let genericArguments: GenericArgumentClauseSyntax?
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        isOptionalName = identifier.name.text == "Optional"
        genericArguments = identifier.genericArgumentClause
    } else if let member = type.as(MemberTypeSyntax.self) {
        isOptionalName = member.name.text == "Optional"
            && member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift"
        genericArguments = member.genericArgumentClause
    } else {
        return .none
    }
    return isOptionalName && genericArguments?.arguments.count == 1 ? .named : .none
}

/// `T!` spelled as `T?`, the form Swift accepts in generic arguments, casts,
/// and stored stubs. Every other type keeps its spelling.
func mockStorableTypeSpelling(_ type: TypeSyntax) -> String {
    guard let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) else {
        return type.trimmedDescription
    }
    return OptionalTypeSyntax(wrappedType: unwrapped.wrappedType.trimmed).trimmedDescription
}

/// A one-line spelling of `type` for string literals. A type written across
/// several lines, or with comments, keeps its tokens; single-line types keep
/// their exact spelling.
func mockSingleLineTypeSpelling(_ type: TypeSyntax) -> String {
    var text = ""
    var previous: TokenSyntax?
    for token in type.trimmed.tokens(viewMode: .sourceAccurate) {
        if let previous {
            let gap = previous.trailingTrivia + token.leadingTrivia
            let isPlain = gap.allSatisfy {
                if case .spaces = $0 { return true }
                if case .tabs = $0 { return true }
                return false
            }
            if isPlain {
                text += gap.description
            } else if !["(", "[", "<"].contains(previous.text),
                      ![")", "]", ">", ",", ":"].contains(token.text) {
                text += " "
            }
        }
        text += token.text
        previous = token
    }
    return text
}

/// Whether `type` contains an opaque `some` type in any position.
func containsMockOpaqueType(_ type: TypeSyntax) -> Bool {
    final class OpaqueFinder: SyntaxVisitor {
        var found = false
        override func visit(_ node: SomeOrAnyTypeSyntax) -> SyntaxVisitorContinueKind {
            if node.someOrAnySpecifier.tokenKind == .keyword(.some) {
                found = true
                return .skipChildren
            }
            return .visitChildren
        }
    }
    let finder = OpaqueFinder(viewMode: .sourceAccurate)
    finder.walk(type)
    return finder.found
}

/// Every type name a requirement resolves through lexical lookup, for
/// example `ToolCall` in `func tool() -> ToolCall` or `ToolCall.Kind`. A
/// function's own generic parameters are scoped to it and are left out.
func mockReferencedTypeNames(in member: DeclSyntax) -> Set<String> {
    final class TypeNameCollector: SyntaxVisitor {
        var names: Set<String> = []
        override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.name.text.unescapedIdentifier)
            return .visitChildren
        }
    }
    let collector = TypeNameCollector(viewMode: .sourceAccurate)
    if let function = member.as(FunctionDeclSyntax.self) {
        if let generics = function.genericParameterClause { collector.walk(generics) }
        collector.walk(function.signature)
        if let whereClause = function.genericWhereClause { collector.walk(whereClause) }
        let scoped = Set(function.genericParameterClause?.parameters.map {
            $0.name.text.unescapedIdentifier
        } ?? [])
        return collector.names.subtracting(scoped)
    }
    if let variable = member.as(VariableDeclSyntax.self) {
        for binding in variable.bindings {
            if let annotation = binding.typeAnnotation { collector.walk(annotation) }
        }
    }
    return collector.names
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
