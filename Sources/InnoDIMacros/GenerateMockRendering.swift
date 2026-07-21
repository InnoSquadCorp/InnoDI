import Foundation
import SwiftSyntax

// Protocol requirement lowering and generated mock source rendering.
struct RenderedFunctionMock {
    let snippet: String
    let usesNotStubbedError: Bool
}
func renderFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    if unsupportedMockIsolation(in: function.attributes) != nil {
        return nil
    }
    if function.modifiers.contains(where: { $0.name.text != "mutating" }) {
        return nil
    }
    if hasUnsupportedThrowsClause(function.signature) {
        return nil
    }
    let isGeneric = function.genericParameterClause != nil
    if isGeneric {
        return renderGenericFunctionMock(function: function, names: names)
    }
    return renderTypedFunctionMock(function: function, names: names)
}

private func renderTypedFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    guard let callParameters = renderableCallParameters(parameters) else {
        return nil
    }

    let returnsVoid = isVoidReturnType(signature.returnClause?.type.trimmedDescription)

    let returnTypeRendered = signature.returnClause?.type.trimmedDescription ?? "Void"
    if !returnsVoid && isOpaqueType(returnTypeRendered) {
        return nil
    }
    let parametersRendered = parameters.map { $0.trimmedDescription }.joined(separator: ", ")
    var effectSpecifierTokens: [String] = []
    if isAsync { effectSpecifierTokens.append("async") }
    if isThrowing { effectSpecifierTokens.append("throws") }
    let effectSpecifiersJoined = effectSpecifierTokens.isEmpty
        ? ""
        : " " + effectSpecifierTokens.joined(separator: " ")

    var snippetLines: [String] = []

    let callFields = callParameters
        .map { "        let \($0.name): \($0.type)" }
        .joined(separator: "\n")
    snippetLines.append("    struct \(names.callStructName) {")
    if !callFields.isEmpty {
        snippetLines.append(callFields)
    }
    snippetLines.append("    }")
    snippetLines.append("    private(set) var \(names.callsProperty): [\(names.callStructName)] = []")

    if !returnsVoid {
        if isThrowing {
            // `Result<T, Error>` keeps the typed `throw` lossy but lets the
            // mock author choose between `.success(value)` and `.failure(error)`
            // with a single assignment. The default failure prompts the test
            // author with the missing stub identifier through the nested
            // `_InnoDIMockNotStubbed` error.
            snippetLines.append(
                "    var \(names.resultProperty): Result<\(returnTypeRendered), Error> = .failure(_InnoDIMockNotStubbed(selector: \"\(names.resultProperty)\"))"
            )
        } else {
            snippetLines.append("    var \(names.returnProperty): \(optionalStorageType(returnTypeRendered))")
        }
    } else if isThrowing {
        // Even a Void-returning throwing function needs an opt-in error
        // hook so tests can simulate the failure path.
        snippetLines.append("    var \(names.thrownErrorProperty): Error?")
    }

    let recordArgs = callParameters
        .map { "\($0.label): \($0.name)" }
        .joined(separator: ", ")
    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    snippetLines.append("    func \(baseName)(\(parametersRendered))\(effectSpecifiersJoined)\(returnFragment) {")
    snippetLines.append("        \(names.callsProperty).append(.init(\(recordArgs)))")
    if !returnsVoid {
        if isThrowing {
            snippetLines.append("        return try \(names.resultProperty).get()")
        } else {
            snippetLines.append("        guard let value = \(names.returnProperty) else {")
            snippetLines.append("            preconditionFailure(\"\(names.returnProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
            snippetLines.append("        }")
            snippetLines.append("        return value")
        }
    } else if isThrowing {
        snippetLines.append("        if let error = \(names.thrownErrorProperty) {")
        snippetLines.append("            throw error")
        snippetLines.append("        }")
    }
    snippetLines.append("    }")

    return RenderedFunctionMock(
        snippet: snippetLines.joined(separator: "\n"),
        usesNotStubbedError: isThrowing && !returnsVoid
    )
}

private func renderGenericFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    guard let callParameters = renderableCallParameters(parameters, eraseTypes: true) else {
        return nil
    }
    let parametersRendered = parameters.map { $0.trimmedDescription }.joined(separator: ", ")
    let returnTypeRendered = signature.returnClause?.type.trimmedDescription ?? "Void"
    let returnsVoid = isVoidReturnType(signature.returnClause?.type.trimmedDescription)
    var effectSpecifierTokens: [String] = []
    if isAsync { effectSpecifierTokens.append("async") }
    if isThrowing { effectSpecifierTokens.append("throws") }
    let effectSpecifiersJoined = effectSpecifierTokens.isEmpty
        ? ""
        : " " + effectSpecifierTokens.joined(separator: " ")

    let genericParameterClause = function.genericParameterClause?.trimmedDescription ?? ""
    let genericWhereClause = function.genericWhereClause.map { " " + $0.trimmedDescription } ?? ""
    let handlerEffectsJoined = effectSpecifiersJoined
    let handlerReturnType = returnsVoid ? "Void" : "Any"
    let invocationPrefix = effectInvocationPrefix(isAsync: isAsync, isThrowing: isThrowing)
    let handlerArguments = callParameters.map(\.name).joined(separator: ", ")
    let handlerArgumentArray = handlerArguments.isEmpty ? "[]" : "[\(handlerArguments)]"

    var snippetLines: [String] = []
    let callFields = callParameters
        .map { "        let \($0.name): \($0.type)" }
        .joined(separator: "\n")
    snippetLines.append("    struct \(names.callStructName) {")
    if !callFields.isEmpty {
        snippetLines.append(callFields)
    }
    snippetLines.append("    }")
    snippetLines.append("    private(set) var \(names.callsProperty): [\(names.callStructName)] = []")
    snippetLines.append("    var \(names.handlerProperty): (([Any])\(handlerEffectsJoined) -> \(handlerReturnType))?")

    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    snippetLines.append("    func \(baseName)\(genericParameterClause)(\(parametersRendered))\(effectSpecifiersJoined)\(returnFragment)\(genericWhereClause) {")
    let recordArgs = callParameters.map { "\($0.label): \($0.name)" }.joined(separator: ", ")
    snippetLines.append("        \(names.callsProperty).append(.init(\(recordArgs)))")
    if returnsVoid {
        snippetLines.append("        if let handler = \(names.handlerProperty) {")
        snippetLines.append("            \(invocationPrefix)handler(\(handlerArgumentArray))")
        snippetLines.append("        }")
    } else {
        snippetLines.append("        guard let handler = \(names.handlerProperty) else {")
        snippetLines.append("            preconditionFailure(\"\(names.handlerProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
        snippetLines.append("        }")
        snippetLines.append("        let rawValue = \(invocationPrefix)handler(\(handlerArgumentArray))")
        snippetLines.append("        guard let value = rawValue as? \(returnTypeRendered) else {")
        snippetLines.append("            preconditionFailure(\"\(names.handlerProperty) returned a value that cannot be cast to \(returnTypeRendered)\")")
        snippetLines.append("        }")
        snippetLines.append("        return value")
    }
    snippetLines.append("    }")

    return RenderedFunctionMock(
        snippet: snippetLines.joined(separator: "\n"),
        usesNotStubbedError: false
    )
}

