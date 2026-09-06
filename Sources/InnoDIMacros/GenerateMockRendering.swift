import Foundation
import SwiftSyntax

// Protocol requirement lowering and generated mock source rendering.
struct RenderedFunctionMock {
    let snippet: String
    let usesNotStubbedError: Bool
    let missingStubExpression: String?
    let recordedCallCountExpression: String
}
func renderFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames,
    concurrent: Bool = false
) -> RenderedFunctionMock? {
    if findStandardMainActorAttribute(in: function.attributes) != nil {
        return nil
    }
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
    if isGeneric,
       typedThrowsFailureType(
           function.signature.effectSpecifiers?.throwsClause?.trimmedDescription
       ) != nil {
        return nil
    }
    if concurrent {
        guard !isGeneric else { return nil }
        return renderConcurrentTypedFunctionMock(
            function: function,
            names: names
        )
    }
    if isGeneric {
        return renderGenericFunctionMock(function: function, names: names)
    }
    return renderTypedFunctionMock(function: function, names: names)
}

private func renderConcurrentTypedFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsSpelling = signature.effectSpecifiers?.throwsClause?.trimmedDescription
    let isThrowing = throwsSpelling != nil
    let typedFailure = typedThrowsFailureType(throwsSpelling)

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    guard let callParameters = renderableCallParameters(parameters) else {
        return nil
    }
    let returnsVoid = isVoidReturnType(
        signature.returnClause?.type.trimmedDescription
    )
    let returnType = signature.returnClause?.type.trimmedDescription ?? "Void"
    if !returnsVoid && isOpaqueType(returnType) { return nil }
    let parametersRendered = callParameters.map(\.declaration)
        .joined(separator: ", ")
    var effects: [String] = []
    if isAsync { effects.append("async") }
    if let throwsSpelling { effects.append(throwsSpelling) }
    let effectsRendered = effects.isEmpty ? "" : " " + effects.joined(separator: " ")
    let callBox = "__innodi_\(names.callsProperty)Box"
    let callFields = callParameters
        .map { "        let \($0.fieldIdentifier): \($0.type)" }
        .joined(separator: "\n")
    let recordArgs = callParameters
        .map { "\($0.fieldLabel): \($0.argumentIdentifier)" }
        .joined(separator: ", ")
    let stubbedBox = "__innodi_\(names.stem)StubbedBox"
    var lines = [
        "    struct \(names.callStructName): Sendable {",
        callFields,
        "    }",
        "    private let \(callBox) = InnoDITesting.DIConcurrentValueBox<[\(names.callStructName)]>([])",
        "    var \(names.callsProperty): [\(names.callStructName)] { \(callBox).snapshot() }",
    ].filter { !$0.isEmpty }

    if let typedFailure {
        let box = "__innodi_\(names.resultProperty)Box"
        let successType = returnsVoid ? "Void" : returnType
        let resultType = "Result<\(successType), \(typedFailure)>?"
        lines.append("    private let \(box) = InnoDITesting.DIConcurrentValueBox<\(resultType)>(nil)")
        lines.append("    private let \(stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)")
        lines.append("    var \(names.resultProperty): \(resultType) {")
        lines.append("        get { \(box).snapshot() }")
        lines.append("        set {")
        lines.append("            \(box).replace(with: newValue)")
        lines.append("            \(stubbedBox).replace(with: newValue != nil)")
        lines.append("        }")
        lines.append("    }")
    } else if !returnsVoid {
        if isThrowing {
            let box = "__innodi_\(names.resultProperty)Box"
            lines.append("    private let \(box) = InnoDITesting.DIConcurrentValueBox<Result<\(returnType), Error>>(.failure(_InnoDIMockNotStubbed(selector: \"\(names.resultProperty)\")))")
            lines.append("    private let \(stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)")
            lines.append("    var \(names.resultProperty): Result<\(returnType), Error> {")
            lines.append("        get { \(box).snapshot() }")
            lines.append("        set {")
            lines.append("            \(box).replace(with: newValue)")
            lines.append("            \(stubbedBox).replace(with: true)")
            lines.append("        }")
            lines.append("    }")
        } else {
            let box = "__innodi_\(names.returnProperty)Box"
            let storageType = optionalStorageType(returnType)
            lines.append("    private let \(box) = InnoDITesting.DIConcurrentValueBox<\(storageType)>(nil)")
            lines.append("    private let \(stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)")
            lines.append("    var \(names.returnProperty): \(storageType) {")
            lines.append("        get { \(box).snapshot() }")
            lines.append("        set {")
            lines.append("            \(box).replace(with: newValue)")
            lines.append("            \(stubbedBox).replace(with: true)")
            lines.append("        }")
            lines.append("    }")
        }
    } else if isThrowing {
        let box = "__innodi_\(names.thrownErrorProperty)Box"
        lines.append("    private let \(box) = InnoDITesting.DIConcurrentValueBox<Error?>(nil)")
        lines.append("    private let \(stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)")
        lines.append("    var \(names.thrownErrorProperty): Error? {")
        lines.append("        get { \(box).snapshot() }")
        lines.append("        set {")
        lines.append("            \(box).replace(with: newValue)")
        lines.append("            \(stubbedBox).replace(with: true)")
        lines.append("        }")
        lines.append("    }")
    }

    let returnFragment = returnsVoid ? "" : " -> \(returnType)"
    lines.append("    func \(baseName)(\(parametersRendered))\(effectsRendered)\(returnFragment) {")
    lines.append("        \(callBox).update { $0.append(.init(\(recordArgs))) }")
    if typedFailure != nil {
        let box = "__innodi_\(names.resultProperty)Box"
        lines.append("        guard let result = \(box).snapshot() else {")
        lines.append("            preconditionFailure(\"\(names.resultProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
        lines.append("        }")
        lines.append("        return try result.get()")
    } else if !returnsVoid {
        if isThrowing {
            let box = "__innodi_\(names.resultProperty)Box"
            lines.append("        return try \(box).snapshot().get()")
        } else {
            let box = "__innodi_\(names.returnProperty)Box"
            let storedReturn = renderStoredReturn(
                storage: "\(box).snapshot()",
                type: returnType
            )
            lines.append("        guard \(stubbedBox).snapshot() else {")
            lines.append("            preconditionFailure(\"\(names.returnProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
            lines.append("        }")
            lines.append("        \(storedReturn)")
        }
    } else if isThrowing {
        let box = "__innodi_\(names.thrownErrorProperty)Box"
        lines.append("        if let error = \(box).snapshot() { throw error }")
    }
    lines.append("    }")

    return RenderedFunctionMock(
        snippet: lines.joined(separator: "\n"),
        usesNotStubbedError: typedFailure == nil && isThrowing && !returnsVoid,
        missingStubExpression: requiresFunctionStub(
            returnsVoid: returnsVoid,
            isThrowing: isThrowing
        ) ? "!\(stubbedBox).snapshot() ? \"\(names.stem)\" : nil" : nil,
        recordedCallCountExpression: "\"\(names.stem)\": \(names.callsProperty).count"
    )
}

private func renderTypedFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsSpelling = signature.effectSpecifiers?.throwsClause?.trimmedDescription
    let isThrowing = throwsSpelling != nil
    let typedFailure = typedThrowsFailureType(throwsSpelling)

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
    let parametersRendered = callParameters.map(\.declaration)
        .joined(separator: ", ")
    var effectSpecifierTokens: [String] = []
    if isAsync { effectSpecifierTokens.append("async") }
    if let throwsSpelling { effectSpecifierTokens.append(throwsSpelling) }
    let effectSpecifiersJoined = effectSpecifierTokens.isEmpty
        ? ""
        : " " + effectSpecifierTokens.joined(separator: " ")

    var snippetLines: [String] = []

    let callFields = callParameters
        .map { "        let \($0.fieldIdentifier): \($0.type)" }
        .joined(separator: "\n")
    snippetLines.append("    struct \(names.callStructName) {")
    if !callFields.isEmpty {
        snippetLines.append(callFields)
    }
    snippetLines.append("    }")
    snippetLines.append("    private(set) var \(names.callsProperty): [\(names.callStructName)] = []")

    let stubbedStorage = "__innodi_\(names.stem)IsStubbed"
    if !returnsVoid {
        snippetLines.append("    private var \(stubbedStorage) = false")
        if let typedFailure {
            snippetLines.append(
                "    private var __innodi_\(names.resultProperty)Storage: Result<\(returnTypeRendered), \(typedFailure)>?"
            )
            snippetLines.append(
                computedStubProperty(
                    name: names.resultProperty,
                    type: "Result<\(returnTypeRendered), \(typedFailure)>?",
                    storage: "__innodi_\(names.resultProperty)Storage",
                    stubbedStorage: stubbedStorage,
                    nilMeansMissing: true
                )
            )
        } else if isThrowing {
            // `Result<T, Error>` keeps the typed `throw` lossy but lets the
            // mock author choose between `.success(value)` and `.failure(error)`
            // with a single assignment. The default failure prompts the test
            // author with the missing stub identifier through the nested
            // `_InnoDIMockNotStubbed` error.
            let storage = "__innodi_\(names.resultProperty)Storage"
            snippetLines.append("    private var \(storage): Result<\(returnTypeRendered), Error> = .failure(_InnoDIMockNotStubbed(selector: \"\(names.resultProperty)\"))")
            snippetLines.append(
                computedStubProperty(
                    name: names.resultProperty,
                    type: "Result<\(returnTypeRendered), Error>",
                    storage: storage,
                    stubbedStorage: stubbedStorage
                )
            )
        } else {
            let storage = "__innodi_\(names.returnProperty)Storage"
            let storageType = optionalStorageType(returnTypeRendered)
            snippetLines.append("    private var \(storage): \(storageType)")
            snippetLines.append(
                computedStubProperty(
                    name: names.returnProperty,
                    type: storageType,
                    storage: storage,
                    stubbedStorage: stubbedStorage
                )
            )
        }
    } else if let typedFailure {
        snippetLines.append("    private var \(stubbedStorage) = false")
        let storage = "__innodi_\(names.resultProperty)Storage"
        snippetLines.append("    private var \(storage): Result<Void, \(typedFailure)>?")
        snippetLines.append(
            computedStubProperty(
                name: names.resultProperty,
                type: "Result<Void, \(typedFailure)>?",
                storage: storage,
                stubbedStorage: stubbedStorage,
                nilMeansMissing: true
            )
        )
    } else if isThrowing {
        // Even a Void-returning throwing function needs an opt-in error
        // hook so tests can simulate the failure path.
        snippetLines.append("    private var \(stubbedStorage) = false")
        let storage = "__innodi_\(names.thrownErrorProperty)Storage"
        snippetLines.append("    private var \(storage): Error?")
        snippetLines.append(
            computedStubProperty(
                name: names.thrownErrorProperty,
                type: "Error?",
                storage: storage,
                stubbedStorage: stubbedStorage
            )
        )
    }

    let recordArgs = callParameters
        .map { "\($0.fieldLabel): \($0.argumentIdentifier)" }
        .joined(separator: ", ")
    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    snippetLines.append("    func \(baseName)(\(parametersRendered))\(effectSpecifiersJoined)\(returnFragment) {")
    snippetLines.append("        \(names.callsProperty).append(.init(\(recordArgs)))")
    if typedFailure != nil {
        snippetLines.append("        guard let result = \(names.resultProperty) else {")
        snippetLines.append("            preconditionFailure(\"\(names.resultProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
        snippetLines.append("        }")
        snippetLines.append("        return try result.get()")
    } else if !returnsVoid {
        if isThrowing {
            snippetLines.append("        return try \(names.resultProperty).get()")
        } else {
            snippetLines.append("        guard \(stubbedStorage) else {")
            snippetLines.append("            preconditionFailure(\"\(names.returnProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
            snippetLines.append("        }")
            snippetLines.append("        \(renderStoredReturn(storage: names.returnProperty, type: returnTypeRendered))")
        }
    } else if isThrowing {
        snippetLines.append("        if let error = \(names.thrownErrorProperty) {")
        snippetLines.append("            throw error")
        snippetLines.append("        }")
    }
    snippetLines.append("    }")

    return RenderedFunctionMock(
        snippet: snippetLines.joined(separator: "\n"),
        usesNotStubbedError: typedFailure == nil && isThrowing && !returnsVoid,
        missingStubExpression: requiresFunctionStub(
            returnsVoid: returnsVoid,
            isThrowing: isThrowing
        ) ? "!\(stubbedStorage) ? \"\(names.stem)\" : nil" : nil,
        recordedCallCountExpression: "\"\(names.stem)\": \(names.callsProperty).count"
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
    let parametersRendered = callParameters.map(\.declaration)
        .joined(separator: ", ")
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
    let handlerArguments = callParameters.map(\.argumentIdentifier)
        .joined(separator: ", ")
    let handlerArgumentArray = handlerArguments.isEmpty ? "[]" : "[\(handlerArguments)]"

    var snippetLines: [String] = []
    let callFields = callParameters
        .map { "        let \($0.fieldIdentifier): \($0.type)" }
        .joined(separator: "\n")
    snippetLines.append("    struct \(names.callStructName) {")
    if !callFields.isEmpty {
        snippetLines.append(callFields)
    }
    snippetLines.append("    }")
    snippetLines.append("    private(set) var \(names.callsProperty): [\(names.callStructName)] = []")
    let handlerType = "(([Any])\(handlerEffectsJoined) -> \(handlerReturnType))?"
    let handlerStorage = "__innodi_\(names.handlerProperty)Storage"
    let stubbedStorage = "__innodi_\(names.stem)IsStubbed"
    snippetLines.append("    private var \(handlerStorage): \(handlerType)")
    snippetLines.append("    private var \(stubbedStorage) = false")
    snippetLines.append(
        computedStubProperty(
            name: names.handlerProperty,
            type: handlerType,
            storage: handlerStorage,
            stubbedStorage: stubbedStorage,
            nilMeansMissing: true
        )
    )

    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    snippetLines.append("    func \(baseName)\(genericParameterClause)(\(parametersRendered))\(effectSpecifiersJoined)\(returnFragment)\(genericWhereClause) {")
    let recordArgs = callParameters.map {
        "\($0.fieldLabel): \($0.argumentIdentifier)"
    }.joined(separator: ", ")
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
        usesNotStubbedError: false,
        missingStubExpression: "!\(stubbedStorage) ? \"\(names.stem)\" : nil",
        recordedCallCountExpression: "\"\(names.stem)\": \(names.callsProperty).count"
    )
}

struct RenderedVariableMock {
    let snippet: String
    let missingStubExpression: String
}

func renderVariableMock(
    variable: VariableDeclSyntax,
    concurrent: Bool = false
) -> RenderedVariableMock? {
    if findStandardMainActorAttribute(in: variable.attributes) != nil {
        return nil
    }
    if unsupportedMockIsolation(in: variable.attributes) != nil {
        return nil
    }
    if !variable.modifiers.isEmpty {
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
    let stubbedName = "__innodi_\(name.safeLowerCamelIdentifier)_\(name.stableIdentifierSuffix)IsStubbed"
    let storageType = optionalStorageType(type)
    if concurrent {
        let boxName = "\(storageName)Box"
        let stubbedBoxName = "\(stubbedName)Box"
        return RenderedVariableMock(
            snippet: """
            private let \(boxName) = InnoDITesting.DIConcurrentValueBox<\(storageType)>(nil)
            private let \(stubbedBoxName) = InnoDITesting.DIConcurrentValueBox(false)
            var \(escapedName): \(type) {
                get {
                    guard \(stubbedBoxName).snapshot() else {
                        preconditionFailure("\(name) was not set on \\(Self.self) before it was read")
                    }
                    \(renderStoredReturn(storage: "\(boxName).snapshot()", type: type))
                }
                set {
                    \(boxName).replace(with: newValue)
                    \(stubbedBoxName).replace(with: true)
                }
            }
            """,
            missingStubExpression:
                "!\(stubbedBoxName).snapshot() ? \"\(name)\" : nil"
        )
    }
    return RenderedVariableMock(
        snippet: """
            private var \(storageName): \(storageType)
            private var \(stubbedName) = false
            var \(escapedName): \(type) {
                get {
                    guard \(stubbedName) else {
                        preconditionFailure("\(name) was not set on \\(Self.self) before it was read")
                    }
                    \(renderStoredReturn(storage: storageName, type: type))
                }
                set {
                    \(storageName) = newValue
                    \(stubbedName) = true
                }
            }
        """,
        missingStubExpression: "!\(stubbedName) ? \"\(name)\" : nil"
    )
}

private struct RenderableCallParameter {
    let fieldLabel: String
    let fieldIdentifier: String
    let argumentIdentifier: String
    let type: String
    let declaration: String
}

private func renderableCallParameters(
    _ parameters: FunctionParameterListSyntax,
    eraseTypes: Bool = false
) -> [RenderableCallParameter]? {
    var usedNames: [String: Int] = [:]
    var rendered: [RenderableCallParameter] = []
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
        let argumentName: String
        let declaration: String
        let parameterWithoutComma = parameter.with(\.trailingComma, nil)
        if internalName == "_" {
            argumentName = unescapedFieldName.escapedSwiftIdentifier
            declaration = parameterWithoutComma
                .with(
                    \.secondName,
                    .identifier(unescapedFieldName, leadingTrivia: .space)
                )
                .trimmedDescription
        } else {
            argumentName = internalName.unescapedIdentifier.escapedSwiftIdentifier
            declaration = parameterWithoutComma.trimmedDescription
        }
        rendered.append(
            RenderableCallParameter(
                fieldLabel: unescapedFieldName,
                fieldIdentifier: unescapedFieldName.escapedSwiftIdentifier,
                argumentIdentifier: argumentName,
                type: typeText,
                declaration: declaration
            )
        )
    }
    return rendered
}

private func requiresFunctionStub(
    returnsVoid: Bool,
    isThrowing: Bool
) -> Bool {
    !returnsVoid || isThrowing
}

private func computedStubProperty(
    name: String,
    type: String,
    storage: String,
    stubbedStorage: String,
    nilMeansMissing: Bool = false
) -> String {
    let stateUpdate = nilMeansMissing ? "newValue != nil" : "true"
    return """
        var \(name): \(type) {
            get { \(storage) }
            set {
                \(storage) = newValue
                \(stubbedStorage) = \(stateUpdate)
            }
        }
    """
}

private func renderStoredReturn(storage: String, type: String) -> String {
    if type.hasSuffix("?") || type.hasSuffix("!") {
        return "return \(storage) ?? nil"
    }
    return """
        guard let value = \(storage) else {
            preconditionFailure("Stub storage for \(type) was unexpectedly empty")
        }
        return value
    """
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
    let spelling = throwsClause.trimmedDescription
    return spelling != "throws" && typedThrowsFailureType(spelling) == nil
}

private func typedThrowsFailureType(_ spelling: String?) -> String? {
    guard let spelling,
          spelling.hasPrefix("throws("),
          spelling.hasSuffix(")") else {
        return nil
    }
    let start = spelling.index(spelling.startIndex, offsetBy: 7)
    let end = spelling.index(before: spelling.endIndex)
    let failure = spelling[start..<end]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return failure.isEmpty ? nil : failure
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