func renderVariableMock(variable: VariableDeclSyntax) -> String? {
    if unsupportedMockIsolation(in: variable.attributes) != nil {
        return nil
    }
    guard variable.bindings.count == 1,
          let binding = variable.bindings.first,
          let typeAnnotation = binding.typeAnnotation,
          binding.pattern.is(IdentifierPatternSyntax.self) else {
        return nil
    }
    // Skip computed-only requirements with effects (async/throws getters).
    if let accessorBlock = binding.accessorBlock,
       case .accessors(let accessors) = accessorBlock.accessors {
        for accessor in accessors {
            if accessor.effectSpecifiers?.asyncSpecifier != nil { return nil }
            if accessor.effectSpecifiers?.throwsClause != nil { return nil }
        }
    }
    let name = (binding.pattern.as(IdentifierPatternSyntax.self))?.identifier.text ?? "<unknown>"
    let type = typeAnnotation.type.trimmedDescription
    let escapedName = name.escapedSwiftIdentifier
    let storageName = "__innodi_\(name.safeLowerCamelIdentifier)_\(name.stableIdentifierSuffix)StubValue"
    let storageType = optionalStorageType(type)
    return """
        private var \(storageName): \(storageType)
        var \(escapedName): \(type) {
            get {
                guard let value = \(storageName) else {
                    preconditionFailure("\(name) was not set on \\(Self.self) before it was read")
                }
                return value
            }
            set {
                \(storageName) = newValue
            }
        }
    """
}

private func renderableCallParameters(
    _ parameters: FunctionParameterListSyntax,
    eraseTypes: Bool = false
) -> [(label: String, name: String, type: String)]? {
    var usedNames: [String: Int] = [:]
    var rendered: [(label: String, name: String, type: String)] = []
    for (index, parameter) in parameters.enumerated() {
        let internalName = (parameter.secondName?.text ?? parameter.firstName.text)
        let baseFieldName = internalName == "_"
            ? "value\(index + 1)"
            : internalName.unescapedIdentifier.safeLowerCamelIdentifier
        let count = usedNames[baseFieldName, default: 0]
        usedNames[baseFieldName] = count + 1
        let unescapedFieldName = count == 0 ? baseFieldName : "\(baseFieldName)\(count + 1)"
        guard let typeText = renderableCallRecordType(parameter.type.trimmedDescription, eraseTypes: eraseTypes) else {
            return nil
        }
        rendered.append((unescapedFieldName, unescapedFieldName.escapedSwiftIdentifier, typeText))
    }
    return rendered
}

private func renderableCallRecordType(_ typeText: String, eraseTypes: Bool) -> String? {
    if typeText.hasPrefix("inout ") {
        return nil
    }
    if eraseTypes {
        return "Any"
    }
    if isOpaqueType(typeText) {
        return nil
    }

    return typeText
        .replacingOccurrences(of: "@escaping ", with: "")
        .replacingOccurrences(of: "@autoclosure ", with: "")
}

private func effectInvocationPrefix(isAsync: Bool, isThrowing: Bool) -> String {
    var tokens: [String] = []
    if isThrowing { tokens.append("try") }
    if isAsync { tokens.append("await") }
    return tokens.isEmpty ? "" : tokens.joined(separator: " ") + " "
}

private func hasUnsupportedThrowsClause(_ signature: FunctionSignatureSyntax) -> Bool {
    guard let throwsClause = signature.effectSpecifiers?.throwsClause else {
        return false
    }
    return throwsClause.trimmedDescription != "throws"
}

private func isOpaqueType(_ typeText: String) -> Bool {
    typeText == "some" || typeText.hasPrefix("some ") || typeText.contains(" some ")
}

func isVoidReturnType(_ typeText: String?) -> Bool {
    guard let typeText else {
        return true
    }
    return typeText == "Void" || typeText == "()" || typeText == "(Void)"
}

private func optionalStorageType(_ typeText: String) -> String {
    if typeText.hasPrefix("any ")
        || typeText.hasSuffix("?")
        || typeText.contains("->")
        || typeText.contains("&") {
        return "(\(typeText))?"
    }
    return "\(typeText)?"
}
